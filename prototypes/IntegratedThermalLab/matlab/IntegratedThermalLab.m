function engine = IntegratedThermalLab
%INTEGRATEDTHERMALLAB Standalone base MATLAB R2021b simulation GUI.
% Launch: addpath('matlab'); IntegratedThermalLab
% Manual: new -> 3 confirmations -> baseline -> run -> manually return ->
% 3 new confirmations -> heat window -> continue/finish -> export.
% Auto demo labels every confirmation as simulated. Closing stops/deletes timer.
% Nothing here commands CNC or accesses hardware; read +itl/SimTransport.m
% for the deliberately unimplemented hardware adapter boundary.
engine=itl.LabEngine(); cfg=engine.Config;
auto=false; demoStage=0; runStarted=0; savedCounts=[0 0 0]; uiMessage='请选择组合并新建实验。';
f=figure('Name','热误差与三区水冷集成采集 · 模拟原型', ...
    'NumberTitle','off','MenuBar','none','ToolBar','none','Color',[0.94 0.96 0.98], ...
    'Position',[40 40 1370 890],'CloseRequestFcn',@closeApp);
textBox([.02 .95 .96 .035],'仅模拟 · 无硬件写入 / 无CNC控制 / 无热位移闭环',[.7 .18 .05],13);
status=textBox([.02 .907 .64 .035],'', [0 .25 .4],12);
textBox([.69 .907 .1 .03],'固定组合', [0 0 0],10);
group=uicontrol(f,'Style','popupmenu','Units','normalized','Position',[.79 .91 .09 .03], ...
    'String',cfg.groups,'Callback',@groupChanged);
button([.89 .907 .09 .035],'新建实验',@newSession);
button([.02 .858 .12 .037],'一键自动演示',@autoDemo);
poseChecks=gobjects(1,3);
labels={'已停转','已到检测位','角向已复位'};
for k=1:3
    poseChecks(k)=uicontrol(f,'Style','checkbox','Units','normalized', ...
        'Position',[.16+.13*(k-1) .858 .13 .037],'String',labels{k},'Callback',@poseChanged);
end
button([.57 .858 .13 .037],'建立一次冷态基准',@(~,~)act(@()engine.requestWindow('BASELINE')));
button([.71 .858 .12 .037],'开始/继续运行',@(~,~)act(@()engine.startRun()));
button([.85 .858 .13 .037],'返回检测位',@(~,~)act(@()engine.returnToMeasure()));
button([.02 .806 .13 .037],'采有效热位移窗口',@(~,~)act(@()engine.requestWindow('HEAT')));
button([.16 .806 .10 .037],'结束实验',@finishSession);
button([.27 .806 .13 .037],'注入通信失败',@(~,~)injection('COMM_FAILURE'));
button([.41 .806 .12 .037],'注入探头超程',@(~,~)injection('OVERRANGE'));
button([.54 .806 .12 .037],'清除模拟注入',@(~,~)injection('CLEAR'));
button([.67 .806 .10 .037],'故障恢复',@(~,~)act(@()engine.recover()));
button([.79 .806 .19 .037],'导出CSV与元数据',@exportData);
message=textBox([.02 .761 .96 .034],uiMessage,[.3 .2 .08],10);
textBox([.02 .727 .31 .026],'18路温度（℃，模拟）',[0 .25 .4],11);
tempTable=uitable(f,'Units','normalized','Position',[.02 .285 .31 .44], ...
    'ColumnName',{'测点名称','模拟温度℃'},'ColumnWidth',{215 100},'RowName',[]);
textBox([.02 .243 .31 .03],'3探头 / 仅有效窗口计算XYZ（μm）',[0 .25 .4],11);
probeTable=uitable(f,'Units','normalized','Position',[.02 .105 .31 .137], ...
    'ColumnName',{'探头','原始μm','有效窗口XYZμm'},'ColumnWidth',{60 100 145},'RowName',[]);
tempAxes=axes(f,'Units','normalized','Position',[.39 .495 .32 .23]);
xlabel(tempAxes,'墙钟经过时间 / s'); ylabel(tempAxes,'模拟温度 / ℃'); grid(tempAxes,'on');
xyzAxes=axes(f,'Units','normalized','Position',[.39 .15 .32 .22]);
xlabel(xyzAxes,'有效热测量结束墙钟 / s'); ylabel(xyzAxes,'XYZ / μm'); grid(xyzAxes,'on');
textBox([.75 .727 .23 .025],'六阀命令 / 模拟反馈（%）',[0 .25 .4],11);
valveTable=uitable(f,'Units','normalized','Position',[.75 .514 .23 .21], ...
    'ColumnName',{'支路','命令%','模拟反馈%'},'ColumnWidth',{90 65 80},'RowName',[]);
