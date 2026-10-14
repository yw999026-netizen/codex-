classdef LabEngine < handle
    % Experiment workflow, sole scheduler owner, immutable session logs.
    % Public API (all actions return logical accepted, except void tick/inject):
    % newExperiment(group), setGroup(group), setPose(stopped,positioned,oriented[,source]),
    % requestWindow('BASELINE'|'HEAT'), startRun(), returnToMeasure(), finish(),
    % recover(), inject('COMM_FAILURE'|'OVERRANGE'|'NONFINITE'|'CLEAR'), tick().
    % Additional NONFINITE_FLOW/WATER_IN/WATER_OUT/VALVE_FEEDBACK/TEMPERATURE
    % injections exercise the all-sensor window quality contract.
    % tick samples at most once per call, using actual monotonic wall time;
    % sampling omissions never become fabricated intermediate samples.
    % Optional constructor clock is a deterministic-test elapsed-time source.
    properties (SetAccess=private)
        Config
        State = 'IDLE'
        Group = '0'
        Pose = [false false false]
        Baseline = []
        Raw
        Events
        Windows
        Latest = []
        ExperimentId = ''
        SimulationTimeS = 0
        Scheduler
        Transport
        Active = false
    end
    properties (Access=private)
        Clock
        Origin = 0
        LastWall = 0
        LastSampleWall = -Inf
        Pending = []
        InTick = false
        RawTemplate
        EventTemplate
        WindowTemplate
    end
    methods
        function obj=LabEngine(cfg,clock)
            if nargin<1, cfg=itl.defaultConfig(); end
            if ~strcmp(cfg.mode,'simulation')
                error('itl:SimulationOnly','Only explicit simulation mode is implemented; hardware access rejected.');
            end
            validateattributes(cfg.C,{'numeric'},{'size',[3 3],'finite'});
            validateattributes(cfg.sampleIntervalS,{'numeric'},{'scalar','positive','finite'});
            validateattributes(cfg.settleS,{'numeric'},{'scalar','nonnegative','finite'});
            validateattributes(cfg.windowPoints,{'numeric'},{'scalar','integer','>=',2});
            validateattributes(cfg.thermalAcceleration,{'numeric'},{'scalar','positive','finite'});
            validateattributes(cfg.probeRangeUm,{'numeric'},{'scalar','positive','finite'});
            validateattributes(cfg.openPercent,{'numeric'},{'scalar','finite','>=',0,'<=',100});
            if nargin<2, token=tic; clock=@()toc(token); end
            obj.Config=cfg; obj.Clock=clock;
            [obj.RawTemplate,obj.EventTemplate,obj.WindowTemplate]=itl.recordTemplates();
            obj.newExperiment('0');
        end
        function accepted=newExperiment(obj,group)
            if nargin<2, group='0'; end
            accepted=false;
            if obj.Active && ~ismember(obj.State,{'FINISHED','IDLE'})
                obj.note('REJECTED','Finish the active experiment before creating another.'); return
            end
            if ~ismember(group,obj.Config.groups), return; end
            obj.State='IDLE'; obj.Group=group; obj.Pose=[false false false];
            obj.Baseline=[]; obj.Latest=[]; obj.Active=false; obj.Pending=[];
            obj.Raw=repmat(obj.RawTemplate,0,1); obj.Events=repmat(obj.EventTemplate,0,1);
            obj.Windows=repmat(obj.WindowTemplate,0,1);
            obj.Scheduler=itl.SerialScheduler(); obj.Transport=itl.SimTransport();
            obj.Origin=obj.Clock(); obj.LastWall=0; obj.LastSampleWall=-Inf; obj.SimulationTimeS=0;
            persistent sequence
            if isempty(sequence), sequence=0; end
            sequence=sequence+1;
            stamp=itl.utcNow(); obj.ExperimentId=sprintf('SIM-%s-%04d',strrep(strrep(strrep(stamp,':',''),'-',''),'.',''),sequence);
            obj.note('NEW_EXPERIMENT',obj.Config.statement); accepted=true;
        end
        function accepted=setGroup(obj,group)
            accepted=false;
            if obj.Active || ~strcmp(obj.State,'IDLE')
                obj.note('REJECTED','Cooling group is frozen for this experiment.'); return
            end
            if ~ismember(group,obj.Config.groups), return; end
            obj.Group=group; obj.note('GROUP_SELECTED',group); accepted=true;
        end
        function accepted=setPose(obj,stopped,positioned,oriented,source)
            if nargin<5, source='operator-in-simulation'; end
            accepted=false;
            if ismember(obj.State,{'RUNNING','FAULT','FINISHED'})
                obj.note('REJECTED','Pose confirmations unavailable in the current state.'); return
            end
            obj.Pose=logical([stopped positioned oriented]);
            obj.note('POSE_CONFIRMATION',jsonencode(struct('values',obj.Pose,'source',source))); accepted=true;
            if ~all(obj.Pose) && ~isempty(obj.Pending), obj.closeWindow(false,'POSE_LOST'); end
        end
        function accepted=requestWindow(obj,kind)
            accepted=false;
            if ~ismember(kind,{'BASELINE','HEAT'}), return; end
            if ~isempty(obj.Pending) || ~ismember(obj.State,{'IDLE','READY','RETURNING'}) || ~all(obj.Pose)
                obj.note('REJECTED','Window requires stopped / positioned / oriented confirmations.'); return
            end
            if strcmp(kind,'BASELINE') && ~isempty(obj.Baseline)
                obj.note('REJECTED','A cold baseline already exists and cannot be replaced.'); return
            end
            if strcmp(kind,'HEAT') && (isempty(obj.Baseline) || ~strcmp(obj.State,'RETURNING'))
                obj.note('REJECTED','Heat measurement requires a cold baseline, explicit return and fresh pose confirmations.'); return
            end
            obj.Active=true;
            obj.Pending=struct('kind',kind,'requested',itl.utcNow(),'requestedWall',obj.wall(), ...
                'samples',zeros(0,3),'times',{{}},'walls',zeros(0,1));
            obj.State='SETTLING'; obj.note('WINDOW_REQUEST',kind); accepted=true;
        end
        function accepted=startRun(obj)
            accepted=false;
            if isempty(obj.Baseline) || ~strcmp(obj.State,'READY') || ~isempty(obj.Pending)
                obj.note('REJECTED','Running requires a completed cold baseline and READY state.'); return
            end
            obj.Pose=[false false false]; obj.State='RUNNING'; obj.Active=true;
            obj.note('RUN_START',['Fixed group ' obj.Group]); obj.commandValves(obj.groupCommand());
            accepted=~strcmp(obj.State,'FAULT');
        end
        function accepted=returnToMeasure(obj)
            accepted=false;
            if isempty(obj.Baseline) || ~ismember(obj.State,{'RUNNING','READY'})
                obj.note('REJECTED','Return requires a baseline and RUNNING or READY state.'); return
            end
            obj.State='RETURNING'; obj.Pose=[false false false];
            obj.note('RETURN_REQUEST','Operator must stop and return manually; no CNC commands are sent.'); accepted=true;
        end
        function accepted=finish(obj)
            accepted=false;
            if strcmp(obj.State,'FINISHED'), return; end
            if ~isempty(obj.Pending), obj.closeWindow(false,'CANCELLED'); end
            obj.State='FINISHED'; obj.Pose=[false false false];
            obj.note('FINISH_REQUEST','Request simulation valves at zero.');
            obj.commandValves(zeros(1,6)); accepted=strcmp(obj.State,'FINISHED');
            if accepted, obj.note('EXPERIMENT_FINISH','Simulation zero-command write completed.'); end
        end
        function accepted=recover(obj)
            accepted=false;
            if ~strcmp(obj.State,'FAULT'), return; end
            obj.Transport.inject('CLEAR'); obj.Pose=[false false false];
            if isempty(obj.Baseline), obj.State='IDLE'; else, obj.State='READY'; end
            obj.note('RECOVERY','Baseline retained; all pose checks cleared; no automatic window.'); accepted=true;
        end
        function inject(obj,kind)
            obj.Transport.inject(kind); obj.note('SIMULATION_INJECTION',kind);
        end
        function tick(obj)
            if obj.InTick || ismember(obj.State,{'FAULT','FINISHED'}), return; end
            obj.InTick=true; guard=onCleanup(@()obj.releaseTick()); %#ok<NASGU>
            now=obj.wall(); delta=max(0,now-obj.LastWall); obj.LastWall=now;
            obj.SimulationTimeS=obj.SimulationTimeS+delta*obj.Config.thermalAcceleration;
            if now-obj.LastSampleWall < obj.Config.sampleIntervalS-1e-9, return; end
            obj.LastSampleWall=now;
            if ~isempty(obj.Pending) && now-obj.Pending.requestedWall>=obj.Config.settleS
                if ~all(obj.Pose), obj.closeWindow(false,'POSE_LOST'); else, obj.State='MEASURING'; end
            end
            thermal=obj.SimulationTimeS; running=strcmp(obj.State,'RUNNING');
            obj.Scheduler.enqueue('READ_FRAME',@()obj.Transport.readFrame(thermal,running,obj.Config.C), ...
                @(result,err)obj.readComplete(result,err));
            obj.Scheduler.drain();
        end
        function data=metadata(obj)
            data=struct('experiment_id',obj.ExperimentId,'mode','simulation','export_actual_time_iso',itl.utcNow(), ...
                'state',obj.State,'group',obj.Group,'baseline_probe_um',obj.Baseline, ...
                'C_probe_um_to_xyz_um',obj.Config.C,'displacement_convention','XYZ = C * (baseline_probe - current_probe)', ...
                'probe_sign_convention','Decreasing probe reading produces positive C-column contribution to XYZ; simulation only, field polarity unverified.', ...
                'config',obj.Config,'statement',obj.Config.statement, ...
                'clock_definition','actual_time_iso is UTC; elapsed_wall_s is monotonic real time; simulation_time_s is accelerated thermal time', ...
                'hardware_adapter_status','UNIMPLEMENTED: no real serial/modbus I/O permitted');
        end
    end
    methods (Access=private)
        function t=wall(obj), t=max(0,obj.Clock()-obj.Origin); end
        function releaseTick(obj), obj.InTick=false; end
        function command=groupCommand(obj)
            command=zeros(1,6);
            for k=1:3
                if contains(obj.Group,char('A'+k-1)), command(2*k-1:2*k)=obj.Config.openPercent; end
            end
        end
        function commandValves(obj,command)
            obj.Scheduler.enqueue('SET_VALVES',@()obj.Transport.setValves(command),@(result,err)obj.writeComplete(result,err));
            obj.Scheduler.drain();
        end
        function writeComplete(obj,result,err)
            if ~isempty(err), obj.enterFault(err); return; end
            obj.note('SIM_VALVE_WRITE',jsonencode(result));
        end
        function readComplete(obj,frame,err)
            row=obj.common(obj.RawTemplate);
            if isempty(err)
                for k=1:18, row.(sprintf('temperature_%02d_c',k))=frame.temperature(k); end
                for k=1:3, row.(sprintf('probe_um_%d',k))=frame.probes(k); end
                for k=1:6
                    row.(sprintf('flow_sim_%d_l_min',k))=frame.flow(k);
                    row.(sprintf('water_in_sim_%d_c',k))=frame.waterIn(k);
                    row.(sprintf('water_out_sim_%d_c',k))=frame.waterOut(k);
                    row.(sprintf('valve_command_%d_percent',k))=frame.valveCommand(k);
                    row.(sprintf('valve_sim_feedback_%d_percent',k))=frame.valveFeedback(k);
                end
                sensors=[frame.temperature(:);frame.probes(:);frame.flow(:); ...
                    frame.waterIn(:);frame.waterOut(:);frame.valveFeedback(:)];
                allSensorsFinite=all(isfinite(sensors));
                row.communication_ok=true;
                row.probe_in_range=all(isfinite(frame.probes)) && all(abs(frame.probes)<=obj.Config.probeRangeUm);
                if ~allSensorsFinite, row.error='NONFINITE_SENSOR';
                elseif ~row.probe_in_range, row.error='PROBE_OVERRANGE'; end
                obj.Latest=frame;
            else
                row.error=[err.identifier ': ' err.message]; obj.Latest=[];
            end
            obj.Raw(end+1,1)=row;
            if ~isempty(err), obj.enterFault(err); return; end
            if isempty(obj.Pending), return; end
            if ~all(obj.Pose), obj.closeWindow(false,'POSE_LOST'); return; end
            % Reject any nonfinite sensor feedback even while settling; preserve raw NaNs.
            if ~allSensorsFinite
                obj.closeWindow(false,'NONFINITE_SENSOR'); return
            end
            if ~row.probe_in_range, obj.closeWindow(false,'PROBE_OVERRANGE'); return; end
            if ~strcmp(obj.State,'MEASURING'), return; end
            obj.Pending.samples(end+1,:)=frame.probes;
            obj.Pending.times{end+1}=row.actual_time_iso;
            obj.Pending.walls(end+1,1)=row.elapsed_wall_s;
            if size(obj.Pending.samples,1)>=obj.Config.windowPoints, obj.closeWindow(true,'OK'); end
        end
        function enterFault(obj,err)
            if ~isempty(obj.Pending), obj.closeWindow(false,'COMMUNICATION_FAILURE'); end
            obj.State='FAULT'; obj.Pose=[false false false]; obj.Scheduler.clearQueued();
            obj.note('COMMUNICATION_FAULT',[err.identifier ': ' err.message]);
        end
        function closeWindow(obj,valid,reason)
            pending=obj.Pending; if isempty(pending), return; end
            row=obj.common(obj.WindowTemplate); row.kind=pending.kind; row.valid=valid;
            row.reason=reason; row.count=size(pending.samples,1); row.request_time_iso=pending.requested;
            row.actual_end_iso=itl.utcNow(); row.end_elapsed_wall_s=obj.wall();
            if row.count>0
                row.actual_start_iso=pending.times{1}; row.start_elapsed_wall_s=pending.walls(1);
                average=mean(pending.samples,1); deviations=std(pending.samples,0,1);
                for k=1:3
                    row.(sprintf('probe_mean_%d_um',k))=average(k);
                    row.(sprintf('probe_std_%d_um',k))=deviations(k);
                end
            end
            if valid && strcmp(pending.kind,'BASELINE')
                obj.Baseline=average;
            elseif valid
                xyz=itl.displacementUm(obj.Config.C,obj.Baseline,average(:));
                xyzSamples=itl.displacementUm(obj.Config.C,obj.Baseline,pending.samples')';
                xyzStd=std(xyzSamples,0,1);
                for k=1:3
                    axis=char('x'+k-1);
                    row.(sprintf('xyz_%s_um',axis))=xyz(k);
                    row.(sprintf('xyz_std_%s_um',axis))=xyzStd(k);
                end
            end
            obj.Windows(end+1,1)=row; obj.Pending=[];
            if isempty(obj.Baseline), obj.State='IDLE'; else, obj.State='READY'; end
            obj.note('WINDOW_RESULT',[row.kind ': ' reason]);
        end
        function row=common(obj,row)
            row.experiment_id=obj.ExperimentId; row.mode='simulation'; row.actual_time_iso=itl.utcNow();
            row.elapsed_wall_s=obj.wall(); row.simulation_time_s=obj.SimulationTimeS;
            row.group=obj.Group; row.phase=obj.State;
        end
        function note(obj,event,detail)
            row=obj.common(obj.EventTemplate); row.event=event; row.detail=detail;
            obj.Events(end+1,1)=row;
        end
    end
end
