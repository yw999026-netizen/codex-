function ThermalError_18T_3Probe_V3()
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
% 3. 固定2 s采样周期
% 4. 时间严格记录为：
%
%       0, 2, 4, 6, 8, ...
%
% 5. 冷态零点测量
% 6. 固定检测位热误差测量
% 7. 5 s稳定等待
% 8. 20 s测量窗口，共10个2 s采样点
% 9. 三探头XYZ标定矩阵转换
% 10. ±100 μm有效范围检查
% 11. ±90~±100 μm边界预警
% 12. 连续数据、建模样本分别保存
% 13. Excel全部中文
% 14. COM连接失败自动进入离线模拟模式
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
%     自动采10个点
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
%     自动采10个点（2 s/点）
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


% 固定10个点
measurementSamples = ...
    measurementWindowSec / sampleIntervalSec;


% ---------------- 是否强制使用离线模式 ----------------
%
% false：
%   先尝试真实设备；
%   连接失败自动模拟。
%
% true：
%   完全不连接设备，直接模拟。
%

forceOfflineMode = false;


% COM失败是否自动模拟

autoFallbackOffline = true;


% ---------------- 连续读取失败次数 ----------------

maxReadErrors = 5;


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
% 当前：
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

m = [];

simulateMode = forceOfflineMode;


if forceOfflineMode

    fprintf('\n=============================================\n');
    fprintf('当前设置：强制离线模拟模式\n');
    fprintf('不会尝试连接COM端口\n');
    fprintf('=============================================\n');

else

    %% 清理旧串口

    try
        delete(instrfindall);
    catch
    end


    %% 尝试Modbus

    try

        fprintf('\n正在连接 %s ...\n', comPort);


        m = modbus( ...
            'serialrtu', ...
            comPort, ...
            'BaudRate', baudRate, ...
            'DataBits', 8, ...
            'StopBits', 1, ...
            'Parity', 'none');


        m.Timeout = 2;


        simulateMode = false;


        fprintf('✅ Modbus连接成功。\n');

        fprintf('温度地址：1、2、3\n');

        fprintf('电涡流地址：%d、%d、%d\n', ...
            probeSensors(1).id, ...
            probeSensors(2).id, ...
            probeSensors(3).id);


    catch ME

        if autoFallbackOffline

            fprintf('\n⚠️ 真实设备连接失败：\n');
            fprintf('%s\n', ME.message);

            fprintf('\n自动进入离线模拟模式。\n');

            m = [];

            simulateMode = true;

        else

            error('Modbus连接失败：%s', ...
                ME.message);

        end

    end

end


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

calibrationIsDemo = false;


C_xyz_from_probe = eye(3);


if exist(calibrationFile,'file')

    try

        calData = ...
            load(calibrationFile);


        if isfield( ...
                calData, ...
                'C_xyz_from_probe') && ...
                isequal( ...
                size(calData.C_xyz_from_probe), ...
                [3 3])


            C_xyz_from_probe = ...
                calData.C_xyz_from_probe;


            calibrationEnabled = true;

            calibrationIsDemo = false;


            fprintf('\n✅ 已加载真实XYZ标定矩阵：\n');

            disp(C_xyz_from_probe);

        end


    catch ME

        fprintf('⚠️ 标定文件读取失败：%s\n', ...
            ME.message);

    end

end


%% 离线模拟采用演示矩阵

if simulateMode && ~calibrationEnabled

    C_xyz_from_probe = [ ...
         1.000,  0.035, -0.020; ...
        -0.025,  1.000,  0.030; ...
         0.018, -0.022,  1.000 ...
        ];


    calibrationEnabled = true;

    calibrationIsDemo = true;


    fprintf('\n离线模式使用演示XYZ矩阵。\n');

end


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
    [30 20 1580 880], ...
    'CloseRequestFcn', ...
    @closeFigure);


%% ========================================================================
% 9. 模式状态
% ========================================================================

