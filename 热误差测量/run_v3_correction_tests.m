function run_v3_correction_tests()
% Behavioral assertions for the V3 session core; no GUI, serial or CNC I/O.
% Authored before implementation. NOT EXECUTED in the correction environment:
% MATLAB is unavailable. Run this function in MATLAB R2021b or newer.
% Regressions guarded: fabricated time, re-zero, stale confirmations, invalid
% settling/measurement data, fault refill, baseline reuse, and lost audit rows.
C = [2 0 0; 0 3 0; 0 0 -4];
s = te.V3Session('simulation', C, 5, 20, 100);
s.start('experiment-A',0,'utc0');
assertThrows(@() s.request('baseline',0,'utc0'),'te:Confirmation');
s.confirm([true true true],0,'utc0');
s.request('baseline',0,'utc0');
s.poll(2.3,'utc2',ones(18,1),[1;2;3],'ok');
s.poll(6.8,'utc6',ones(18,1),[1;2;3],'ok');
for t=[8.9 10.9 13 14 16 18 20 22 24]
    s.poll(t,sprintf('utc%.1f',t),ones(18,1),[1;2;3],'ok');
end
s.poll(25.7,'utc25',ones(18,1),[1;2;3],'ok');
assert(s.BaselineReady && isequal(s.BaselineProbe,[1;2;3]));
assert(isequal([s.Rows.ElapsedSec],[2.3 6.8 8.9 10.9 13 14 16 18 20 22 24 25.7]));
assert(s.Windows(end).PointCount==10 && s.Windows(end).StartElapsedSec==6.8 && s.Windows(end).EndElapsedSec==24);
assert(~any(s.Confirmations));
baselineID = s.BaselineID;
s.confirm([true true true],26,'utc26');
assertThrows(@() s.request('baseline',26,'utc26'),'te:BaselineImmutable');
s.request('heat',26,'utc26');
for t=32:2:50
    s.poll(t,sprintf('utc%d',t),2*ones(18,1),[2;4;6],'ok');
end
s.poll(51,'utc51',2*ones(18,1),[2;4;6],'ok');
assert(numel(s.Samples)==1);
assert(isequal(s.Samples(1).XYZ,C*[1;2;3]));
assert(strcmp(s.Samples(1).BaselineID,baselineID));
assert(s.Samples(1).ElapsedSec==41 && strcmp(s.Samples(1).Mode,'simulation'));
assertThrows(@() s.request('heat',52,'utc52'),'te:Confirmation');
% A communication failure consumes a poll, writes NaNs, invalidates the whole
% active window, clears confirmations and latches a fault. No later refill.
s.confirm([true true true],52,'utc52'); s.request('heat',52,'utc52');
s.poll(58,'utc58',ones(18,1),[2;4;6],'ok');
s.poll(60.6,'utc60',ones(18,1),[2;4;6],'communication_error');
assert(strcmp(s.State,'fault') && ~any(s.Confirmations));
assert(all(isnan(s.Rows(end).Temperature)) && all(isnan(s.Rows(end).Probe)));
assert(strcmp(s.Windows(end).Quality,'invalid') && strcmp(s.Rows(end).Quality,'communication_error'));
[hh,rr]=s.auditData('rows');
assert(strcmp(rr{end,strcmp(hh,'Quality')},'communication_error'));
assert(rr{end,strcmp(hh,'ElapsedSec')}==60.6 && strcmp(rr{end,strcmp(hh,'Mode')},'simulation'));
assert(strcmp(rr{end,strcmp(hh,'SessionID')},'experiment-A'));
assertThrows(@() s.request('heat',61,'utc61'),'te:Fault');
s.recover(62,'utc62');
s.poll(80,'utc80',ones(18,1),[2;4;6],'ok');
assert(numel(s.Samples)==1 && strcmp(s.BaselineID,baselineID));
assertThrows(@() s.request('heat',81,'utc81'),'te:Confirmation');
% Each invalidity must be rejected in settling and measurement, not clamped.
invalidTemp = ones(18,1); invalidTemp(4) = NaN;
invalidProbe = [0;Inf;0];
for phase = [2 7]
    for bad = 1:3
        q = te.V3Session('simulation',C,5,20,100);
        q.start(sprintf('invalid-%d-%d',phase,bad),0,'utc0');
        q.confirm([true true true],0,'utc0'); q.request('baseline',0,'utc0');
        t = ones(18,1); p = [0;0;0];
        if bad==1, t=invalidTemp; elseif bad==2, p=invalidProbe; else, p=[0;101;0]; end
        q.poll(phase,'utcBad',t,p,'ok');
        q.poll(40,'utc40',ones(18,1),[0;0;0],'ok');
        assert(~q.BaselineReady && isempty(q.Samples));
        assert(strcmp(q.Windows(end).Quality,'invalid') && isempty(q.Active));
    end
