classdef SerialScheduler < handle
    % Sole FIFO communications owner; callbacks receive (result, MException).
    % enqueue(label, operation, completion), drain(), clearQueued().
    % operation is a zero-argument function. Reentrant drain is a no-op.
    % Future adapters must execute ALL transport operations through this owner.
    properties (SetAccess=private)
        Busy = false
        MaxConcurrent = 0
        Completed = 0
        Trace = {}
    end
    properties (Access=private)
        Queue = {}
    end
    methods
        function enqueue(obj,label,operation,completion)
            obj.Queue{end+1}=struct('label',label,'operation',operation,'completion',completion);
        end
        function drain(obj)
            if obj.Busy, return; end
            obj.Busy=true; obj.MaxConcurrent=max(obj.MaxConcurrent,1);
            guard=onCleanup(@()obj.release()); %#ok<NASGU>
            while ~isempty(obj.Queue)
                task=obj.Queue{1}; obj.Queue(1)=[];
                result=[]; failure=[];
                try, result=task.operation(); catch err, failure=err; end
                obj.Completed=obj.Completed+1;
                obj.Trace{end+1}=task.label;
                task.completion(result,failure);
            end
        end
        function clearQueued(obj), obj.Queue={}; end
    end
    methods (Access=private)
        function release(obj), obj.Busy=false; end
    end
end