modeText = uicontrol( ...
    'Parent', fig, ...
    'Style', 'text', ...
    'Position', [1150 825 380 35], ...
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
    '连续采样周期：%d s（固定）', ...
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
    '测量窗口：%d s / %d点', ...
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
    {'X方向热误差', ...
     'Y方向热误差', ...
     'Z方向热误差'} ...
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
% 2 = 采集10个正式测量点
%
% ========================================================================

windowMode = 0;

windowPhase = 0;


windowRequestClock = [];

windowTempBuffer = [];

windowProbeBuffer = [];

windowTimeBuffer = [];


%% ========================================================================
% 20. 离线模拟状态
% ========================================================================

simTick = 0;


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

        if collecting
            return;
        end


        %% ---------------------------------------------------------------
        % 清空本轮实验数据
        % ---------------------------------------------------------------

        sampleIndex = 0;


        full_time = [];

        full_temp = [];

        full_probe = [];


        lastTemp = [];

        lastProbe = [];


        zeroReady = false;

        zeroProbe = [NaN;NaN;NaN];

        zeroTemp = nan(tempChannels,1);


        sampleNumber = 0;

        sampleTime = [];

        sampleTemp = [];

        sampleProbeMean = [];

        sampleDeltaProbe = [];

        sampleXYZ = [];

        sampleStdXYZ = [];

        sampleWindowStart = [];

        sampleWindowEnd = [];


        windowMode = 0;

        windowPhase = 0;


        simTick = 0;


        collecting = true;


        set(btnStart,'Enable','off');

        set(btnStop,'Enable','on');

        set(btnZero,'Enable','off');

        set(btnSample,'Enable','off');


        set(statusText, ...
            'String', ...
            '状态：正在读取 t = 0 s 初始数据');


        set(sampleCountText, ...
            'String', ...
            '有效热误差样本：0');


        set(zeroStatusText, ...
            'String', ...
            '冷态零点：未设置');


        fprintf('\n=============================================\n');

        fprintf('开始本轮热误差实验\n');

        fprintf('固定采样周期：%d s\n', ...
            sampleIntervalSec);

        fprintf('记录时间：0、2、4、6、8…… s\n');

        fprintf('=============================================\n');


        %% ---------------------------------------------------------------
        % t = 0 s读取一次
        % ---------------------------------------------------------------

        initialOK = false;

        failureCount = 0;


        while ~initialOK && collecting

            try

                [tempVals,probeVals] = ...
                    readAllSensors();


                sampleIndex = 0;


                full_time = 0;

                full_temp = tempVals;

                full_probe = probeVals;


                lastTemp = tempVals;

                lastProbe = probeVals;


                initialOK = true;


                updateCurrentDisplay();

                updatePlots();


                fprintf('✅ t = 0 s 数据读取成功。\n');


            catch ME

                failureCount = ...
                    failureCount + 1;


                fprintf( ...
                    '⚠️ 初始读取失败 %d 次：%s\n', ...
                    failureCount, ...
                    ME.message);


                if failureCount >= 3 && ...
                        ~simulateMode && ...
                        autoFallbackOffline

                    switchToOfflineMode( ...
                        '设备连接成功，但读取数据失败');


                    failureCount = 0;

                else

                    pause(0.5);

                end

            end

        end


        if ~collecting
            return;
        end


        %% ---------------------------------------------------------------
        % 建立严格2秒FixedRate定时器
        % ---------------------------------------------------------------

        acqTimer = timer( ...
            'ExecutionMode', ...
            'fixedRate', ...
            'Period', ...
            sampleIntervalSec, ...
            'StartDelay', ...
            sampleIntervalSec, ...
            'BusyMode', ...
            'drop', ...
            'TimerFcn', ...
            @acquisitionTick, ...
            'ErrorFcn', ...
            @timerErrorCallback);


        start(acqTimer);


        set(statusText, ...
            'String', ...
            '状态：每2 s固定采集中');


        refreshActionButtons();

    end


%% ========================================================================
% 23. 2秒定时采样
% ========================================================================

    function acquisitionTick(~,~)

        if ~collecting
            return;
        end


        try

            %% -----------------------------------------------------------
            % 读取数据
            % -----------------------------------------------------------

            [tempVals,probeVals] = ...
                readAllSensors();


            %% -----------------------------------------------------------
            % 时间严格使用理论2秒网格
            %
            % 不用toc。
            %
            % Excel：
            %
            % 0
            % 2
            % 4
            % 6
            % ...
            %
            % -----------------------------------------------------------

            sampleIndex = ...
                sampleIndex + 1;


            tNow = ...
                sampleIndex * ...
                sampleIntervalSec;


            %% -----------------------------------------------------------
            % 保存连续数据
            % -----------------------------------------------------------

            full_time(end+1) = ...
                tNow;


            full_temp(:,end+1) = ...
                tempVals;


            full_probe(:,end+1) = ...
                probeVals;


            lastTemp = ...
                tempVals;


            lastProbe = ...
                probeVals;


            %% -----------------------------------------------------------
            % 当前是否正在进行冷态/热误差测量
            % -----------------------------------------------------------

            handleMeasurementWindow( ...
                tempVals, ...
                probeVals, ...
                tNow);


            %% -----------------------------------------------------------
            % GUI
            % -----------------------------------------------------------

            updateCurrentDisplay();

            updatePlots();


            %% -----------------------------------------------------------
            % 命令行
            % -----------------------------------------------------------

            fprintf( ...
                ['时间=%6d s | ' ...
                 'T1=%5.1f T2=%5.1f T3=%5.1f | ' ...
                 'P1=%7.2f P2=%7.2f P3=%7.2f μm\n'], ...
                tNow, ...
                tempVals(1), ...
                tempVals(2), ...
                tempVals(3), ...
                probeVals(1), ...
                probeVals(2), ...
                probeVals(3));


            drawnow limitrate;


        catch ME

            fprintf( ...
                '⚠️ 第%d个采样周期读取失败：%s\n', ...
                sampleIndex+1, ...
                ME.message);


            % 当前设计：
            % 单次失败不伪造数据、不增加sampleIndex。
            %
            % 下一次timer重新读取。
            %
            % 如果真实实验中频繁出现，
            % 应优先检查RS485通信。

        end

    end


%% ========================================================================
% 24. 设置冷态零点
% ========================================================================

    function zeroCallback(~,~)

        if ~collecting || ...
                windowMode ~= 0
            return;
        end


        if isempty(lastProbe)
            return;
        end


        [OK,message] = ...
            checkProbeVector(lastProbe);


        if ~OK

            fprintf('\n❌ 不能设置冷态零点：%s\n', ...
                message);

            return;

        end


        startMeasurementWindow(1);

    end


%% ========================================================================
% 25. 记录热误差样本
% ========================================================================

    function sampleCallback(~,~)

        if ~collecting || ...
                windowMode ~= 0
            return;
        end


        if ~zeroReady

            fprintf('\n⚠️ 请先设置冷态零点。\n');

            return;

        end


        if isempty(lastProbe)
            return;
        end


        [OK,message] = ...
            checkProbeVector(lastProbe);


        if ~OK

            fprintf('\n❌ 当前不能记录样本：%s\n', ...
                message);

            return;

        end


        startMeasurementWindow(2);

    end


%% ========================================================================
% 26. 启动测量任务
% ========================================================================

    function startMeasurementWindow(modeValue)

        windowMode = modeValue;

        windowPhase = 1;


        windowRequestClock = tic;


        windowTempBuffer = [];

        windowProbeBuffer = [];

        windowTimeBuffer = [];


        set(btnZero,'Enable','off');

        set(btnSample,'Enable','off');


        if modeValue == 1

            fprintf('\n=============================================\n');

            fprintf('开始设置冷态零点\n');

        else

            fprintf('\n=============================================\n');

            fprintf('开始记录第 %d 个热误差样本\n', ...
                sampleNumber+1);

        end


        fprintf('先等待稳定：%d s\n', ...
            settleTimeSec);

        fprintf('随后采集：%d 个点 × %d s\n', ...
            measurementSamples, ...
            sampleIntervalSec);

        fprintf('=============================================\n');


        set(statusText, ...
            'String', ...
            sprintf( ...
            '状态：等待机械稳定 %d s', ...
            settleTimeSec));

    end


%% ========================================================================
% 27. 处理稳定和测量窗口
% ========================================================================

    function handleMeasurementWindow( ...
            tempVals, ...
            probeVals, ...
            tNow)


        if windowMode == 0
            return;
        end


        %% ---------------------------------------------------------------
        % 等待5秒
        %
        % 等待时间使用实际墙钟；
        % 正式采样仍然只发生在2秒采样节点。
        % ---------------------------------------------------------------

        if windowPhase == 1

            elapsed = ...
                toc(windowRequestClock);


            remaining = ...
                settleTimeSec - elapsed;


            if remaining > 0

                set(statusText, ...
                    'String', ...
                    sprintf( ...
                    '状态：等待稳定，还剩约 %.1f s', ...
                    remaining));

                return;

            end


            windowPhase = 2;


            fprintf('✅ 稳定等待完成，开始正式取10个点。\n');

        end


        %% ---------------------------------------------------------------
        % 正式收集2秒采样点
        % ---------------------------------------------------------------

        if windowPhase == 2

            windowTempBuffer(:,end+1) = ...
                tempVals;


            windowProbeBuffer(:,end+1) = ...
                probeVals;


            windowTimeBuffer(end+1) = ...
                tNow;


            currentCount = ...
                size(windowProbeBuffer,2);


            set(statusText, ...
                'String', ...
                sprintf( ...
                '状态：测量中 %d / %d 个点', ...
                currentCount, ...
                measurementSamples));


            if currentCount >= measurementSamples

                processMeasurementWindow();

            end

        end

    end


%% ========================================================================
% 28. 处理一个完整测量窗口
% ========================================================================

    function processMeasurementWindow()

        %% ---------------------------------------------------------------
        % 整个窗口都必须在±100 μm以内
        % ---------------------------------------------------------------

        [OK,message] = ...
            checkProbeWindow( ...
            windowProbeBuffer);


        if ~OK

            fprintf('\n=============================================\n');

            fprintf('❌ 本次测量无效\n');

            fprintf('原因：%s\n',message);

            fprintf('本次数据不会进入建模样本。\n');

            fprintf('=============================================\n');


            resetMeasurementWindow();

            return;

        end


        %% ---------------------------------------------------------------
        % 平均值
        % ---------------------------------------------------------------

        meanTemp = ...
            mean(windowTempBuffer,2);


        meanProbe = ...
            mean(windowProbeBuffer,2);


        tMean = ...
            round(mean(windowTimeBuffer));


        tStart = ...
            windowTimeBuffer(1);


        tEnd = ...
            windowTimeBuffer(end);


        %% ---------------------------------------------------------------
        % 冷态零点
        % ---------------------------------------------------------------

        if windowMode == 1

            zeroProbe = ...
                meanProbe;


            zeroTemp = ...
                meanTemp;


            zeroReady = true;


            fprintf('\n=============================================\n');

            fprintf('✅ 冷态零点设置完成\n');

            fprintf('探头1零点 = %.3f μm\n', ...
                zeroProbe(1));

            fprintf('探头2零点 = %.3f μm\n', ...
                zeroProbe(2));

            fprintf('探头3零点 = %.3f μm\n', ...
                zeroProbe(3));


            for ii = 1:3

                if abs(zeroProbe(ii)) > ...
                        probeRecommendedZeroLimit_um

                    fprintf( ...
                        '⚠️ 探头%d冷态位置离中点较远：%.2f μm\n', ...
                        ii, ...
                        zeroProbe(ii));

                end

            end


            fprintf('=============================================\n');


            set(zeroStatusText, ...
                'String', ...
                sprintf( ...
                '冷态零点：P1=%.2f，P2=%.2f，P3=%.2f μm', ...
                zeroProbe(1), ...
                zeroProbe(2), ...
                zeroProbe(3)));


        %% ---------------------------------------------------------------
        % 正式热误差样本
        % ---------------------------------------------------------------

        elseif windowMode == 2

            deltaProbe = ...
                meanProbe - ...
                zeroProbe;


            %% XYZ转换

            if calibrationEnabled

                xyzMean = ...
                    C_xyz_from_probe * ...
                    deltaProbe;


                deltaProbeWindow = ...
                    windowProbeBuffer - ...
                    zeroProbe;


                xyzWindow = ...
                    C_xyz_from_probe * ...
                    deltaProbeWindow;


                xyzStd = ...
                    std( ...
                    xyzWindow, ...
                    0, ...
                    2);

            else

                xyzMean = ...
                    [NaN;NaN;NaN];


                xyzStd = ...
                    [NaN;NaN;NaN];

            end


            %% 保存正式样本

            sampleNumber = ...
                sampleNumber + 1;


            sampleTime(end+1) = ...
                tMean;


            sampleTemp(:,end+1) = ...
                meanTemp;


            sampleProbeMean(:,end+1) = ...
                meanProbe;


            sampleDeltaProbe(:,end+1) = ...
                deltaProbe;


            sampleXYZ(:,end+1) = ...
                xyzMean;


            sampleStdXYZ(:,end+1) = ...
                xyzStd;


            sampleWindowStart(end+1) = ...
                tStart;


            sampleWindowEnd(end+1) = ...
                tEnd;


            %% 显示

            fprintf('\n=============================================\n');

            fprintf('✅ 第 %d 个热误差样本完成\n', ...
                sampleNumber);


            fprintf('实验时间：%d s\n', ...
                tMean);


            fprintf('\n测量窗口：\n');

            fprintf('%d s ～ %d s\n', ...
                tStart, ...
                tEnd);


            fprintf('\n探头平均值：\n');

            fprintf('P1 = %.3f μm\n', ...
                meanProbe(1));

            fprintf('P2 = %.3f μm\n', ...
                meanProbe(2));

            fprintf('P3 = %.3f μm\n', ...
                meanProbe(3));


            fprintf('\n相对冷态变化：\n');

            fprintf('ΔP1 = %.3f μm\n', ...
                deltaProbe(1));

            fprintf('ΔP2 = %.3f μm\n', ...
                deltaProbe(2));

            fprintf('ΔP3 = %.3f μm\n', ...
                deltaProbe(3));


            if calibrationEnabled

                fprintf('\nXYZ热误差：\n');

                fprintf('X = %.3f μm\n', ...
                    xyzMean(1));

                fprintf('Y = %.3f μm\n', ...
                    xyzMean(2));

                fprintf('Z = %.3f μm\n', ...
                    xyzMean(3));


                fprintf('\n窗口波动标准差：\n');

                fprintf('σX = %.3f μm\n', ...
                    xyzStd(1));

                fprintf('σY = %.3f μm\n', ...
                    xyzStd(2));

                fprintf('σZ = %.3f μm\n', ...
                    xyzStd(3));

            else

                fprintf('\n⚠️ 当前没有真实XYZ标定矩阵。\n');

            end


            fprintf('=============================================\n');


            set(sampleCountText, ...
                'String', ...
                sprintf( ...
                '有效热误差样本：%d', ...
                sampleNumber));

        end


        resetMeasurementWindow();

    end


%% ========================================================================
% 29. 重置测量窗口
% ========================================================================

    function resetMeasurementWindow()

        windowMode = 0;

        windowPhase = 0;


        windowTempBuffer = [];

        windowProbeBuffer = [];

        windowTimeBuffer = [];


        set(statusText, ...
            'String', ...
            '状态：每2 s固定连续采集中');


        refreshActionButtons();

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


        %% 每调用一次相当于2秒

        t = ...
            simTick * ...
            sampleIntervalSec;


        simTick = ...
            simTick + 1;


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
            'X方向热误差', ...
            'Y方向热误差', ...
            'Z方向热误差'};


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

        if ~collecting || ...
                windowMode ~= 0

            set(btnZero,'Enable','off');

            set(btnSample,'Enable','off');

            return;

        end


        if isempty(lastProbe)

            set(btnZero,'Enable','off');

            set(btnSample,'Enable','off');

            return;

        end


        [OK,~] = ...
            checkProbeVector(lastProbe);


        if OK

            set(btnZero,'Enable','on');


            if zeroReady

                set(btnSample,'Enable','on');

            else

                set(btnSample,'Enable','off');

            end

        else

            set(btnZero,'Enable','off');

            set(btnSample,'Enable','off');

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
            tempPlot(:);


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

        if ~collecting
            return;
        end


        collecting = false;


        set(statusText, ...
            'String', ...
            '状态：停止采集，正在保存数据');


        %% 停止Timer

        stopAndDeleteTimer();


        %% 保存

        saveData();


        %% GUI按钮

        set(btnStart,'Enable','on');

        set(btnStop,'Enable','off');

        set(btnZero,'Enable','off');

        set(btnSample,'Enable','off');


        set(statusText, ...
            'String', ...
            '状态：实验结束');


        fprintf('\n🏁 本轮实验结束。\n');


        if pendingClose && ...
                ishandle(fig)

            delete(fig);

        end

    end


