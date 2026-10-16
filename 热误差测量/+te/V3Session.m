classdef V3Session < handle
    % V3 acquisition/session rules. No transport, GUI, clock or machine I/O.
    % Callers supply toc-based elapsed seconds and UTC strings at each action.
    % A baseline belongs to one start/stop experiment and cannot be overwritten.
    properties (SetAccess = private)
        Mode
        CalibrationVersion
        State = 'stopped'
        SessionID = ''
        BaselineID = ''
        BaselineReady = false
        BaselineProbe = nan(3,1)
        BaselineTemperature = nan(18,1)
        Confirmations = false(1,3)
        Active = []
        Rows = struct([])
        Samples = struct([])
        Windows = struct([])
        Events = struct([])
    end
    properties (Access = private)
        C
        SettleSec
        MeasureSec
        ProbeLimit
        RequiredPoints = 10
        LastElapsed = -Inf
        WindowSequence = 0
        UsedSessionIDs = {}
    end
    methods
        function obj = V3Session(mode,C,settleSec,measureSec,probeLimit,requiredPoints)
            % Physical addressing/register/scaling are not commissioned.
            % Reject real mode before the caller can create a serial object.
            if ~strcmp(mode,'simulation')
                error('te:UnverifiedConfiguration', ...
                    'Real acquisition is blocked: global device map, register convention and scaling are unverified. Select explicit simulation.');
            end
            if ~isequal(size(C),[3 3]) || ~(all(isfinite(C(:))) || all(isnan(C(:))))
                error('te:Calibration','Calibration must be finite 3-by-3, or entirely NaN to mark unavailable XYZ.');
            end
            validateattributes(settleSec,{'numeric'},{'scalar','finite','nonnegative'});
            validateattributes(measureSec,{'numeric'},{'scalar','finite','positive'});
            validateattributes(probeLimit,{'numeric'},{'scalar','finite','positive'});
            if nargin>=6
                validateattributes(requiredPoints,{'numeric'},{'scalar','integer','positive'});
                obj.RequiredPoints=requiredPoints;
            end
            % Identity preserves the actual signed matrix without claiming
            % field verification or treating the filename as a version.
            obj.CalibrationVersion=['matrix:' mat2str(C,17)];
            obj.Mode=mode; obj.C=C; obj.SettleSec=settleSec;
            obj.MeasureSec=measureSec; obj.ProbeLimit=probeLimit;
        end
        function start(obj,id,elapsed,utc)
            if ~strcmp(obj.State,'stopped')
                error('te:SessionActive','Stop and save the existing experiment before starting another.');
            end
            if ~(ischar(id) && isrow(id) && ~isempty(id)) || any(strcmp(id,obj.UsedSessionIDs))
                error('te:SessionIdentity','Each experiment must have a fresh nonempty character-row identity.');
            end
            obj.UsedSessionIDs{end+1}=id;
            obj.SessionID=id; obj.BaselineID=''; obj.BaselineReady=false;
            obj.BaselineProbe=nan(3,1); obj.BaselineTemperature=nan(18,1);
            obj.Rows=struct([]); obj.Samples=struct([]); obj.Windows=struct([]);
            obj.Events=struct([]); obj.Active=[]; obj.Confirmations=false(1,3);
            obj.WindowSequence=0; obj.LastElapsed=-Inf; obj.State='running';
            obj.checkTime(elapsed); obj.event('session_start',elapsed,utc,'');
        end
        function confirm(obj,values,elapsed,utc)
            obj.checkTime(elapsed); obj.expire(elapsed,utc);
            if numel(values)~=3 || any(~ismember(values,[0 1]))
                error('te:Confirmation','Three explicit operator confirmations are required.');
            end
            obj.Confirmations=logical(reshape(values,1,3));
            obj.event('confirmations',elapsed,utc,mat2str(obj.Confirmations));
            if ~isempty(obj.Active) && ~all(obj.Confirmations)
                obj.finish('invalid','confirmation_lost',elapsed,utc);
            end
        end
        function request(obj,kind,elapsed,utc)
            obj.checkTime(elapsed); obj.expire(elapsed,utc);
            if strcmp(obj.State,'fault'), error('te:Fault','Explicit fault recovery is required.'); end
            if ~strcmp(obj.State,'running') || ~isempty(obj.Active)
                error('te:WindowState','A running session without an active window is required.');
            end
            if strcmp(kind,'baseline') && obj.BaselineReady
                error('te:BaselineImmutable','This experiment already owns an immutable baseline. Stop and start a new experiment to zero again.');
            end
            if ~ismember(kind,{'baseline','heat'}), error('te:WindowKind','Unknown window kind.'); end
            if strcmp(kind,'heat') && ~obj.BaselineReady, error('te:BaselineRequired','Set a baseline first.'); end
            if ~all(obj.Confirmations)
                error('te:Confirmation','Confirm stopped spindle, same-direction fixed-point return and independent angular reset for every window.');
            end
            obj.WindowSequence=obj.WindowSequence+1;
            obj.Active=struct('ID',sprintf('%s-W%04d',obj.SessionID,obj.WindowSequence), ...
                'Kind',kind,'RequestElapsedSec',elapsed,'RequestUTC',utc, ...
                'Temperature',zeros(18,0),'Probe',zeros(3,0),'Times',[], ...
                'UTC',{{}},'Phase','settling');
            obj.event('window_requested',elapsed,utc,kind);
        end
        function poll(obj,elapsed,utc,temp,probe,quality,readStartSec,readStartUTC,errorDetail)
            if ~strcmp(obj.State,'running')
                error('te:PollState','Polling requires a running session; faults require explicit recovery.');
            end
            obj.checkTime(elapsed); obj.expire(elapsed,utc);
            if nargin<8, readStartSec=elapsed; readStartUTC=utc; end
            if nargin<9 || isempty(errorDetail), errorDetail='communication_error'; end
            if strcmp(quality,'communication_error')
                % Never retain stale or partial payloads as fresh measurements.
                temp=nan(18,1); probe=nan(3,1);
            elseif ~strcmp(quality,'ok')
                error('te:Quality','Unknown poll quality.');
            elseif numel(temp)~=18 || numel(probe)~=3
                temp=nan(18,1); probe=nan(3,1); quality='invalid_shape';
            elseif any(~isfinite(temp(:))) || any(~isfinite(probe(:)))
                quality='nonfinite';
            elseif any(abs(probe(:))>obj.ProbeLimit)
                quality='probe_overrange';
            end
            windowID=''; phase='running';
            if ~isempty(obj.Active), windowID=obj.Active.ID; phase=obj.Active.Phase; end
            r=struct('Mode',obj.Mode,'Source',obj.Mode,'calibration_version',obj.CalibrationVersion,'SessionID',obj.SessionID, ...
                'BaselineID',obj.BaselineID,'WindowID',windowID,'Phase',phase, ...
                'ElapsedSec',elapsed,'UTC',utc,'ReadStartElapsedSec',readStartSec, ...
                'ReadStartUTC',readStartUTC,'ReadEndElapsedSec',elapsed,'ReadEndUTC',utc,'Quality',quality, ...
                'Temperature',temp(:),'Probe',probe(:));
            obj.Rows(end+1)=r;
            if strcmp(quality,'communication_error')
                obj.fault(elapsed,utc,errorDetail); return;
            end
            if isempty(obj.Active), return; end
            if ~strcmp(quality,'ok')
                obj.finish('invalid',quality,elapsed,utc); return;
            end
            if ~all(obj.Confirmations)
                obj.finish('invalid','confirmation_lost',elapsed,utc); return;
            end
            age=elapsed-obj.Active.RequestElapsedSec;
            if age<obj.SettleSec, return; end
            obj.Active.Phase='measuring'; obj.Rows(end).Phase='measuring';
            obj.Active.Temperature(:,end+1)=temp(:);
            obj.Active.Probe(:,end+1)=probe(:);
            obj.Active.Times(end+1)=elapsed; obj.Active.UTC{end+1}=utc;
        end
        function fault(obj,elapsed,utc,reason)
            obj.checkTime(elapsed); obj.expire(elapsed,utc);
            if ~isempty(obj.Active), obj.finish('invalid',reason,elapsed,utc); end
            obj.Confirmations=false(1,3); obj.State='fault';
            obj.event('fault',elapsed,utc,reason);
        end
        function recover(obj,elapsed,utc)
            obj.checkTime(elapsed); obj.expire(elapsed,utc);
            if ~strcmp(obj.State,'fault'), error('te:Recovery','Recovery requires an existing fault.'); end
            obj.State='running'; obj.Confirmations=false(1,3);
            obj.event('explicit_recovery',elapsed,utc,'baseline retained; fresh confirmations required');
        end
        function stop(obj,elapsed,utc)
            obj.checkTime(elapsed); obj.expire(elapsed,utc);
            if ~isempty(obj.Active), obj.finish('cancelled','operator_stop',elapsed,utc); end
            obj.Confirmations=false(1,3); obj.State='stopped';
            obj.event('session_stop',elapsed,utc,'');
        end
        function [headers,cells] = auditData(obj,kind)
            % Headers exist for zero-row sessions/windows/samples as well.
            switch kind
                case 'rows'
                    headers={'Mode','Source','SessionID','BaselineID','WindowID','Phase','ElapsedSec','UTC','ReadStartElapsedSec','ReadStartUTC','ReadEndElapsedSec','ReadEndUTC','Quality','calibration_version','Temperature','Probe'}; data=obj.Rows;
                case 'samples'
                    headers={'Mode','SessionID','BaselineID','WindowID','Quality','ElapsedSec','UTC','StartElapsedSec','EndElapsedSec','StartUTC','EndUTC','calibration_version','Temperature','Probe','DeltaProbe','XYZ','StdXYZ'}; data=obj.Samples;
                case 'windows'
                    headers={'Mode','SessionID','BaselineID','WindowID','Kind','RequestElapsedSec','RequestUTC','StartElapsedSec','EndElapsedSec','StartUTC','EndUTC','Quality','Reason','PointCount','CloseElapsedSec','CloseUTC','calibration_version'}; data=obj.Windows;
                case 'events'
                    headers={'Mode','SessionID','BaselineID','ElapsedSec','UTC','Event','Detail','calibration_version'}; data=obj.Events;
                otherwise, error('te:Audit','Unknown audit kind.');
            end
            cells=cell(numel(data),numel(headers));
            for k=1:numel(data)
                for j=1:numel(headers)
                    value=data(k).(headers{j});
                    if isnumeric(value) && ~isscalar(value), value=mat2str(value,17); end
                    cells{k,j}=value;
                end
            end
        end
    end
    methods (Access = private)
        function expire(obj,elapsed,utc)
            % One expiry gate serves every timestamped action. The sampling
            % interval is half-open: post-deadline quality/revoke/stop/fault
            % cannot invalidate or cancel points already accepted inside it.
            if isempty(obj.Active), return; end
            deadline=obj.Active.RequestElapsedSec+obj.SettleSec+obj.MeasureSec;
            if elapsed<deadline, return; end
            if numel(obj.Active.Times)<obj.RequiredPoints
                obj.finish('invalid','insufficient_samples',elapsed,utc);
            else
                obj.finish('valid','',elapsed,utc);
            end
        end
        function checkTime(obj,elapsed)
            if ~isscalar(elapsed) || ~isfinite(elapsed) || elapsed<0 || elapsed<obj.LastElapsed
                error('te:Clock','Elapsed time must be finite, nonnegative and monotonic.');
            end
            obj.LastElapsed=elapsed;
        end
        function event(obj,name,elapsed,utc,detail)
            obj.Events(end+1)=struct('Mode',obj.Mode,'calibration_version',obj.CalibrationVersion,'SessionID',obj.SessionID, ...
                'BaselineID',obj.BaselineID,'ElapsedSec',elapsed,'UTC',utc,'Event',name,'Detail',detail);
        end
        function finish(obj,quality,reason,elapsed,utc)
            a=obj.Active;
            startSec=NaN; endSec=NaN; startUTC=''; endUTC='';
            if ~isempty(a.Times)
                startSec=a.Times(1); endSec=a.Times(end);
                startUTC=a.UTC{1}; endUTC=a.UTC{end};
            end
            if strcmp(quality,'valid')
                mt=mean(a.Temperature,2); mp=mean(a.Probe,2);
                if strcmp(a.Kind,'baseline')
                    % request() blocks re-zero; this guard protects finalization too.
                    if obj.BaselineReady, error('te:BaselineImmutable','Baseline is immutable.'); end
                    obj.BaselineID=[obj.SessionID '-B001']; obj.BaselineProbe=mp;
                    obj.BaselineTemperature=mt; obj.BaselineReady=true;
                else
                    delta=mp-obj.BaselineProbe;
                    sampleQuality='valid';
                    if any(~isfinite(obj.C(:))), sampleQuality='calibration_unavailable'; end
                    obj.Samples(end+1)=struct('Mode',obj.Mode,'calibration_version',obj.CalibrationVersion,'SessionID',obj.SessionID, ...
                        'BaselineID',obj.BaselineID,'WindowID',a.ID,'Quality',sampleQuality, ...
                        'ElapsedSec',mean(a.Times),'UTC',utc,'StartElapsedSec',startSec, ...
                        'EndElapsedSec',endSec,'StartUTC',startUTC,'EndUTC',endUTC, ...
                        'Temperature',mt,'Probe',mp,'DeltaProbe',delta, ...
                        'XYZ',obj.C*delta,'StdXYZ',std(obj.C*(a.Probe-obj.BaselineProbe),0,2));
                end
            end
            obj.Windows(end+1)=struct('Mode',obj.Mode,'calibration_version',obj.CalibrationVersion,'SessionID',obj.SessionID, ...
                'BaselineID',obj.BaselineID,'WindowID',a.ID,'Kind',a.Kind, ...
                'RequestElapsedSec',a.RequestElapsedSec,'RequestUTC',a.RequestUTC, ...
                'StartElapsedSec',startSec,'EndElapsedSec',endSec,'StartUTC',startUTC, ...
                'EndUTC',endUTC,'Quality',quality,'Reason',reason,'PointCount',numel(a.Times), ...
                'CloseElapsedSec',elapsed,'CloseUTC',utc);
            obj.Active=[]; obj.Confirmations=false(1,3);
            obj.event(['window_' quality],elapsed,utc,[a.ID ' ' reason]);
        end
    end
end
