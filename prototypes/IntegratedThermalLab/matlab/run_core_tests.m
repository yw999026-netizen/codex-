function run_core_tests
% Base MATLAB R2021b behavioral assertions; no instrument toolbox required.
% Run: addpath('matlab'); run_core_tests
wall = 0;
cfg = itl.defaultConfig();
assert(cfg.openPercent==60, 'Agreed demo opening must remain 60 percent');
e = itl.LabEngine(cfg, @clock);
assert(~e.startRun(), 'Run must reject missing baseline');
assert(~e.requestWindow('BASELINE'), 'Baseline requires all pose checks');
e.setPose(true,true,true);
assert(e.requestWindow('BASELINE'));
assert(~e.requestWindow('BASELINE'), 'Repeated pending baseline must reject');
e.tick(); wall = 1; e.tick();
assert(isempty(e.Baseline), 'Settle must precede sample collection');
wall = 2; e.tick();
for k = 1:4, wall = wall+1; e.tick(); end
assert(strcmp(e.State,'READY') && numel(e.Baseline)==3);
b = e.Baseline;
assert(~e.requestWindow('HEAT'), 'READY must not reuse baseline confirmations for heat');
assert(~e.requestWindow('BASELINE') && isequal(e.Baseline,b));
assert(e.startRun() && ~any(e.Pose));
assert(~e.setGroup('ABC'), 'Active group must freeze');
assert(~e.requestWindow('HEAT'), 'Running pose is invalid');
assert(e.returnToMeasure()); e.setPose(true,true,true);
assert(e.requestWindow('HEAT'));
wall=wall+2; e.tick(); e.setPose(false,true,true);
assert(~e.Windows(end).valid && strcmp(e.Windows(end).reason,'POSE_LOST'));
assert(isequal(e.Baseline,b));
assert(e.returnToMeasure() && ~any(e.Pose));
e.setPose(true,true,true); assert(e.requestWindow('HEAT'));
e.inject('OVERRANGE'); wall=wall+2; e.tick();
assert(~e.Windows(end).valid && strcmp(e.Windows(end).reason,'PROBE_OVERRANGE'));
assert(e.Raw(end).probe_um_1 > cfg.probeRangeUm);
e.inject('CLEAR'); assert(e.returnToMeasure() && ~any(e.Pose));
e.setPose(true,true,true); assert(e.requestWindow('HEAT'));
e.inject('COMM_FAILURE'); wall=wall+2; e.tick();
assert(strcmp(e.State,'FAULT') && ~e.Windows(end).valid);
assert(all(isnan([e.Raw(end).probe_um_1,e.Raw(end).probe_um_2,e.Raw(end).probe_um_3])));
assert(e.recover() && isequal(e.Baseline,b) && ~any(e.Pose));
assert(~e.requestWindow('HEAT'), 'Recovery must require fresh confirmations');
e.setPose(true,true,true);
assert(~e.requestWindow('HEAT'), 'Even renewed checks in READY must not bypass explicit return');
assert(e.returnToMeasure() && strcmp(e.State,'RETURNING') && ~any(e.Pose));
assert(~e.requestWindow('HEAT'), 'Return clears checks and requires another fresh confirmation');
e.setPose(true,true,true); assert(e.requestWindow('HEAT'));
wall=wall+2; e.tick(); e.finish();
assert(strcmp(e.Windows(end).reason,'CANCELLED') && ~e.Windows(end).valid);
assert(strcmp(e.State,'FINISHED'));
% A new experiment permits a group change and a new immutable baseline.
e.newExperiment('AB'); e.setPose(true,true,true); assert(e.requestWindow('BASELINE'));
wall=wall+2; e.tick(); for k=1:4, wall=wall+1; e.tick(); end
assert(e.startRun()); wall=wall+10; e.tick(); assert(e.returnToMeasure());
e.setPose(true,true,true); assert(e.requestWindow('HEAT'));
wall=wall+2; e.tick(); for k=1:4, wall=wall+1; e.tick(); end
w=e.Windows(end); assert(w.valid && strcmp(w.kind,'HEAT') && w.count==5);
assert(~e.requestWindow('HEAT'), 'Completed-window READY cannot reuse earlier return confirmations');
assert(all(isfinite([w.xyz_x_um,w.xyz_y_um,w.xyz_z_um])));
assert(abs(w.xyz_x_um - cfg.C(1,:)*([w.probe_mean_1_um;w.probe_mean_2_um;w.probe_mean_3_um]-e.Baseline(:)))<1e-9);
assert(e.Scheduler.MaxConcurrent==1 && ~e.Scheduler.Busy);
assert(e.Raw(end).simulation_time_s>e.Raw(end).elapsed_wall_s);
assert(numel(e.Latest.flow)==6 && numel(e.Latest.waterIn)==6 && numel(e.Latest.waterOut)==6, 'Water readings must be branch-level');
assert(e.Raw(end).valve_command_1_percent==60 && e.Raw(end).valve_command_6_percent==0);
assert(max(abs(e.Latest.flow-[1.32 1.32 1.32 1.32 0 0]))<1e-12);
for branch=1:6
    assert(isfield(e.Raw,sprintf('flow_sim_%d_l_min',branch)));
    assert(isfield(e.Raw,sprintf('water_in_sim_%d_c',branch)));
    assert(isfield(e.Raw,sprintf('water_out_sim_%d_c',branch)));
