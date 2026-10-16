function ThermalError_18T_3Probe_V3(acquisitionMode)
% ========================================================================
% 龙门机床 18路温度 + 三电涡流 XYZ热误差采集系统 V3
%
% MATLAB R2021b
%
% ========================================================================
% 主要功能
%
% 1. 18路温度连续采集
% 2. 三路电涡流位移连续采集
% 3. 计划2 s采样周期（FixedSpacing / BusyMode=drop）
% 4. 时间记录为实际单调经过秒数和UTC，不假定严格2 s或无丢失
%
% 5. 冷态零点测量
% 6. 固定检测位热误差测量
% 7. 5 s稳定等待
% 8. 稳定期后20 s实际测量窗口；点数取决于实际轮询，不补采失败窗口
% 9. 三探头XYZ标定矩阵转换
% 10. ±100 μm有效范围检查
% 11. ±90~±100 μm边界预警
% 12. 连续数据、建模样本分别保存
% 13. 保留中文工作表和旧数值列；新增审计列使用明确字段名
% 14. 默认显式模拟；真实设备配置未经核验，真实模式在打开串口前拒绝
% 15. 每窗需重新确认：主轴停止、同向返回固定点、独立角度复位
% 16. 连续行、窗口、事件、样本均保留模式/实际时间/质量/实验和基准ID
% 兼容列“时间/s”“实验时间/s”现表示实际时间；新增ElapsedSec/UTC列。
%
% ========================================================================
% 实验流程
%
% 冷机：
%
%     开始连续采集
%          ↓
%     机床位于固定检测位
%          ↓
%     设置冷态零点
%          ↓
%     自动稳定5 s
%          ↓
%     在20 s实际窗口内至少取得10个有效点（不足则无效）
%          ↓
%     建立本轮实验冷态基准
%
%
% 正式实验：
%
%     机床运行
%          ↓
%     返回固定检测位
%          ↓
%     点击“记录热误差样本”
%          ↓
%     自动等待5 s
%          ↓
%     在20 s实际窗口内至少取得10个有效点（不足则无效）
%          ↓
%     18温度平均
%          ↓
%     三探头平均
%          ↓
%     减去冷态零点
%          ↓
%     XYZ标定矩阵
%          ↓
%     得到一个有效训练样本
%
% ========================================================================

clc;
if nargin<1, acquisitionMode='simulation'; end
% Protocol guard must precede serial construction and serial cleanup alike.
if ~strcmp(acquisitionMode,'simulation')
    error('te:UnverifiedConfiguration', ...
        '真实采集已阻止：全局从站地址、寄存器约定与缩放未经现场核验。请显式选择 simulation。');
end

%% ========================================================================
% 1. 用户设置
% ========================================================================

% ---------------- COM ----------------

comPort = 'COM5';

baudRate = 19200;


% ---------------- 固定采样周期 ----------------

sampleIntervalSec = 2;


% ---------------- 返回检测位后的稳定时间 ----------------

settleTimeSec = 5;


% ---------------- 正式测量窗口 ----------------

measurementWindowSec = 20;


% 有效窗口至少10个点；实际20 s截止，不足点数记为无效
measurementSamples = ...
    measurementWindowSec / sampleIntervalSec;


% 模式只能在构造时显式选择：ThermalError_18T_3Probe_V3('simulation')。
% 本修订版尚未完成现场通信核验，任何 real 选择均在接触串口前报错。

% ---------------- GUI显示最大点数 ----------------

maxDisplayPoints = 10000;


%% ========================================================================
% 2. 电涡流有效范围
% ========================================================================
%
% 根据你的要求：
%
%       -100 μm ~ +100 μm
%
% 注意：
% 这个范围已经基本等于传感器完整线性范围。
%
% 90~100 μm区域：
% 允许使用，但GUI提醒“接近边界”。
%
% >100 μm：
% 正式样本无效。
%
% ========================================================================

probeSafeLimit_um = 100;

probeWarningLimit_um = 90;


% 冷态安装建议尽量靠近0点

probeRecommendedZeroLimit_um = 20;


%% ========================================================================
% 3. 18路温度传感器
% ========================================================================

tempServers = struct( ...
    'id', {1, 2, 3}, ...
    'numChannels', {8, 8, 2}, ...
    'names', { ...
    {'床身右侧', ...
     '立柱左侧', ...
     '立柱右侧', ...
     '横梁上端', ...
     '环境温度', ...
     'Z轴前端轴承', ...
     'Z轴后端轴承', ...
     'X轴前端轴承'}, ...
    {'Y2轴前端轴承', ...
     'Y1轴前端轴承', ...
     'Y1轴后端轴承', ...
     'Z轴螺母', ...
     'Y2轴螺母', ...
     'Y1轴螺母', ...
     'Y2轴后端轴承', ...
     'X轴螺母'}, ...
    {'X轴后端轴承', ...
     '主轴前端轴承'} ...
    });


tempChannels = ...
    sum([tempServers.numChannels]);


tempNames = {};


for k = 1:length(tempServers)

    tempNames = ...
        [tempNames, tempServers(k).names];

end


% 温度寄存器

tempRegister = 1537;


% 原始温度值 /10

tempScale = 0.1;


%% ========================================================================
% 4. 三个电涡流仪表
% ========================================================================
%
% 以下为历史候选配置，尚未完成现场核验，真实模式已禁止：
%
% Probe1：地址5
% Probe2：地址6
% Probe3：地址7
%
% 保持寄存器：
%
% 75
%
% 缩放：
%
% raw × 0.1 = μm
%
% 正式实验前需要现场再确认一次：
%
% AI仪表显示 12.3 μm
% MATLAB也应该显示 12.3 μm
%
% ========================================================================

probeSensors = struct( ...
    'id',    {5, 6, 7}, ...
    'reg',   {75, 75, 75}, ...
    'scale', {0.1, 0.1, 0.1}, ...
    'name',  {'探头1','探头2','探头3'} ...
    );


numProbes = 3;


%% ========================================================================
% 5. 模式初始化
% ========================================================================

m = []; % historical read adapter below is unreachable until separately commissioned
simulateMode = true; % fixed by the explicit construction guard, never changed on errors