end
% Revoking any confirmation invalidates even an otherwise stable window.
s.confirm([true true true],82,'utc82'); s.request('heat',82,'utc82');
s.confirm([true false true],83,'utc83');
assert(isempty(s.Active) && strcmp(s.Windows(end).Reason,'confirmation_lost'));
% Confirmation loss is also terminal once measurement has begun.
for phase=[2 7]
    c=te.V3Session('simulation',C,5,20,100); c.start(sprintf('confirm-%d',phase),0,'utc0');
    c.confirm([true true true],0,'utc0'); c.request('baseline',0,'utc0');
    c.poll(phase,'point',ones(18,1),zeros(3,1),'ok');
    c.confirm([false true true],phase+0.1,'revoked');
    c.poll(40,'later',ones(18,1),zeros(3,1),'ok');
    assert(~c.BaselineReady && isempty(c.Active) && strcmp(c.Windows(end).Reason,'confirmation_lost'));
end
% Cancellation before a poll still has a durable window/event record.
s.confirm([true true true],84,'utc84'); s.request('heat',84,'utc84');
s.stop(84.1,'utc84');
assert(strcmp(s.Windows(end).Quality,'cancelled') && s.Windows(end).PointCount==0);
assert(s.Windows(end).CloseElapsedSec==84.1 && strcmp(s.Windows(end).CloseUTC,'utc84'));
assert(~isempty(s.Events) && s.BaselineReady);
oldID=s.SessionID;
assertThrows(@() s.start('experiment-A',0,'utcA'),'te:SessionIdentity');
s.start('experiment-B',0,'utcB');
assert(~strcmp(oldID,s.SessionID) && ~s.BaselineReady && isempty(s.Rows) && isempty(s.Samples));
assertThrows(@() te.V3Session('real',C,5,20,100),'te:UnverifiedConfiguration');
assertThrows(@() ThermalError_18T_3Probe_V3('real'),'te:UnverifiedConfiguration');
% Clock regression must not replace a genuine gap with an invented grid.
s.poll(3.1,'utc3',ones(18,1),zeros(3,1),'ok');
assertThrows(@() s.poll(3,'utc3',ones(18,1),zeros(3,1),'ok'),'te:Clock');
% The settle boundary starts measurement; the deadline poll is excluded.
b=te.V3Session('simulation',C,5,20,100); b.start('boundaries',0,'utc0');
b.confirm([true true true],0,'utc0'); b.request('baseline',0,'utc0');
b.poll(4.99,'settling',ones(18,1),zeros(3,1),'ok');
for t=5:2:23
    b.poll(t,sprintf('utc%d',t),ones(18,1),zeros(3,1),'ok');