end
% Loss during settling cannot create an effective window, even with no samples.
x=itl.LabEngine(cfg,@clock); x.setPose(true,true,true); assert(x.requestWindow('BASELINE'));
x.tick(); x.setPose(true,false,true);
assert(~x.Windows(end).valid && x.Windows(end).count==0 && strcmp(x.Windows(end).reason,'POSE_LOST'));
assert(isempty(x.Baseline));
% Nonfinite input remains NaN in raw and rejects a baseline rather than replacing it.
x.setPose(true,true,true); assert(x.requestWindow('BASELINE')); x.inject('NONFINITE');
wall=wall+2; x.tick();
assert(strcmp(x.Windows(end).reason,'NONFINITE_SENSOR') && isnan(x.Raw(end).probe_um_2) && isempty(x.Baseline));
% Every sensor-feedback family invalidates a window when nonfinite.
for bad={'NONFINITE_FLOW','NONFINITE_WATER_IN','NONFINITE_WATER_OUT','NONFINITE_VALVE_FEEDBACK','NONFINITE_TEMPERATURE'}
    sensor=itl.LabEngine(cfg,@clock); sensor.setPose(true,true,true);
    assert(sensor.requestWindow('BASELINE')); sensor.inject(bad{1}); sensor.tick();
    assert(~sensor.Windows(end).valid && strcmp(sensor.Windows(end).reason,'NONFINITE_SENSOR'));
    assert(strcmp(sensor.Raw(end).error,'NONFINITE_SENSOR') && isempty(sensor.Baseline));