%% ========================================================================
% 6. 三探头XYZ系统标定矩阵
% ========================================================================
%
% 正式标定以后，需要：
%
% ThreeProbeCalibration.mat
%
% 文件中包含：
%
% C_xyz_from_probe
%
% 满足：
%
%       [X;Y;Z]
%
%            =
%
%       C_xyz_from_probe
%
%            ×
%
%       [ΔP1;ΔP2;ΔP3]
%
% ========================================================================

calibrationFile = ...
    'ThreeProbeCalibration.mat';


calibrationEnabled = false;


C_xyz_from_probe = nan(3); % unavailable calibration stays unavailable; never enable demo on error


if exist(calibrationFile,'file')

    try

        calData = ...
            load(calibrationFile);


        if isfield( ...
                calData, ...
                'C_xyz_from_probe') && ...
                isequal( ...
                size(calData.C_xyz_from_probe), ...
                [3 3]) && ...
                all(isfinite(calData.C_xyz_from_probe(:)))


            C_xyz_from_probe = ...
                calData.C_xyz_from_probe;


            calibrationEnabled = true;


            fprintf('\n✅ 已加载真实XYZ标定矩阵：\n');

            disp(C_xyz_from_probe);

        end


    catch ME

        fprintf('⚠️ 标定文件读取失败：%s\n', ...
            ME.message);

    end

end


% 无标定时保留NaN XYZ；加载失败不会启用演示矩阵。
session = te.V3Session(acquisitionMode,C_xyz_from_probe, ...
    settleTimeSec,measurementWindowSec,probeSafeLimit_um,measurementSamples);
sessionClock = [];
sessionSequence = 0;
sessionSaved = true;

%% ========================================================================
% 7. 自动清理
% ========================================================================

cleanupObj = ...
    onCleanup(@cleanupResources); %#ok<NASGU>


%% ========================================================================
% 8. GUI窗口
% ========================================================================

fig = figure( ...
    'Name', ...
    '龙门机床三向热误差实验采集系统 V3', ...
    'NumberTitle', ...
    'off', ...
    'Position', ...
    [30 20 1580 990], ...
    'CloseRequestFcn', ...
    @closeFigure);


%% ========================================================================
% 9. 模式状态
% ========================================================================

modeText = uicontrol( ...
    'Parent', fig, ...
    'Style', 'text', ...
    'Position', [1150 935 380 35], ...
    'FontSize', 13, ...
    'FontWeight', 'bold');


%% ========================================================================
% 10. 温度图
% ========================================================================

axTemp = axes( ...
    'Parent', fig, ...
    'Units', 'normalized', ...
    'Position', ...
    [0.045 0.59 0.62 0.33]);


hold(axTemp,'on');


tempColors = ...
    lines(tempChannels);


hTemp = ...
    gobjects(tempChannels,1);


for i = 1:tempChannels

    hTemp(i) = plot( ...
        axTemp, ...
        NaN, ...
        NaN, ...
        'Color', ...
        tempColors(i,:), ...
        'LineWidth', ...
        1.1);

end


grid(axTemp,'on');


title( ...
    axTemp, ...
    '18路温度连续监测');


ylabel( ...
    axTemp, ...
    '温度 / ℃');


legend( ...
    axTemp, ...
    tempNames, ...
    'Location', ...
    'eastoutside', ...
    'FontSize', ...
    6);


%% ========================================================================
% 11. 三探头实时图
% ========================================================================

axProbe = axes( ...
    'Parent', fig, ...
    'Units', 'normalized', ...
    'Position', ...
    [0.045 0.34 0.62 0.18]);


hold(axProbe,'on');


hProbe(1) = plot( ...
    axProbe, NaN, NaN, ...
    'LineWidth', 1.5);


hProbe(2) = plot( ...
    axProbe, NaN, NaN, ...
    'LineWidth', 1.5);


hProbe(3) = plot( ...
    axProbe, NaN, NaN, ...
    'LineWidth', 1.5);


% ±100 μm边界

yline( ...
    axProbe, ...
    +probeSafeLimit_um, ...
    '--', ...
    '+100 μm线性边界');


yline( ...
    axProbe, ...
    -probeSafeLimit_um, ...
    '--', ...
    '-100 μm线性边界');


% ±90 μm预警

yline( ...
    axProbe, ...
    +probeWarningLimit_um, ...
    ':', ...
    '+90 μm预警');


yline( ...
    axProbe, ...
    -probeWarningLimit_um, ...
    ':', ...
    '-90 μm预警');


ylim(axProbe,[-115 115]);


grid(axProbe,'on');


title( ...
    axProbe, ...
    '三路电涡流位移实时数据');


ylabel( ...
    axProbe, ...
    '相对位移 / μm');


legend( ...
    axProbe, ...
    {'探头1','探头2','探头3'}, ...
    'Location', ...
    'eastoutside');


%% ========================================================================
% 12. XYZ热误差图
% ========================================================================

axXYZ = axes( ...
    'Parent', fig, ...
    'Units', 'normalized', ...
    'Position', ...
    [0.045 0.08 0.62 0.18]);


hold(axXYZ,'on');


hXYZ(1) = plot( ...
    axXYZ, ...
    NaN, ...
    NaN, ...
    'o-', ...
    'LineWidth',1.6, ...
    'MarkerSize',6);


hXYZ(2) = plot( ...
    axXYZ, ...
    NaN, ...
    NaN, ...
    's-', ...
    'LineWidth',1.6, ...
    'MarkerSize',6);


hXYZ(3) = plot( ...
    axXYZ, ...
    NaN, ...
    NaN, ...
    '^-', ...
    'LineWidth',1.6, ...
    'MarkerSize',6);


grid(axXYZ,'on');


title( ...
    axXYZ, ...
    '固定检测位XYZ热误差样本');


xlabel( ...
    axXYZ, ...
    '实验时间 / min');


ylabel( ...
    axXYZ, ...
    '热误差 / μm');


legend( ...
    axXYZ, ...
    {'X方向','Y方向','Z方向'}, ...
    'Location', ...
    'eastoutside');


%% ========================================================================
% 13. 固定参数显示
% ========================================================================