end
b.poll(25,'deadline',ones(18,1),[50;50;50],'ok');
assert(b.BaselineReady && isequal(b.BaselineProbe,zeros(3,1)));
assert(b.Windows(end).PointCount==10 && b.Windows(end).StartElapsedSec==5 && b.Windows(end).EndElapsedSec==23);
% An insufficient window expires; later good data cannot fill or validate it.
b.confirm([true true true],26,'utc26'); b.request('heat',26,'utc26');
b.poll(32,'utc32',ones(18,1),zeros(3,1),'ok');
b.poll(51,'utc51',ones(18,1),zeros(3,1),'ok');
b.poll(53,'utc53',ones(18,1),zeros(3,1),'ok');
assert(isempty(b.Samples) && strcmp(b.Windows(end).Reason,'insufficient_samples') && b.Windows(end).PointCount==1);
% The core records actual read boundaries as metadata, including failed reads.
r=te.V3Session('simulation',C,5,20,100); r.start('read-times',0,'utc0');
r.poll(4.7,'read-end',ones(18,1),zeros(3,1),'ok',1.2,'read-start');
assert(r.Rows(1).ReadStartElapsedSec==1.2 && r.Rows(1).ReadEndElapsedSec==4.7);
assert(strcmp(r.Rows(1).ReadStartUTC,'read-start') && strcmp(r.Rows(1).Source,'simulation'));
% Unavailable calibration never creates a demo or a plausible fallback XYZ.
u=te.V3Session('simulation',nan(3),5,20,100); u.start('no-cal',0,'utc0');
for kind={'baseline','heat'}
    base=0; if strcmp(kind{1},'heat'), base=26; end
    u.confirm([true true true],base,'confirm'); u.request(kind{1},base,'request');
    for t=base+(5:2:23), u.poll(t,'point',ones(18,1),ones(3,1),'ok'); end
    u.poll(base+25,'close',ones(18,1),ones(3,1),'ok');
end
assert(all(isnan(u.Samples(1).XYZ)) && strcmp(u.Samples(1).Quality,'calibration_unavailable'));
% Expire the half-open window BEFORE processing outside-window data/actions.
% Each regression changes the old behavior: a bad deadline poll, stop, or
% confirmation revoke previously invalidated/cancelled a completed window.
for kind={'baseline','heat'}
    for bad=1:3
        [e,deadline]=pendingWindow(C,sprintf('expiry-%s-%d',kind{1},bad),kind{1});
        t=ones(18,1); p=ones(3,1); quality='ok'; expected='nonfinite';
        if bad==1, t(1)=NaN; elseif bad==2, p(1)=101; expected='probe_overrange';
        else, quality='communication_error'; expected=quality; end
        e.poll(deadline,'outside',t,p,quality);
        assert(strcmp(e.Windows(end).Quality,'valid') && e.Windows(end).PointCount==10);
        assert(e.BaselineReady && isempty(e.Active) && isempty(e.Rows(end).WindowID));
        assert(strcmp(e.Rows(end).Quality,expected));
        if strcmp(kind{1},'heat')
            assert(numel(e.Samples)==1 && isequal(e.Samples(1).XYZ,C*ones(3,1)));
            assert(strcmp(e.Samples(1).calibration_version,['matrix:' mat2str(C,17)]));
        end
        if bad==3, assert(strcmp(e.State,'fault')); else, assert(strcmp(e.State,'running')); end
        assert(all(diff([e.Events.ElapsedSec])>=0));
    end
    for action={'stop','revoke','fault','request'}
        [e,deadline]=pendingWindow(C,['action-' kind{1} '-' action{1}],kind{1});
        switch action{1}
            case 'stop', e.stop(deadline+1,'outside-stop');
            case 'revoke', e.confirm([false true true],deadline+1,'outside-revoke');
            case 'fault', e.fault(deadline+1,'outside-fault','timer_error');
            case 'request'
                assertThrows(@() e.request('heat',deadline+1,'outside-request'),'te:Confirmation');
        end
        assert(strcmp(e.Windows(end).Quality,'valid') && isempty(e.Active));
        if strcmp(kind{1},'heat'), assert(numel(e.Samples)==1); end
    end