end
% Failed communication outside a window still faults and keeps a timestamped NaN record.
y=itl.LabEngine(cfg,@clock); y.inject('COMM_FAILURE'); y.tick();
assert(strcmp(y.State,'FAULT') && isempty(y.Windows) && ~y.Raw(end).communication_ok);
assert(y.recover() && strcmp(y.State,'IDLE') && ~any(y.Pose));
% No requested window may collect before the full 2-second wall wait.
y.setPose(true,true,true); assert(y.requestWindow('BASELINE'));
wall=wall+1; y.tick(); assert(isempty(y.Windows));
y.finish(); assert(y.Windows(end).count==0 && strcmp(y.Windows(end).reason,'CANCELLED'));
% Common calibration vector fixes sign convention across both implementations.
vector=itl.displacementUm(cfg.C,[10 20 30],[9;18;27]);
assert(max(abs(vector-cfg.C*[-1;-2;-3]))<1e-12, 'Signed C uses current minus baseline probe');
% Finish write failure is not reported as a successful experiment completion.
z=itl.LabEngine(cfg,@clock); z.inject('COMM_FAILURE');
assert(~z.finish() && strcmp(z.State,'FAULT'));
assert(~any(strcmp({z.Events.event},'EXPERIMENT_FINISH')));
assert(z.recover() && z.finish() && strcmp(z.State,'FINISHED'));
% Failed zero-write preserves its own request and leaves last ACK separate.
audit=itl.LabEngine(cfg,@clock); audit.setGroup('ABC'); audit.setPose(true,true,true);
assert(audit.requestWindow('BASELINE'));
wall=wall+2; audit.tick(); for k=1:4, wall=wall+1; audit.tick(); end
assert(audit.startRun()); audit.inject('COMM_FAILURE'); assert(~audit.finish());
failedEvents=audit.Events(strcmp({audit.Events.event},'SIM_VALVE_WRITE_FAILED'));
assert(numel(failedEvents)==1); attempt=jsondecode(failedEvents(end).detail);
assert(all(attempt.requested_percent==0) && all(attempt.command_percent==0));
assert(strcmp(attempt.write_status,'FAILED') && all(isnan(attempt.sim_feedback_percent)));
assert(audit.recover());wall=wall+1;audit.tick();
assert(audit.Raw(end).valve_requested_1_percent==60);
assert(strcmp(audit.Raw(end).valve_write_status_1,'SIMULATED_ACK'));
assert(any(strcmp({audit.Events.event},'SIM_VALVE_WRITE_REQUEST')));
% Reentrant submission is FIFO and cannot create parallel ownership.
q=itl.SerialScheduler(); order=[];
q.enqueue('first',@first,@(~,~)[]); q.enqueue('second',@second,@(~,~)[]); q.drain();
assert(isequal(order,[1 2 3]) && q.MaxConcurrent==1 && ~q.Busy);
% Failure still releases ownership and supplies the actual error to its callback.
seen=false; q.enqueue('error',@fail,@failed); q.drain(); assert(seen && ~q.Busy);
% Export empty and populated logs with stable headers and explicit provenance.
out=tempname; mkdir(out); clean=onCleanup(@()rmdir(out,'s')); %#ok<NASGU>
itl.exportSession(e,out); assert(exist(fullfile(out,'raw.csv'),'file')==2);
t=readtable(fullfile(out,'windows.csv')); assert(any(t.valid));
m=jsondecode(fileread(fullfile(out,'metadata.json'))); assert(strcmp(m.mode,'simulation'));
assert(strcmp(m.displacement_convention,'XYZ = C * (current_probe - baseline_probe)'));
assert(strcmp(m.probe_sign_convention,'Signed C maps current-minus-baseline probe readings to XYZ; demo geometry only, field polarity unverified.'));
empty=itl.LabEngine(cfg,@clock); itl.exportSession(empty,out);
assert(contains(fileread(fullfile(out,'raw.csv')),'actual_time_iso'));
assert(contains(fileread(fullfile(out,'raw.csv')),'flow_sim_6_l_min'));
assert(contains(fileread(fullfile(out,'raw.csv')),'water_out_sim_6_c'));
assert(contains(fileread(fullfile(out,'windows.csv')),'xyz_x_um'));
% A final close/export snapshot must retain partial cancellation and terminal events.
closing=itl.LabEngine(cfg,@clock); closing.setPose(true,true,true);
assert(closing.requestWindow('BASELINE')); wall=wall+2; closing.tick();
assert(closing.finish()); itl.exportSession(closing,out);
closedWindows=readtable(fullfile(out,'windows.csv')); closedEvents=readtable(fullfile(out,'events.csv'));
assert(any(strcmp(closedWindows.reason,'CANCELLED')) && ~any(closedWindows.valid));
assert(any(strcmp(closedEvents.event,'EXPERIMENT_FINISH')));
closedMetadata=jsondecode(fileread(fullfile(out,'metadata.json'))); assert(strcmp(closedMetadata.state,'FINISHED'));
% Real modes are explicitly rejected, never silently converted into simulation.
realCfg=cfg; realCfg.mode='real'; caught=false;
try, itl.LabEngine(realCfg,@clock); catch err, caught=strcmp(err.identifier,'itl:SimulationOnly'); end
assert(caught);
fprintf('PASS: MATLAB core behavioral assertions\n');
    function t=clock, t=wall; end
    function x=first
        order(end+1)=1; q.enqueue('third',@third,@(~,~)[]); q.drain(); x=1;
    end
    function x=second, order(end+1)=2; x=2; end
    function x=third, order(end+1)=3; x=3; end
    function x=fail, error('itl:ExpectedFailure','Expected transport failure'); x=[]; end %#ok<UNRCH>
    function failed(~,err), seen=strcmp(err.identifier,'itl:ExpectedFailure'); end
end