uicontrol( ...
    'Parent', fig, ...
    'Style', 'text', ...
    'String', ...
    sprintf( ...
    '计划采样间隔：%d s', ...
    sampleIntervalSec), ...
    'Position', ...
    [1150 785 190 28], ...
    'HorizontalAlignment', ...
    'left', ...
    'FontSize',11, ...
    'FontWeight','bold');


uicontrol( ...
    'Parent', fig, ...
    'Style', 'text', ...
    'String', ...
    sprintf( ...
    '稳定等待：%d s', ...
    settleTimeSec), ...
    'Position', ...
    [1360 785 150 28], ...
    'HorizontalAlignment', ...
    'left', ...
    'FontSize',11);


uicontrol( ...
    'Parent', fig, ...
    'Style', 'text', ...
    'String', ...
    sprintf( ...
    '测量窗口：%d s / 约%d点', ...
    measurementWindowSec, ...
    measurementSamples), ...
    'Position', ...
    [1150 755 200 28], ...
    'HorizontalAlignment', ...
    'left', ...
    'FontSize',11);


uicontrol( ...
    'Parent', fig, ...
    'Style', 'text', ...
    'String', ...
    sprintf( ...
    '电涡流范围：±%d μm', ...
    probeSafeLimit_um), ...
    'Position', ...
    [1360 755 160 28], ...
    'HorizontalAlignment', ...
    'left', ...
    'FontSize',11);


% 操作者确认是测量条件，不代表软件控制或核验CNC；每个新窗口重新勾选。
confirmStopped = uicontrol('Parent',fig,'Style','checkbox', ...
    'String','确认主轴已停止','Position',[1150 900 370 25], ...
    'Callback',@confirmationCallback,'Enable','off');
confirmReturn = uicontrol('Parent',fig,'Style','checkbox', ...
    'String','确认已按同一方向返回固定检测点','Position',[1150 873 370 25], ...
    'Callback',@confirmationCallback,'Enable','off');
confirmAngle = uicontrol('Parent',fig,'Style','checkbox', ...
    'String','确认已独立完成角度复位','Position',[1150 846 370 25], ...
    'Callback',@confirmationCallback,'Enable','off');
btnRecover = uicontrol('Parent',fig,'Style','pushbutton', ...
    'String','显式恢复故障（保留本轮基准）','Position',[1150 812 370 29], ...
    'Callback',@recoverCallback,'Enable','off');

%% ========================================================================
% 14. 操作按钮
% ========================================================================

btnStart = uicontrol( ...
    'Parent', fig, ...
    'Style', 'pushbutton', ...
    'String', '开始连续采集', ...
    'Position', [1150 700 160 40], ...
    'Callback', @startCallback, ...
    'FontSize',12);


btnZero = uicontrol( ...
    'Parent', fig, ...
    'Style', 'pushbutton', ...
    'String', '设置冷态零点', ...
    'Position', [1330 700 160 40], ...
    'Callback', @zeroCallback, ...
    'FontSize',12, ...
    'Enable','off');


btnSample = uicontrol( ...
    'Parent', fig, ...
    'Style', 'pushbutton', ...
    'String', '记录热误差样本', ...
    'Position', [1150 650 160 40], ...
    'Callback', @sampleCallback, ...
    'FontSize',12, ...
    'Enable','off');


btnStop = uicontrol( ...
    'Parent', fig, ...
    'Style', 'pushbutton', ...
    'String', '停止并保存', ...
    'Position', [1330 650 160 40], ...
    'Callback', @stopCallback, ...
    'FontSize',12, ...
    'Enable','off');


%% ========================================================================
% 15. 状态文字
% ========================================================================

statusText = uicontrol( ...
    'Parent', fig, ...
    'Style','text', ...
    'String','状态：等待开始实验', ...
    'Position',[1150 610 370 30], ...
    'HorizontalAlignment','left', ...
    'FontSize',11);


sampleCountText = uicontrol( ...
    'Parent',fig, ...
    'Style','text', ...
    'String','有效热误差样本：0', ...
    'Position',[1150 580 370 28], ...
    'HorizontalAlignment','left', ...
    'FontSize',11);


zeroStatusText = uicontrol( ...
    'Parent',fig, ...
    'Style','text', ...
    'String','冷态零点：未设置', ...
    'Position',[1150 550 370 28], ...
    'HorizontalAlignment','left', ...
    'FontSize',11);


%% ========================================================================
% 16. 三探头状态
% ========================================================================

probeStatusText = ...
    gobjects(3,1);


for ii = 1:3

    probeStatusText(ii) = ...
        uicontrol( ...
        'Parent',fig, ...
        'Style','text', ...
        'String', ...
        sprintf( ...
        '探头%d：等待数据',ii), ...
        'Position', ...
        [1150, ...
         510-(ii-1)*30, ...
         370, ...
         26], ...
        'HorizontalAlignment','left', ...
        'FontSize',10);

end


detectPositionText = uicontrol( ...
    'Parent',fig, ...
    'Style','text', ...
    'String','检测状态：未知', ...
    'Position',[1150 410 370 32], ...
    'HorizontalAlignment','left', ...
    'FontWeight','bold', ...
    'FontSize',11);


%% ========================================================================
% 17. 当前值表格
% ========================================================================

tableNames = [ ...
    tempNames, ...
    {'探头1','探头2','探头3'}, ...
    {'最近有效窗口X热误差', ...
     '最近有效窗口Y热误差', ...
     '最近有效窗口Z热误差'} ...
    ];


numTableRows = ...
    length(tableNames);


initialData = ...
    cell(numTableRows,2);


for ii = 1:numTableRows

    initialData{ii,1} = ...
        tableNames{ii};

    initialData{ii,2} = ...
        '--';

end


tbl = uitable( ...
    fig, ...
    'Position',[1150 45 370 350], ...
    'ColumnName', ...
    {'测点/变量','当前值'}, ...
    'ColumnWidth', ...
    {200 120}, ...
    'Data', ...
    initialData, ...
    'RowName', ...
    'numbered', ...
    'FontSize', ...
    9);


%% ========================================================================
% 18. 采集状态变量
% ========================================================================

collecting = false;

isSaving = false;

pendingClose = false;