end
ins=te.V3Session('simulation',C,5,20,100); ins.start('insufficient-bad',0,'utc0');
ins.confirm([true true true],0,'utc0'); ins.request('baseline',0,'utc0');
ins.poll(5,'inside',ones(18,1),zeros(3,1),'ok');
ins.poll(25,'outside',nan(18,1),zeros(3,1),'ok');
assert(strcmp(ins.Windows(end).Reason,'insufficient_samples') && ~ins.BaselineReady);
% Every timestamped action rejects a backward time BEFORE mutating state.
clock=te.V3Session('simulation',C,5,20,100); clock.start('clock-actions',0,'utc0');
clock.poll(10,'utc10',ones(18,1),zeros(3,1),'ok');
actions={@() clock.confirm([true true true],9,'past'), ...
    @() clock.request('baseline',9,'past'),@() clock.fault(9,'past','fault'), ...
    @() clock.recover(9,'past'),@() clock.stop(9,'past')};
for k=1:numel(actions), assertThrows(actions{k},'te:Clock'); end
assert(strcmp(clock.State,'running') && ~any(clock.Confirmations) && numel(clock.Events)==1);
% Matrix identity, including signs, is available on every row and audit kind.
expectedVersion=['matrix:' mat2str(C,17)];
assert(strcmp(s.CalibrationVersion,expectedVersion));
for records={s.Rows,u.Samples,b.Windows,s.Events}
    records=records{1};
    if ~isempty(records)
        for k=1:numel(records)
            assert(isfield(records(k),'calibration_version') && ~isempty(records(k).calibration_version));
        end
    end
end
assert(strcmp(b.Windows(1).calibration_version,expectedVersion));
assert(strcmp(s.Rows(1).calibration_version,expectedVersion));
assert(strcmp(s.Events(1).calibration_version,expectedVersion));
assert(strcmp(u.Samples(1).calibration_version,['matrix:' mat2str(nan(3),17)]));
for kind={'rows','samples','windows','events'}
    [versionHeaders,~]=s.auditData(kind{1});
    assert(any(strcmp(versionHeaders,'calibration_version')));
end
% Empty/no-poll sessions export header-bearing audit sheets and CSVs.
[headers,rows] = s.auditData('windows');
assert(~isempty(headers) && isempty(rows));
[eh,er]=s.auditData('events');
assert(~isempty(er) && strcmp(er{1,strcmp(eh,'Event')},'session_start'));
empty=te.V3Session('simulation',C,5,20,100); empty.start('empty',0,'utc0');
empty.confirm([true true true],0,'utc0'); empty.request('baseline',0,'utc0'); empty.stop(1,'utc1');
[wh,wr]=empty.auditData('windows');
assert(strcmp(wr{1,strcmp(wh,'Quality')},'cancelled') && isempty(empty.Rows) && isempty(empty.Samples));
assert(wr{1,strcmp(wh,'PointCount')}==0);
fprintf('V3 correction behavioral assertions passed.\n');
end

function [session,deadline]=pendingWindow(C,id,kind)
session=te.V3Session('simulation',C,5,20,100); session.start(id,0,'utc0');
session.confirm([true true true],0,'utc0'); session.request('baseline',0,'utc0');
for t=5:2:23, session.poll(t,'inside',ones(18,1),zeros(3,1),'ok'); end
deadline=25;
if strcmp(kind,'heat')
    session.poll(25,'baseline-close',ones(18,1),zeros(3,1),'ok');
    session.confirm([true true true],26,'confirm'); session.request('heat',26,'request');
    for t=31:2:49, session.poll(t,'inside',ones(18,1),ones(3,1),'ok'); end
    deadline=51;
end
end

function assertThrows(action,identifier)
try
    action();
catch ME
    assert(strcmp(ME.identifier,identifier),sprintf('Expected %s, received %s',identifier,ME.identifier));
    return;
end
error('test:ExpectedError','Expected error %s was not thrown.',identifier);
end