%% ========================================================================
% 40. 保存全部中文Excel
% ========================================================================

    function saveData()

        if isSaving
            return;
        end


        isSaving = true;


        fileName = ...
            sprintf( ...
            '龙门机床热误差实验_%s.xlsx', ...
            datestr( ...
            now, ...
            'yyyymmdd_HHMMSS'));


        fprintf('\n=============================================\n');

        fprintf('开始保存Excel...\n');


        try

            %% ============================================================
            % Sheet 1：连续采集数据
            % ============================================================

            continuousHeader = ...
                cell(1, ...
                1+tempChannels+3);


            continuousHeader{1} = ...
                '时间/s';


            for ii = 1:tempChannels

                continuousHeader{1+ii} = ...
                    sprintf( ...
                    '%s/℃', ...
                    tempNames{ii});

            end


            continuousHeader{ ...
                1+tempChannels+1} = ...
                '探头1/μm';


            continuousHeader{ ...
                1+tempChannels+2} = ...
                '探头2/μm';


            continuousHeader{ ...
                1+tempChannels+3} = ...
                '探头3/μm';


            continuousMatrix = [ ...
                full_time', ...
                full_temp', ...
                full_probe' ...
                ];


            writecell( ...
                continuousHeader, ...
                fileName, ...
                'Sheet', ...
                '连续采集数据', ...
                'Range', ...
                'A1');


            writematrix( ...
                continuousMatrix, ...
                fileName, ...
                'Sheet', ...
                '连续采集数据', ...
                'Range', ...
                'A2');


            %% ============================================================
            % Sheet 2：热误差建模样本
            % ============================================================

            if sampleNumber > 0

                sampleHeader = { ...
                    '样本编号', ...
                    '实验时间/s', ...
                    '实验时间/min', ...
                    '测量起始时间/s', ...
                    '测量结束时间/s'};


                %% 18温度

                for ii = 1:tempChannels

                    sampleHeader{end+1} = ...
                        sprintf( ...
                        '%s平均温度/℃', ...
                        tempNames{ii});

                end


                %% 探头

                sampleHeader = [ ...
                    sampleHeader, ...
                    { ...
                    '探头1平均值/μm', ...
                    '探头2平均值/μm', ...
                    '探头3平均值/μm', ...
                    '探头1相对冷态变化/μm', ...
                    '探头2相对冷态变化/μm', ...
                    '探头3相对冷态变化/μm', ...
                    'X方向热误差/μm', ...
                    'Y方向热误差/μm', ...
                    'Z方向热误差/μm', ...
                    'X方向窗口标准差/μm', ...
                    'Y方向窗口标准差/μm', ...
                    'Z方向窗口标准差/μm'} ...
                    ];


                sampleNo = ...
                    (1:sampleNumber)';


                sampleMatrix = [ ...
                    sampleNo, ...
                    sampleTime', ...
                    sampleTime'/60, ...
                    sampleWindowStart', ...
                    sampleWindowEnd', ...
                    sampleTemp', ...
                    sampleProbeMean', ...
                    sampleDeltaProbe', ...
                    sampleXYZ', ...
                    sampleStdXYZ' ...
                    ];


                writecell( ...
                    sampleHeader, ...
                    fileName, ...
                    'Sheet', ...
                    '热误差建模样本', ...
                    'Range', ...
                    'A1');


                writematrix( ...
                    sampleMatrix, ...
                    fileName, ...
                    'Sheet', ...
                    '热误差建模样本', ...
                    'Range', ...
                    'A2');

            end


            %% ============================================================
            % Sheet 3：温度测点说明
            % ============================================================

            tempMap = ...
                cell(tempChannels+1,2);


            tempMap(1,:) = ...
                {'温度通道','测点名称'};


            for ii = 1:tempChannels

                tempMap{ii+1,1} = ...
                    sprintf('T%d',ii);


                tempMap{ii+1,2} = ...
                    tempNames{ii};

            end


            writecell( ...
                tempMap, ...
                fileName, ...
                'Sheet', ...
                '温度测点说明');


            %% ============================================================
            % Sheet 4：冷态零点
            % ============================================================

            if zeroReady

                zeroCell = { ...
                    '探头','冷态零点/μm'; ...
                    '探头1',zeroProbe(1); ...
                    '探头2',zeroProbe(2); ...
                    '探头3',zeroProbe(3)};


                writecell( ...
                    zeroCell, ...
                    fileName, ...
                    'Sheet', ...
                    '冷态零点');

            end


            %% ============================================================
            % Sheet 5：三探头标定矩阵
            % ============================================================

            if calibrationEnabled

                calibrationCell = { ...
                    '', ...
                    '探头1', ...
                    '探头2', ...
                    '探头3'; ...
                    'X方向', ...
                    C_xyz_from_probe(1,1), ...
                    C_xyz_from_probe(1,2), ...
                    C_xyz_from_probe(1,3); ...
                    'Y方向', ...
                    C_xyz_from_probe(2,1), ...
                    C_xyz_from_probe(2,2), ...
                    C_xyz_from_probe(2,3); ...
                    'Z方向', ...
                    C_xyz_from_probe(3,1), ...
                    C_xyz_from_probe(3,2), ...
                    C_xyz_from_probe(3,3)};


                writecell( ...
                    calibrationCell, ...
                    fileName, ...
                    'Sheet', ...
                    '三探头标定矩阵');

            end


            %% ============================================================
            % Sheet 6：实验参数
            % ============================================================

            if simulateMode

                modeString = ...
                    '离线模拟模式';

            else

                modeString = ...
                    '真实采集模式';

            end


            if calibrationIsDemo

                calibrationString = ...
                    '演示标定矩阵';

            elseif calibrationEnabled

                calibrationString = ...
                    '真实标定矩阵';

            else

                calibrationString = ...
                    '未进行XYZ系统标定';

            end


            settingCell = { ...
                '参数','设置值'; ...
                '实验模式',modeString; ...
                'COM端口',comPort; ...
                '通信波特率',baudRate; ...
                '固定连续采样周期/s',sampleIntervalSec; ...
                '返回检测位稳定时间/s',settleTimeSec; ...
                '热误差测量窗口/s',measurementWindowSec; ...
                '每次测量采样点数',measurementSamples; ...
                '探头1 Modbus地址',probeSensors(1).id; ...
                '探头2 Modbus地址',probeSensors(2).id; ...
                '探头3 Modbus地址',probeSensors(3).id; ...
                '探头PV寄存器',probeSensors(1).reg; ...
                '探头寄存器缩放',probeSensors(1).scale; ...
                '电涡流有效范围/μm','-100 ~ +100'; ...
                '边界预警范围/μm','±90 ~ ±100'; ...
                'XYZ标定状态',calibrationString};


            writecell( ...
                settingCell, ...
                fileName, ...
                'Sheet', ...
                '实验参数');


            fprintf('✅ Excel保存成功。\n');

            fprintf('文件：%s\n', ...
                fileName);


            fprintf('连续采样点：%d\n', ...
                length(full_time));


            fprintf('热误差建模样本：%d\n', ...
                sampleNumber);


            fprintf('=============================================\n');


        catch ME

            fprintf('\n❌ Excel保存失败：\n');

            fprintf('%s\n',ME.message);

        end


        isSaving = false;

    end


%% ========================================================================
% 41. 自动切换离线模式
% ========================================================================

    function switchToOfflineMode(reason)

        fprintf('\n=============================================\n');

        fprintf('⚠️ 自动进入离线模拟模式\n');

        fprintf('原因：%s\n',reason);

        fprintf('=============================================\n');


        simulateMode = true;

        m = [];


        simTick = 0;


        if ~calibrationEnabled

            C_xyz_from_probe = [ ...
                 1.000,  0.035, -0.020; ...
                -0.025,  1.000,  0.030; ...
                 0.018, -0.022,  1.000 ...
                ];


            calibrationEnabled = true;

            calibrationIsDemo = true;

        end


        updateModeText();

    end


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

        fprintf('\n⚠️ 2秒采样定时器发生错误。\n');


        try

            fprintf('%s\n', ...
                event.Data.Message);

        catch
        end

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

        if collecting

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


        try

            delete(instrfindall);

        catch
        end


        fprintf('✅ 清理完成。\n');

    end

end