acqTimer = [];


sampleIndex = 0;


% ---------------- 当前数据 ----------------

lastTemp = [];

lastProbe = [];


% ---------------- 连续数据 ----------------

full_time = [];

full_temp = [];

full_probe = [];


% ---------------- 冷态零点 ----------------

zeroReady = false;

zeroProbe = [NaN;NaN;NaN];

zeroTemp = nan(tempChannels,1);


% ---------------- 热误差样本 ----------------

sampleNumber = 0;

sampleTime = [];

sampleTemp = [];

sampleProbeMean = [];

sampleDeltaProbe = [];

sampleXYZ = [];

sampleStdXYZ = [];

sampleWindowStart = [];

sampleWindowEnd = [];


%% ========================================================================
% 19. 测量窗口状态
% ========================================================================
%
% windowMode
%
% 0 = 没有测量任务
% 1 = 设置冷态零点
% 2 = 正式热误差样本
%
% windowPhase
%
% 0 = 无
% 1 = 等待5秒稳定
% 2 = 实际20 s窗口内测量；至少10点才可有效
%
% ========================================================================

windowMode = 0;

windowPhase = 0;



%% ========================================================================
% 20. 离线模拟状态
% ========================================================================


simTempBase = ...
    24 + ...
    0.6*sin((1:tempChannels)'*0.55);


simTempAmplitude = ...
    3.0 + ...
    2.0*cos((1:tempChannels)'*0.31).^2;


simPhase = ...
    (1:tempChannels)'*0.37;


%% ========================================================================
% 21. 更新当前模式
% ========================================================================

updateModeText();


%% ========================================================================
% 22. 开始采集
% ========================================================================

    function startCallback(~,~)
        if collecting, return; end
        if ~sessionSaved
            sessionSaved=saveData();
            if ~sessionSaved, return; end
        end
        % Stop/start creates a new identity and a fresh immutable-baseline scope.
        sessionClock=tic; sessionSequence=sessionSequence+1;
        id=sprintf('V3_%s_%04d',datestr(now,'yyyymmddTHHMMSSFFF'),sessionSequence);
        session.start(id,0,utcNow()); sessionSaved=false;
        sampleIndex=0; full_time=[]; full_temp=zeros(tempChannels,0); full_probe=zeros(3,0);
        lastTemp=[]; lastProbe=[]; zeroReady=false;
        zeroProbe=nan(3,1); zeroTemp=nan(tempChannels,1);
        sampleNumber=0; sampleTime=[]; sampleTemp=zeros(tempChannels,0);
        sampleProbeMean=zeros(3,0); sampleDeltaProbe=zeros(3,0);
        sampleXYZ=zeros(3,0); sampleStdXYZ=zeros(3,0);
        sampleWindowStart=[]; sampleWindowEnd=[];
        windowMode=0; windowPhase=0; collecting=true;
        clearConfirmations();
        set([confirmStopped confirmReturn confirmAngle],'Enable','on');
        set(btnStart,'Enable','off'); set(btnStop,'Enable','on');
        set(btnRecover,'Enable','off');
        set([hTemp(:);hProbe(:);hXYZ(:)],'XData',NaN,'YData',NaN);
        set(zeroStatusText,'String','冷态零点：未设置');
        set(sampleCountText,'String','有效热误差样本：0');
        set(statusText,'String','状态：实际时间采集，运行段仅记录原始量');
        % Each poll is retained, including an initial failure. Never retry until
        % success while manufacturing t=0 or silently changing source mode.
        acquisitionTick([],[]);
        if ~collecting || strcmp(session.State,'fault'), return; end
        createAcquisitionTimer();
        refreshActionButtons();
    end


%% ========================================================================
% 23. 2秒定时采样
% ========================================================================

    function acquisitionTick(~,~)
        if ~collecting || ~strcmp(session.State,'running'), return; end
        % Timestamp at read start/end records transport latency and true gaps.
        readStartSec=toc(sessionClock); readStartUTC=utcNow();
        readError='';
        try
            [tempVals,probeVals]=readAllSensors();
            quality='ok';
        catch ME
            tempVals=nan(tempChannels,1); probeVals=nan(3,1);
            quality='communication_error'; readError=ME.message;
        end
        tNow=toc(sessionClock); stamp=utcNow();
        session.poll(tNow,stamp,tempVals,probeVals,quality,readStartSec,readStartUTC,readError);
        % Raw rows are projections of the core, including failed polls.
        r=session.Rows(end); sampleIndex=sampleIndex+1;
        full_time(end+1)=r.ElapsedSec;
        full_temp(:,end+1)=r.Temperature; full_probe(:,end+1)=r.Probe;
        lastTemp=r.Temperature; lastProbe=r.Probe;
        syncSessionProjection();
        if strcmp(session.State,'fault')
            enterFaultUI(readError);
        end
        updateCurrentDisplay(); updatePlots();
        drawnow limitrate;
    end


%% ========================================================================
% 24. 设置冷态零点
% ========================================================================

    function zeroCallback(~,~)
        % Core AND callback guard re-zero, even if invoked programmatically.
        if ~collecting || zeroReady || windowMode~=0 || ~strcmp(session.State,'running'), return; end
        startMeasurementWindow(1);
    end


%% ========================================================================
% 25. 记录热误差样本
% ========================================================================

    function sampleCallback(~,~)
        if ~collecting || ~zeroReady || windowMode~=0 || ~strcmp(session.State,'running'), return; end
        startMeasurementWindow(2);
    end


%% ========================================================================
% 26. 启动测量任务
% ========================================================================

    function startMeasurementWindow(modeValue)
        % GUI checks aid the operator; the session checks the same conditions.
        try
            confirmations=[get(confirmStopped,'Value'),get(confirmReturn,'Value'),get(confirmAngle,'Value')];
            session.confirm(confirmations,toc(sessionClock),utcNow());
            kind='baseline'; if modeValue==2, kind='heat'; end
            session.request(kind,toc(sessionClock),utcNow());
            windowMode=modeValue; windowPhase=1;
            set(statusText,'String',sprintf('状态：稳定%d s，随后实际测量%d s；条件丢失即无效',settleTimeSec,measurementWindowSec));
        catch ME
            set(statusText,'String',['状态：拒绝测量：' ME.message]);
        end
        refreshActionButtons();
    end


%% ========================================================================
% 27. 处理稳定和测量窗口
% ========================================================================

    function syncSessionProjection()
        zeroReady=session.BaselineReady; zeroProbe=session.BaselineProbe;
        zeroTemp=session.BaselineTemperature;
        if isempty(session.Active)
            if windowMode~=0, clearConfirmations(); end
            windowMode=0; windowPhase=0;
        else
            windowMode=1; if strcmp(session.Active.Kind,'heat'), windowMode=2; end
            windowPhase=1; if strcmp(session.Active.Phase,'measuring'), windowPhase=2; end
            set(statusText,'String',sprintf('状态：%s，已收%d点；实际时间截止，不补采', ...
                session.Active.Phase,numel(session.Active.Times)));
        end
        if zeroReady
            set(zeroStatusText,'String',sprintf('冷态零点（本轮锁定）：%.2f / %.2f / %.2f μm',zeroProbe));
        end
        if numel(session.Samples)>sampleNumber
            a=session.Samples(end); sampleNumber=sampleNumber+1;
            sampleTime(end+1)=a.ElapsedSec; sampleTemp(:,end+1)=a.Temperature;
            sampleProbeMean(:,end+1)=a.Probe; sampleDeltaProbe(:,end+1)=a.DeltaProbe;
            sampleXYZ(:,end+1)=a.XYZ; sampleStdXYZ(:,end+1)=a.StdXYZ;
            sampleWindowStart(end+1)=a.StartElapsedSec; sampleWindowEnd(end+1)=a.EndElapsedSec;
            set(sampleCountText,'String',sprintf('有效热误差样本：%d',sampleNumber));
        end
        if isempty(session.Active) && ~isempty(session.Windows)
            a=session.Windows(end);
            set(statusText,'String',sprintf('状态：上一窗口 %s %s；新窗口需重新确认',a.Quality,a.Reason));
        end
    end

    function confirmationCallback(~,~)
        if ~collecting, return; end
        confirmations=[get(confirmStopped,'Value'),get(confirmReturn,'Value'),get(confirmAngle,'Value')];
        hadWindow=~isempty(session.Active);
        session.confirm(confirmations,toc(sessionClock),utcNow());
        if hadWindow && isempty(session.Active), syncSessionProjection(); end
        refreshActionButtons();
    end

    function clearConfirmations()
        set([confirmStopped confirmReturn confirmAngle],'Value',0);
    end

    function createAcquisitionTimer()
        acqTimer=timer('ExecutionMode','fixedSpacing','Period',sampleIntervalSec, ...
            'StartDelay',sampleIntervalSec,'BusyMode','drop', ...
            'TimerFcn',@acquisitionTick,'ErrorFcn',@timerErrorCallback);
        start(acqTimer);
    end

    function enterFaultUI(reason)
        % V3 reads only. Do not invent machine/valve commands on fault.
        stopAndDeleteTimer(); clearConfirmations();
        set([confirmStopped confirmReturn confirmAngle],'Enable','off');
        set(btnRecover,'Enable','on');
        set(statusText,'String',['状态：故障，需显式恢复；' reason]);
        refreshActionButtons();
    end

    function recoverCallback(~,~)
        if ~collecting || ~strcmp(session.State,'fault'), return; end
        session.recover(toc(sessionClock),utcNow());
        clearConfirmations(); set([confirmStopped confirmReturn confirmAngle],'Enable','on');
        set(btnRecover,'Enable','off');
        set(statusText,'String','状态：已显式恢复；本轮基准保留，测量需重新确认');
        createAcquisitionTimer(); refreshActionButtons();
    end

    function stamp=utcNow()
        stamp=char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
    end

%% ========================================================================
% 30. 读取全部传感器
% ========================================================================

    function [tempVals,probeVals] = ...
            readAllSensors()


        %% ---------------------------------------------------------------
        % 离线模拟
        % ---------------------------------------------------------------

        if simulateMode

            [tempVals,probeVals] = ...
                generateSimulationData();

            return;

        end


        %% ---------------------------------------------------------------
        % 温度
        % ---------------------------------------------------------------

        tempVals = ...
            zeros(tempChannels,1);


        pos = 1;


        for kk = 1:length(tempServers)

            slave = ...
                tempServers(kk).id;


            n = ...
                tempServers(kk).numChannels;


            rawTemp = read( ...
                m, ...
                'holdingregs', ...
                tempRegister, ...
                n, ...
                slave);


            temp = ...
                double(rawTemp) * ...
                tempScale;


            tempVals(pos:pos+n-1) = ...
                temp(:);


            pos = ...
                pos + n;

        end


        %% ---------------------------------------------------------------
        % 三个电涡流
        % ---------------------------------------------------------------

        probeVals = ...
            zeros(numProbes,1);


        for jj = 1:numProbes

            rawProbe = read( ...
                m, ...
                'holdingregs', ...
                probeSensors(jj).reg, ...
                1, ...
                probeSensors(jj).id);


            rawSigned = ...
                signed16ToDouble( ...
                rawProbe);


            probeVals(jj) = ...
                rawSigned * ...
                probeSensors(jj).scale;

        end

    end


%% ========================================================================
% 31. 16位有符号值转换
% ========================================================================

    function value = ...
            signed16ToDouble(raw)


        value = double(raw);


        if value > 32767

            value = ...
                value - 65536;

        end

    end


%% ========================================================================
% 32. 离线模拟数据
% ========================================================================

    function [tempVals,probeVals] = ...
            generateSimulationData()


        % 模拟同样使用实际经过时间，不把轮询次数当作时钟。
        t=toc(sessionClock);


        %% ---------------------------------------------------------------
        % 温度
        %
        % 为方便预览GUI：
        % 约几分钟就能明显升温。
        % ---------------------------------------------------------------

        heatRise = ...
            6.0 * ...
            (1-exp(-t/150));


        tempVals = ...
            simTempBase + ...
            simTempAmplitude .* ...
            (heatRise/6) + ...
            0.10*sin( ...
            0.025*t + simPhase) + ...
            0.03*randn( ...
            tempChannels,1);


        %% ---------------------------------------------------------------
        % 模拟热漂移
        % ---------------------------------------------------------------

        factor = ...
            1-exp(-t/130);


        probeVals = [ ...
             32*factor; ...
            -20*factor; ...
             42*factor ...
            ];


        probeVals = ...
            probeVals + ...
            [ ...
            0.7*sin(0.030*t); ...
            0.5*sin(0.024*t+1.1); ...
            0.8*sin(0.020*t+2.0) ...
            ];


        probeVals = ...
            probeVals + ...
            [0.10;0.10;0.12] .* ...
            randn(3,1);

    end


%% ========================================================================
% 33. 单点探头范围检查
% ========================================================================

    function [OK,message] = ...
            checkProbeVector(probeVals)


        OK = true;

        message = '';


        if any(~isfinite(probeVals))

            OK = false;

            message = ...
                '存在无效探头数据';

            return;

        end


        for ii = 1:3

            if abs(probeVals(ii)) > ...
                    probeSafeLimit_um

                OK = false;


                message = ...
                    sprintf( ...
                    '探头%d超出±%d μm范围，当前值%.2f μm', ...
                    ii, ...
                    probeSafeLimit_um, ...
                    probeVals(ii));

                return;

            end

        end

    end


%% ========================================================================
% 34. 测量窗口范围检查
% ========================================================================

    function [OK,message] = ...
            checkProbeWindow(buffer)


        OK = true;

        message = '';


        if isempty(buffer)

            OK = false;

            message = ...
                '测量窗口为空';

            return;

        end


        if any(~isfinite(buffer(:)))

            OK = false;

            message = ...
                '测量窗口存在无效数据';

            return;

        end


        for ii = 1:3

            if any( ...
                    abs(buffer(ii,:)) > ...
                    probeSafeLimit_um)

                OK = false;


                maxValue = ...
                    max(abs(buffer(ii,:)));


                message = ...
                    sprintf( ...
                    ['探头%d在测量窗口内曾超出' ...
                    '±%d μm，最大绝对值%.2f μm'], ...
                    ii, ...
                    probeSafeLimit_um, ...
                    maxValue);

                return;

            end

        end

    end


%% ========================================================================
% 35. GUI探头状态
% ========================================================================

    function updateProbeStatus()

        if isempty(lastProbe)
            return;
        end


        allOK = true;


        for ii = 1:3

            value = ...
                lastProbe(ii);


            absValue = ...
                abs(value);


            %% 正常区域

            if absValue < ...
                    probeWarningLimit_um

                status = ...
                    '正常';


                bg = ...
                    [0.84 1.00 0.84];


            %% 90~100

            elseif absValue <= ...
                    probeSafeLimit_um

                status = ...
                    '接近线性边界';


                bg = ...
                    [1.00 0.93 0.72];


            %% 超范围

            else

                status = ...
                    '超出线性范围';


                bg = ...
                    [1.00 0.80 0.80];


                allOK = false;

            end


            set( ...
                probeStatusText(ii), ...
                'String', ...
                sprintf( ...
                '探头%d：%8.2f μm    %s', ...
                ii, ...
                value, ...
                status), ...
                'BackgroundColor', ...
                bg);

        end


        if allOK

            set( ...
                detectPositionText, ...
                'String', ...
                '检测状态：三个探头均在±100 μm有效范围内', ...
                'BackgroundColor', ...
                [0.84 1.00 0.84]);

        else

            set( ...
                detectPositionText, ...
                'String', ...
                '检测状态：当前不能记录热误差样本', ...
                'BackgroundColor', ...
                [1.00 0.80 0.80]);

        end

    end


%% ========================================================================
% 36. 更新当前值表格
% ========================================================================

    function updateCurrentDisplay()

        if isempty(lastTemp) || ...
                isempty(lastProbe)
            return;
        end


        updateProbeStatus();


        dataCell = ...
            cell(numTableRows,2);


        row = 1;


        %% 温度

        for ii = 1:tempChannels

            dataCell{row,1} = ...
                tempNames{ii};


            dataCell{row,2} = ...
                sprintf( ...
                '%.2f ℃', ...
                lastTemp(ii));


            row = row + 1;

        end


        %% 探头

        for ii = 1:3

            dataCell{row,1} = ...
                sprintf( ...
                '探头%d',ii);


            dataCell{row,2} = ...
                sprintf( ...
                '%.2f μm', ...
                lastProbe(ii));


            row = row + 1;

        end


        %% XYZ

        xyzNames = { ...
            '最近有效窗口X热误差', ...
            '最近有效窗口Y热误差', ...
            '最近有效窗口Z热误差'};


        if sampleNumber > 0

            xyzLatest = ...
                sampleXYZ(:,end);

        else

            xyzLatest = ...
                [NaN;NaN;NaN];

        end


        for ii = 1:3

            dataCell{row,1} = ...
                xyzNames{ii};


            if isnan(xyzLatest(ii))

                dataCell{row,2} = ...
                    '--';

            else

                dataCell{row,2} = ...
                    sprintf( ...
                    '%.3f μm', ...
                    xyzLatest(ii));

            end


            row = row + 1;

        end


        set(tbl,'Data',dataCell);


        refreshActionButtons();

    end


%% ========================================================================
% 37. 按钮有效状态
% ========================================================================

    function refreshActionButtons()
        set(btnZero,'Enable','off'); set(btnSample,'Enable','off');
        if ~collecting || windowMode~=0 || ~strcmp(session.State,'running') || ...
                isempty(lastProbe) || isempty(lastTemp) || any(~isfinite(lastTemp))
            return;
        end
        [OK,~]=checkProbeVector(lastProbe);
        if ~OK || ~all(session.Confirmations), return; end
        if zeroReady
            set(btnSample,'Enable','on');
        else
            set(btnZero,'Enable','on');
        end
    end


%% ========================================================================
% 38. 更新图
% ========================================================================

    function updatePlots()

        if isempty(full_time)
            return;
        end


        N = ...
            length(full_time);


        firstIndex = ...
            max( ...
            1, ...
            N-maxDisplayPoints+1);


        t = ...
            full_time(firstIndex:end);


        tempPlot = ...
            full_temp(:,firstIndex:end);


        probePlot = ...
            full_probe(:,firstIndex:end);


        %% ---------------------------------------------------------------
        % 温度
        % ---------------------------------------------------------------

        for ii = 1:tempChannels

            set( ...
                hTemp(ii), ...
                'XData', ...
                t, ...
                'YData', ...
                tempPlot(ii,:));

        end


        allTemp = ...
            tempPlot(isfinite(tempPlot));


        if ~isempty(allTemp)

            ymin = ...
                min(allTemp)-1;


            ymax = ...
                max(allTemp)+1;


            if ymax <= ymin

                ymax = ymin+5;

            end


            ylim( ...
                axTemp, ...
                [ymin ymax]);

        end


        %% ---------------------------------------------------------------
        % 探头
        % ---------------------------------------------------------------

        for ii = 1:3

            set( ...
                hProbe(ii), ...
                'XData', ...
                t, ...
                'YData', ...
                probePlot(ii,:));

        end


        %% 最近5分钟

        tNow = ...
            full_time(end);


        xLeft = ...
            max( ...
            0, ...
            tNow-300);


        xRight = ...
            max( ...
            60, ...
            tNow+10);


        xlim(axTemp, ...
            [xLeft xRight]);


        xlim(axProbe, ...
            [xLeft xRight]);


        %% ---------------------------------------------------------------
        % XYZ离散样本
        % ---------------------------------------------------------------

        if sampleNumber > 0 && ...
                calibrationEnabled


            sampleTime_min = ...
                sampleTime / 60;


            set( ...
                hXYZ(1), ...
                'XData', ...
                sampleTime_min, ...
                'YData', ...
                sampleXYZ(1,:));


            set( ...
                hXYZ(2), ...
                'XData', ...
                sampleTime_min, ...
                'YData', ...
                sampleXYZ(2,:));


            set( ...
                hXYZ(3), ...
                'XData', ...
                sampleTime_min, ...
                'YData', ...
                sampleXYZ(3,:));


            xyzAll = ...
                sampleXYZ(:);


            xyzAll = ...
                xyzAll( ...
                isfinite(xyzAll));


            if ~isempty(xyzAll)

                margin = ...
                    max( ...
                    5, ...
                    0.15 * ...
                    (max(xyzAll)-min(xyzAll)) ...
                    + 2);


                yMin = ...
                    min(xyzAll)-margin;


                yMax = ...
                    max(xyzAll)+margin;


                if yMax <= yMin
                    yMax = yMin+10;
                end


                ylim( ...
                    axXYZ, ...
                    [yMin yMax]);

            end


            xlim( ...
                axXYZ, ...
                [0, ...
                 max( ...
                 1, ...
                 tNow/60+0.2)]);

        end

    end


%% ========================================================================
% 39. 停止并保存
% ========================================================================

    function stopCallback(~,~)
        if collecting
            % Cancellation is recorded before saving, even with zero points.
            stopAndDeleteTimer();
            session.stop(toc(sessionClock),utcNow()); syncSessionProjection();
            collecting=false; clearConfirmations();
            set([confirmStopped confirmReturn confirmAngle],'Enable','off');
            set(btnRecover,'Enable','off');
        elseif sessionSaved
            return;
        end
        sessionSaved=saveData();
        set(btnStart,'Enable','on'); set(btnZero,'Enable','off'); set(btnSample,'Enable','off');
        if sessionSaved
            set(btnStop,'Enable','off'); set(statusText,'String','状态：实验结束，原始/窗口/事件均已保存');
            if pendingClose && ishandle(fig), delete(fig); end
        else
            % Failed disk export must not be erased by a new experiment/close.
            set(btnStop,'Enable','on'); set(statusText,'String','状态：保存失败，请检查路径后点击停止并保存重试');
            pendingClose=false;
        end
    end


%% ========================================================================
% 40. 保存全部中文Excel
% ========================================================================

    function saved=saveData()
        saved=false;
        if isSaving || isempty(session.SessionID), return; end
        isSaving=true;
        % Keep the legacy Chinese workbook/sheet identity and current folder.
        % Legacy time columns now mean actual monotonic elapsed time, and
        % explicit ElapsedSec / UTC / read boundaries document that change.
        fileBase=['龙门机床热误差实验_' session.SessionID];
        fileName=[fileBase '.xlsx'];
        try
            continuousHeader={'时间/s'};
            for ii=1:tempChannels
                continuousHeader{end+1}=sprintf('%s/℃',tempNames{ii});
            end
            continuousHeader=[continuousHeader,{'探头1/μm','探头2/μm','探头3/μm'}];
            continuousMatrix=[full_time',full_temp',full_probe'];
            if isempty(full_time), continuousMatrix=zeros(0,numel(continuousHeader)); end
            [auditHeader,auditRows]=session.auditData('rows');
            % Numeric sensor columns stay in their original positions. Add
            % row-level mode/source/time/quality and identity after them.
            metadata=~ismember(auditHeader,{'Temperature','Probe'});
            continuousCells=[num2cell(continuousMatrix),auditRows(:,metadata)];
            continuousHeader=[continuousHeader,auditHeader(metadata)];
            writecell([continuousHeader;continuousCells],fileName,'Sheet','连续采集数据');
            writecell([continuousHeader;continuousCells],[fileBase '_连续采集数据.csv']);

            sampleHeader={'样本编号','实验时间/s','实验时间/min','测量起始时间/s','测量结束时间/s'};
            for ii=1:tempChannels
                sampleHeader{end+1}=sprintf('%s平均温度/℃',tempNames{ii});
            end
            sampleHeader=[sampleHeader, ...
                {'探头1平均值/μm','探头2平均值/μm','探头3平均值/μm', ...
                '探头1相对冷态变化/μm','探头2相对冷态变化/μm','探头3相对冷态变化/μm', ...
                'X方向热误差/μm','Y方向热误差/μm','Z方向热误差/μm', ...
                'X方向窗口标准差/μm','Y方向窗口标准差/μm','Z方向窗口标准差/μm'}];
            sampleMatrix=[(1:sampleNumber)',sampleTime',sampleTime'/60, ...
                sampleWindowStart',sampleWindowEnd',sampleTemp',sampleProbeMean', ...
                sampleDeltaProbe',sampleXYZ',sampleStdXYZ'];
            if sampleNumber==0, sampleMatrix=zeros(0,numel(sampleHeader)); end
            [auditHeader,auditRows]=session.auditData('samples');
            metadata=~ismember(auditHeader,{'Temperature','Probe','DeltaProbe','XYZ','StdXYZ'});
            sampleCells=[num2cell(sampleMatrix),auditRows(:,metadata)];
            sampleHeader=[sampleHeader,auditHeader(metadata)];
            % Write headers even when there are no accepted heat samples.
            writecell([sampleHeader;sampleCells],fileName,'Sheet','热误差建模样本');
            writecell([sampleHeader;sampleCells],[fileBase '_热误差建模样本.csv']);

            tempMap=cell(tempChannels+1,2); tempMap(1,:)={'温度通道','测点名称'};
            for ii=1:tempChannels
                tempMap(ii+1,:)={sprintf('T%d',ii),tempNames{ii}};
            end
            writecell(tempMap,fileName,'Sheet','温度测点说明');
            zeroCell={'探头','冷态零点/μm','Mode','SessionID','BaselineID','calibration_version'};
            for ii=1:3
                zeroCell(end+1,:)={sprintf('探头%d',ii),zeroProbe(ii),session.Mode,session.SessionID,session.BaselineID,session.CalibrationVersion};
            end
            writecell(zeroCell,fileName,'Sheet','冷态零点');
            calibrationCell=[{'','探头1','探头2','探头3'}; ...
                [{'X方向';'Y方向';'Z方向'},num2cell(C_xyz_from_probe)]];
            writecell(calibrationCell,fileName,'Sheet','三探头标定矩阵');
            calibrationString='未进行XYZ系统标定（XYZ为NaN）';
            if calibrationEnabled, calibrationString='已加载标定文件'; end
            settingCell={'参数','设置值'; ...
                '实验模式',session.Mode;'SessionID',session.SessionID;'BaselineID',session.BaselineID; ...
                'COM端口（未连接）',comPort;'通信波特率（未核验）',baudRate; ...
                '计划连续采样周期/s',sampleIntervalSec;'定时策略','FixedSpacing / BusyMode drop'; ...
                '时间列含义','实际单调经过秒数；UTC记录读取边界；不承诺严格2秒或无丢失'; ...
                '返回检测位稳定时间/s',settleTimeSec;'热误差测量窗口最大时长/s',measurementWindowSec; ...
                '每次测量最少有效采样点数',measurementSamples; ...
                '探头有效范围/μm','-100 ~ +100';'XYZ标定状态',calibrationString; ...
                '标定文件',calibrationFile;'calibration_version',session.CalibrationVersion; ...
                '标定标识含义','矩阵内容标识，保留符号与17位精度，不代表现场核验'; ...
                '真实设备状态','未核验，真实模式构造时拒绝'; ...
                '三项操作确认','主轴停止；同向返回固定点；独立角度复位；每窗重置'; ...
                '窗口范围','[请求时刻+稳定期, 请求时刻+稳定期+窗口时长)，截止轮询不纳入平均'; ...
                '样本UTC含义','窗口完成UTC；StartUTC/EndUTC对应首末纳入点'; ...
                '运行段XYZ','只显示最近已完成窗口的XYZ，不由运行探头实时换算'};
            writecell(settingCell,fileName,'Sheet','实验参数');
            kinds={'windows','events'}; sheets={'测量窗口记录','实验事件日志'};
            for ii=1:numel(kinds)
                [headers,rows]=session.auditData(kinds{ii});
                writecell([headers;rows],fileName,'Sheet',sheets{ii});
                writecell([headers;rows],[fileBase '_' sheets{ii} '.csv']);
            end
            fprintf('Excel及CSV已保存：%s；原始行%d，样本%d，窗口%d，事件%d\n', ...
                fileName,numel(session.Rows),numel(session.Samples),numel(session.Windows),numel(session.Events));
            saved=true;
        catch ME
            fprintf('保存失败（内存记录保留，阻止直接开启下一实验）：%s\n',ME.message);
        end
        isSaving=false;
    end


%% ========================================================================
% 41. 自动模式切换已移除；故障恢复见显式恢复按钮
% ========================================================================

%% ========================================================================
% 42. 更新模式文字
% ========================================================================

    function updateModeText()

        if ~ishandle(modeText)
            return;
        end


        if simulateMode

            set( ...
                modeText, ...
                'String', ...
                '当前模式：离线模拟模式', ...
                'BackgroundColor', ...
                [1.00 0.92 0.72]);

        else

            set( ...
                modeText, ...
                'String', ...
                sprintf( ...
                '当前模式：真实采集模式  %s', ...
                comPort), ...
                'BackgroundColor', ...
                [0.84 1.00 0.84]);

        end

    end


%% ========================================================================
% 43. Timer错误
% ========================================================================

    function timerErrorCallback(~,event)
        if ~collecting, return; end
        reason='timer_error';
        try, reason=event.Data.Message; catch, end
        session.fault(toc(sessionClock),utcNow(),reason);
        syncSessionProjection(); enterFaultUI(reason);
    end


%% ========================================================================
% 44. 停止并删除Timer
% ========================================================================

    function stopAndDeleteTimer()

        if isempty(acqTimer)
            return;
        end


        try

            if isvalid(acqTimer)

                stop(acqTimer);

                delete(acqTimer);

            end

        catch
        end


        acqTimer = [];

    end


%% ========================================================================
% 45. 关闭GUI
% ========================================================================

    function closeFigure(~,~)

        if collecting || ~sessionSaved

            pendingClose = true;


            stopCallback();

        else

            stopAndDeleteTimer();


            if ishandle(fig)
                delete(fig);
            end

        end

    end


%% ========================================================================
% 46. 清理所有资源
% ========================================================================

    function cleanupResources()

        fprintf('\n🧹 正在清理程序资源...\n');


        stopAndDeleteTimer();


        try

            m = [];

        catch
        end


        fprintf('✅ 清理完成。\n');

    end

end
