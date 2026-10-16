classdef SimTransport < handle
    % Simulation adapter. NO serial/modbus/hardware methods are implemented.
    % Future adapter contract: setValves(1x6 command percent) -> result struct;
    % readFrame(simulationTimeS, isRunning, C) -> temperature/probe/valve/flow/
    % water fields (flow/waterIn/waterOut are 1x6 branch arrays); failures throw
    % MException and missing data stay NaN.
    % Hardware adapter must not use accelerated time as acquisition timestamp.
    properties (SetAccess=private)
        ValveRequested = zeros(1,6)
        ValveWriteStatus = 'NOT_SENT'
        ValveCommand = zeros(1,6)
        ValveFeedback = zeros(1,6)
    end
    properties (Access=private)
        TemperatureRise = zeros(1,18)
        LastTimeS = 0
        FailNext = false
        Overrange = false
        Nonfinite = false
        NonfiniteFields = {}
    end
    methods
        function result=setValves(obj,command)
            obj.checkFailure();
            validateattributes(command,{'numeric'},{'size',[1,6],'finite'});
            records=arrayfun(@(x)itl.valveCommandRecord(x),command);
            obj.ValveRequested=command; obj.ValveCommand=[records.clamped]; obj.ValveFeedback=obj.ValveCommand; obj.ValveWriteStatus='SIMULATED_ACK';
            result=struct('requested_percent',command,'command_percent',obj.ValveCommand,'register_value',NaN(1,6),'write_status',obj.ValveWriteStatus,'sim_feedback_percent',obj.ValveFeedback);
        end
        function frame=readFrame(obj,timeS,running,C)
            obj.checkFailure();
            dt=max(0,timeS-obj.LastTimeS); obj.LastTimeS=timeS;
            cool=mean(reshape(obj.ValveFeedback,2,3),1)/100;
            region=[1 2 2 3 0 2 2 3 2 2 2 2 2 2 2 3 3 3];
            for k=1:18
                if region(k)==0, target=0.1*sin(timeS/1800); else
                    target=(4+0.35*k)*double(running)/(1+1.8*cool(region(k)));
                end
                obj.TemperatureRise(k)=obj.TemperatureRise(k)+(target-obj.TemperatureRise(k))*(1-exp(-dt/1800));
            end
            temp=22+obj.TemperatureRise+0.015*sin(timeS/37+(1:18));
            xyz=[1.8*obj.TemperatureRise(1);2.1*mean(obj.TemperatureRise([2 3]));1.4*obj.TemperatureRise(4)];
            probes=[20;25;22] + C\xyz + 0.02*sin(timeS/31+(1:3)');
            if running, probes=probes+150; end % out of range at working position is retained
            if obj.Overrange, probes(1)=125; end
            if obj.Nonfinite, probes(2)=NaN; end
            flow=2.2*obj.ValveFeedback/100; inlet=[20 20 20.2 20.2 20.1 20.1];
            outlet=inlet+[0.8 0.8 1.1 1.1 0.9 0.9].*(0.2+double(running));
            frame=struct('temperature',temp,'probes',probes', ...
                'valveRequested',obj.ValveRequested,'valveWriteStatus',obj.ValveWriteStatus,'valveCommand',obj.ValveCommand,'valveFeedback',obj.ValveFeedback, ...
                'flow',flow,'waterIn',inlet,'waterOut',outlet);
            for k=1:numel(obj.NonfiniteFields)
                name=obj.NonfiniteFields{k}; values=frame.(name); values(1)=NaN; frame.(name)=values;
            end
        end
        function inject(obj,kind)
            switch kind
                case 'COMM_FAILURE', obj.FailNext=true;
                case 'OVERRANGE', obj.Overrange=true;
                case 'NONFINITE', obj.Nonfinite=true;
                case 'NONFINITE_FLOW', obj.NonfiniteFields{end+1}='flow';
                case 'NONFINITE_WATER_IN', obj.NonfiniteFields{end+1}='waterIn';
                case 'NONFINITE_WATER_OUT', obj.NonfiniteFields{end+1}='waterOut';
                case 'NONFINITE_VALVE_FEEDBACK', obj.NonfiniteFields{end+1}='valveFeedback';
                case 'NONFINITE_TEMPERATURE', obj.NonfiniteFields{end+1}='temperature';
                case 'CLEAR', obj.FailNext=false; obj.Overrange=false; obj.Nonfinite=false; obj.NonfiniteFields={};
                otherwise, error('itl:Injection','Unknown simulation injection');
            end
        end
    end
    methods (Access=private)
        function checkFailure(obj)
            if obj.FailNext
                obj.FailNext=false;
                error('itl:SimCommunication','Injected simulation communication failure');
            end
        end
    end
end