textBox([.75 .475 .23 .029],'六支路流量 / 水温（全部模拟）',[0 .25 .4],11);
waterTable=uitable(f,'Units','normalized','Position',[.75 .267 .23 .207], ...
    'ColumnName',{'支路','L/min','入口℃','出口℃'},'ColumnWidth',{90 55 60 60},'RowName',[]);
logBox=uicontrol(f,'Style','listbox','Units','normalized','Position',[.75 .105 .23 .145], ...
    'String',{'事件日志'},'FontSize',9,'Max',2,'Min',0);
textBox([.02 .048 .96 .035], ...
    '演示参数：组合开度60% · 采样1s · 等待2s · 窗口5点 · 热时钟120× · 45°理想矩阵 · 探头±100μm。命令与反馈不代表真实动作/固定流量。', ...
    [.45 .25 .08],10);
poller=timer('ExecutionMode','fixedSpacing','Period',cfg.sampleIntervalS, ...
    'BusyMode','drop','TimerFcn',@poll,'ErrorFcn',@timerError);
refresh(); start(poller);
    function h=textBox(position,string,color,size)
        h=uicontrol(f,'Style','text','Units','normalized','Position',position, ...
            'String',string,'HorizontalAlignment','left','BackgroundColor',get(f,'Color'), ...
            'ForegroundColor',color,'FontSize',size);
    end
    function button(position,string,callback)
        uicontrol(f,'Style','pushbutton','Units','normalized','Position',position, ...
            'String',string,'Callback',callback,'FontSize',10);
    end
    function groupChanged(~,~)
        groups=get(group,'String'); act(@()engine.setGroup(groups{get(group,'Value')}));
    end
    function newSession(~,~)
        if engine.Active && ~ismember(engine.State,{'IDLE','FINISHED'})
            uiMessage='当前实验仍活跃，请先结束并导出已有数据。'; refresh(); return
        end
        if ~confirmClear('创建新实验'), return; end
        groups=get(group,'String');
        if engine.newExperiment(groups{get(group,'Value')})
            auto=false; savedCounts=[0 0 0]; uiMessage='新实验：请确认停转、检测位和角向，随后采冷态基准。';
        else, uiMessage='当前实验仍活跃，请先结束并导出已有数据。'; end
        refresh();
    end
    function poseChanged(~,~)
        values=arrayfun(@(h)logical(get(h,'Value')),poseChecks);
        act(@()engine.setPose(values(1),values(2),values(3)));
    end
    function act(action)
        if auto, uiMessage='自动演示进行中；请先结束再手动操作。'; refresh(); return; end
        try
            if action(), uiMessage='操作已接受，请查看状态和事件日志。';
            else, uiMessage='操作被流程条件拒绝，详情见事件日志。'; end
        catch err, uiMessage=['错误：' err.message]; end
        refresh();
    end
    function injection(kind)
        try, engine.inject(kind); uiMessage=['模拟注入：' kind];
        catch err, uiMessage=err.message; end
        refresh();
    end
    function finishSession(~,~)
        auto=false;
        if engine.finish(), uiMessage='实验已结束，可导出原始、事件、窗口和元数据。';
        elseif strcmp(engine.State,'FAULT'), uiMessage='结束时模拟阀写入失败：已进入故障，数据保留；请恢复后重试结束。';
        else, uiMessage='结束请求未被接受，请查看状态。'; end
        refresh();
    end
    function autoDemo(~,~)
        if engine.Active && ~strcmp(engine.State,'FINISHED')
            uiMessage='请先结束当前实验并导出，再启动自动演示。'; refresh(); return
        end
        if ~confirmClear('启动新的自动演示'), return; end
        groups=get(group,'String'); engine.newExperiment(groups{get(group,'Value')});
        savedCounts=[0 0 0]; auto=true; demoStage=0; uiMessage='自动演示：所有停转/到位/角向确认均为模拟确认。'; advanceDemo(); refresh();
    end
    function advanceDemo
        if ~auto, return; end
        if strcmp(engine.State,'FAULT')
            auto=false; uiMessage='自动演示遇到模拟通信故障，需手动恢复与重新确认。'; return
        end
        switch demoStage
            case 0
                engine.setPose(true,true,true,'simulation-demo'); engine.requestWindow('BASELINE'); demoStage=1;
            case 1
                if strcmp(engine.State,'READY') && ~isempty(engine.Baseline)
                    engine.startRun(); runStarted=tic; demoStage=2;
                elseif strcmp(engine.State,'IDLE')
                    auto=false; uiMessage='基准无效；清除注入、重新确认后再演示。';
                end
            case 2
                if toc(runStarted)>=8
                    engine.returnToMeasure(); engine.setPose(true,true,true,'simulation-demo');
                    engine.requestWindow('HEAT'); demoStage=3;
                end
            case 3
                if strcmp(engine.State,'READY')
                    last=engine.Windows(end);
                    if last.valid && strcmp(last.kind,'HEAT')
                        if engine.finish()
                            uiMessage='自动演示完成：一次基准、一次有效热位移窗口，所有操作条件均为模拟确认。';
                        else
                            uiMessage='窗口已保留，但结束写入失败；请恢复后重试结束。';
                        end
                    else, uiMessage=['自动演示窗口无效：' last.reason]; end
                    auto=false;
                end
        end
    end
    function poll(~,~)
        if ~ishghandle(f), return; end
        try, engine.tick(); advanceDemo(); refresh();
        catch err, auto=false; uiMessage=['程序异常（非通信模拟）：' err.message]; refresh(); end
    end
    function timerError(~,event)
        auto=false; uiMessage=['计时器停止，请重新打开：' event.Data.message];
        if ishghandle(f), refresh(); end
    end
    function refresh
        if ~ishghandle(f), return; end
        names=struct('IDLE','待建基准','SETTLING','稳定等待','MEASURING','窗口采集', ...
            'READY','待运行/测量','RUNNING','运行中（探头可能超程）','RETURNING','等待人工返回确认', ...
            'FAULT','通信故障','FINISHED','已结束');
        modeText='手动'; if auto, modeText='自动 · 模拟确认'; end
        set(status,'String',sprintf('%s | %s | %s | 热时间 %.0fs | 记录 %d / 窗口 %d', ...
            engine.State,names.(engine.State),modeText,engine.SimulationTimeS,numel(engine.Raw),numel(engine.Windows)));
        set(message,'String',uiMessage);
        if engine.Active, set(group,'Enable','off'); else, set(group,'Enable','on'); end
        index=find(strcmp(cfg.groups,engine.Group),1); set(group,'Value',index);
        for j=1:3, set(poseChecks(j),'Value',double(engine.Pose(j))); end
        temps=NaN(1,18); probes=NaN(1,3); flow=NaN(1,6); win=NaN(1,6); wout=NaN(1,6);
        if ~isempty(engine.Latest)
            temps=engine.Latest.temperature; probes=engine.Latest.probes;
            flow=engine.Latest.flow; win=engine.Latest.waterIn; wout=engine.Latest.waterOut;
        end
        set(tempTable,'Data',[cfg.temperatureNames(:),num2cell(temps(:))]);
        formal=NaN(1,3); heat=engine.Windows;
        if ~isempty(heat)
            heat=heat([heat.valid] & strcmp({heat.kind},'HEAT'));
            if ~isempty(heat), formal=[heat(end).xyz_x_um heat(end).xyz_y_um heat(end).xyz_z_um]; end
        end
        set(probeTable,'Data',[{'通道1 / X';'通道2 / Y';'通道3 / Z'},num2cell(probes(:)),num2cell(formal(:))]);
        set(valveTable,'Data',[cfg.branchNames(:),num2cell(engine.Transport.ValveCommand(:)),num2cell(engine.Transport.ValveFeedback(:))]);
        set(waterTable,'Data',[cfg.branchNames(:),num2cell(flow(:)),num2cell(win(:)),num2cell(wout(:))]);
        if ~isempty(engine.Raw)
            rows=engine.Raw; times=[rows.elapsed_wall_s]; curves=NaN(numel(rows),18);
            for j=1:18, curves(:,j)=[rows.(sprintf('temperature_%02d_c',j))]'; end
            plot(tempAxes,times,curves,'LineWidth',1); grid(tempAxes,'on');
            xlabel(tempAxes,'墙钟经过时间 / s'); ylabel(tempAxes,'18路模拟温度 / ℃');
        else, cla(tempAxes); end
        if ~isempty(heat)
            plot(xyzAxes,[heat.end_elapsed_wall_s],[heat.xyz_x_um],'o-', ...
                [heat.end_elapsed_wall_s],[heat.xyz_y_um],'s-', ...
                [heat.end_elapsed_wall_s],[heat.xyz_z_um],'^-','LineWidth',1.5);
            legend(xyzAxes,{'X','Y','Z'},'Location','best'); grid(xyzAxes,'on');
            xlabel(xyzAxes,'有效热测量结束墙钟 / s'); ylabel(xyzAxes,'XYZ / μm');
        else, cla(xyzAxes); end
        events=engine.Events; begin=max(1,numel(events)-39); lines=cell(1,numel(events)-begin+1);
        for j=begin:numel(events)
            lines{j-begin+1}=sprintf('%.1fs %s %s',events(j).elapsed_wall_s,events(j).event,events(j).detail);
        end
        set(logBox,'String',lines,'Value',max(1,numel(lines))); drawnow limitrate;
    end
    function exportData(~,~)
        exportSnapshot(); refresh();
    end
    function accepted=exportSnapshot
        accepted=false;
        folder=uigetdir(pwd,'选择导出文件夹（将建立实验编号子目录）');
        if isequal(folder,0), return; end
        try
            target=fullfile(folder,engine.ExperimentId); itl.exportSession(engine,target);
            savedCounts=recordCounts(); accepted=true; uiMessage=['已导出：' target];
        catch err, uiMessage=['导出失败：' err.message]; end
    end
    function counts=recordCounts
        counts=[numel(engine.Raw),numel(engine.Windows),numel(engine.Events)];
    end
    function accepted=confirmClear(action)
        accepted=true;
        if isempty(engine.Raw) && isempty(engine.Windows), return; end
        choice=questdlg([action '将清除内存中的现有采集记录。请选择先导出或明确清除。'], ...
            '保护已有实验数据','导出后继续','清除并继续','取消','取消');
        if strcmp(choice,'导出后继续'), accepted=exportSnapshot();
        else, accepted=strcmp(choice,'清除并继续'); end
        if ~accepted, uiMessage='已取消清除，采集记录保留。'; refresh(); end
    end
    function closeApp(~,~)
        % Freeze acquisition while deciding. Finalize BEFORE any final export,
        % so CANCELLED windows and terminal events cannot be silently lost.
        wasRunning=isvalid(poller) && strcmp(get(poller,'Running'),'on');
        if isvalid(poller), stop(poller); end
        guard=onCleanup(@()resumePolling(wasRunning)); %#ok<NASGU>
        hasRecords=~isempty(engine.Raw) || ~isempty(engine.Windows);
        needPrompt=(hasRecords || engine.Active) && (~isequal(savedCounts,recordCounts()) || ~strcmp(engine.State,'FINISHED'));
        choice='清除并继续'; target='';
        if needPrompt
            choice=questdlg('关闭会结束本轮实验并记录未完成窗口。请选择导出最终记录或明确清除。', ...
                '保护已有实验数据','导出后继续','清除并继续','取消','取消');
            if strcmp(choice,'导出后继续')
                folder=uigetdir(pwd,'选择最终记录导出文件夹');
                if isequal(folder,0), uiMessage='关闭已取消，记录保留。'; refresh(); return; end
                target=fullfile(folder,engine.ExperimentId);
            elseif ~strcmp(choice,'清除并继续')
                uiMessage='关闭已取消，采集记录保留。'; refresh(); return
            end
        end
        auto=false;
        if ~strcmp(engine.State,'FINISHED') && ~engine.finish()
            uiMessage='关闭时模拟阀写入失败，界面和数据保留；请恢复后重试。'; refresh(); return
        end
        if strcmp(choice,'导出后继续')
            try
                itl.exportSession(engine,target); savedCounts=recordCounts();
            catch err
                uiMessage=['最终记录导出失败，界面和数据保留：' err.message]; refresh(); return
            end
        end
        if isvalid(poller), delete(poller); end
        delete(f);
    end
    function resumePolling(wasRunning)
        if wasRunning && ishghandle(f) && isvalid(poller) && strcmp(get(poller,'Running'),'off')
            start(poller);
        end
    end
end
