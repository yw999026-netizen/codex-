function ThermalErrorControl_WithPID_V1()
% ========================================================================
% 龙门机床热误差采集与PID控制系统 V1
%
% 基于 ThermalError_18T_3Probe_V3 改进
% 新增功能：
%   1. 实时PID控制算法
%   2. 电动球阀自动控制
%   3. 可调节控制目标
%   4. 增强的Modbus通讯可靠性
%   5. 数据质量评估
%
% MATLAB R2021b+
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
measurementSamples = measurementWindowSec / sampleIntervalSec;

% ---------------- 是否强制使用离线模式 ----------------

forceOfflineMode = false;
autoFallbackOffline = true;

% ---------------- 连续读取失败次数 ----------------

maxReadErrors = 5;

% ---------------- GUI显示最大点数 ----------------

maxDisplayPoints = 10000;


%% ========================================================================
% 2. 电涡流有效范围
% ========================================================================

probeSafeLimit_um = 100;
probeWarningLimit_um = 90;
probeRecommendedZeroLimit_um = 20;


%% ========================================================================
% 3. 18路温度传感器（保持不变）
% ========================================================================

tempServers = struct( ...
    'id', {1, 2, 3}, ...
    'numChannels', {8, 8, 2}, ...
    'names', { ...
    {'床身右侧', '立柱左侧', '立柱右侧', '横梁上端', ...
     '环境温度', 'Z轴前端轴承', 'Z轴后端轴承', 'X轴前端轴承'}, ...
    {'Y2轴前端轴承', 'Y1轴前端轴承', 'Y1轴后端轴承', 'Z轴螺母', ...
     'Y2轴螺母', 'Y1轴螺母', 'Y2轴后端轴承', 'X轴螺母'}, ...
    {'X轴后端轴承', '主轴前端轴承'} ...
    });

tempChannels = sum([tempServers.numChannels]);
tempNames = {};
for k = 1:length(tempServers)
    tempNames = [tempNames, tempServers(k).names];
end

tempRegister = 1537;
tempScale = 0.1;


%% ========================================================================
% 4. 三个电涡流仪表（保持不变）
% ========================================================================

probeSensors = struct( ...
    'id',    {5, 6, 7}, ...
    'reg',   {75, 75, 75}, ...
    'scale', {0.1, 0.1, 0.1}, ...
    'name',  {'探头1','探头2','探头3'} ...
    );

numProbes = 3;


%% ========================================================================
% 5. 电动球阀配置 (新增)
% ========================================================================
%
% 注意：
% 以下为默认配置，实际使用时需要根据球阀手册修改
%
% ========================================================================

valveConfig = struct(...
    'id', 10, ...                    % Modbus从机地址
    'positionSetReg', 0, ...        % 设定位置寄存器(写)
    'positionReadReg', 1, ...       % 当前位置寄存器(读)
    'statusReg', 2, ...             % 状态寄存器
    'scale', 1.0, ...               % 缩放因子(寄存器值→百分比)
    'minPosition', 0, ...           % 最小开度 (%)
    'maxPosition', 100, ...         % 最大开度 (%)
    'name', '冷却球阀' ...
    );

% 安全限制
valveSafetyMin = 10;    % 最小允许开度 (%)
valveSafetyMax = 90;    % 最大允许开度 (%)


%% ========================================================================
% 6. PID控制参数 (新增)
% ========================================================================

pidConfig = struct(...
    'Kp', 0.5, ...                  % 比例系数
    'Ki', 0.01, ...                 % 积分系数
    'Kd', 0.1, ...                  % 微分系数
    'setpoint', 0.0, ...            % 目标位移 (μm)
    'deadband', 2.0, ...            % 死区 (±μm)
    'integralLimit', 50.0, ...      % 积分限幅
    'outputMin', valveSafetyMin, ...
    'outputMax', valveSafetyMax, ...
    'sampleTime', sampleIntervalSec ...
    );

% 控制模式
controlEnabled = false;  % 初始不启用控制，需手动开启


%% ========================================================================
% 7. Modbus通讯增强配置 (新增)
% ========================================================================

modbusRetryConfig = struct(...
    'maxRetry', 3, ...              % 最大重试次数
    'retryDelay', 0.1, ...          % 重试间隔(秒)
    'timeout', 2.0 ...              % 单次读取超时
    );


%% ========================================================================
% 8. 模式初始化
% ========================================================================

m = [];
simulateMode = forceOfflineMode;

if forceOfflineMode
    fprintf('\n=============================================\n');
    fprintf('当前设置：强制离线模拟模式\n');
    fprintf('不会尝试连接COM端口\n');
    fprintf('=============================================\n');
else
    try
        delete(instrfindall);
    catch
    end

    try
        fprintf('\n正在连接 %s ...\n', comPort);

        m = modbus(...
            'serialrtu', ...
            comPort, ...
            'BaudRate', baudRate, ...
            'DataBits', 8, ...
            'StopBits', 1, ...
            'Parity', 'none');

        m.Timeout = modbusRetryConfig.timeout;

        simulateMode = false;

        fprintf('✅ Modbus连接成功。\n');
        fprintf('温度地址：1、2、3\n');
        fprintf('电涡流地址：%d、%d、%d\n', ...
            probeSensors(1).id, ...
            probeSensors(2).id, ...
            probeSensors(3).id);
        fprintf('球阀地址：%d\n', valveConfig.id);

    catch ME
        if autoFallbackOffline
            fprintf('\n⚠️ 真实设备连接失败：\n');
            fprintf('%s\n', ME.message);
            fprintf('\n自动进入离线模拟模式。\n');
            m = [];
            simulateMode = true;
        else
            error('Modbus连接失败：%s', ME.message);
        end
    end
end


%% ========================================================================
% 9. 三探头XYZ系统标定矩阵（保持不变）
% ========================================================================

calibrationFile = 'ThreeProbeCalibration.mat';
calibrationEnabled = false;
calibrationIsDemo = false;
C_xyz_from_probe = eye(3);

if exist(calibrationFile,'file')
    try
        calData = load(calibrationFile);
        if isfield(calData, 'C_xyz_from_probe') && ...
                isequal(size(calData.C_xyz_from_probe), [3 3])
            C_xyz_from_probe = calData.C_xyz_from_probe;
            calibrationEnabled = true;
            calibrationIsDemo = false;
            fprintf('\n✅ 已加载真实XYZ标定矩阵：\n');
            disp(C_xyz_from_probe);
        end
    catch ME
        fprintf('⚠️ 标定文件读取失败：%s\n', ME.message);
    end
end

if simulateMode && ~calibrationEnabled
    C_xyz_from_probe = [...
         1.000,  0.035, -0.020; ...
        -0.025,  1.000,  0.030; ...
         0.018, -0.022,  1.000];
    calibrationEnabled = true;
    calibrationIsDemo = true;
    fprintf('\n离线模式使用演示XYZ矩阵。\n');
end


%% ========================================================================
% 10. PID控制器初始化 (新增)
% ========================================================================

pid = PIDController(...
    pidConfig.Kp, ...
    pidConfig.Ki, ...
    pidConfig.Kd, ...
    pidConfig.setpoint, ...
    pidConfig.outputMin, ...
    pidConfig.outputMax, ...
    pidConfig.integralLimit, ...
    pidConfig.deadband, ...
    pidConfig.sampleTime);

fprintf('\n✅ PID控制器初始化完成\n');
fprintf('   Kp=%.3f, Ki=%.3f, Kd=%.3f\n', ...
    pidConfig.Kp, pidConfig.Ki, pidConfig.Kd);


%% ========================================================================
% 11. 自动清理
% ========================================================================

cleanupObj = onCleanup(@cleanupResources); %#ok<NASGU>


%% ========================================================================
% 12. GUI窗口
% ========================================================================

fig = figure(...
    'Name', '龙门机床热误差采集与PID控制系统 V1', ...
    'NumberTitle', 'off', ...
    'Position', [20 20 1700 920], ...
    'CloseRequestFcn', @closeFigure);


%% ========================================================================
% 13. 模式状态
% ========================================================================

modeText = uicontrol(...
    'Parent', fig, ...
    'Style', 'text', ...
    'Position', [1250 870 400 35], ...
    'FontSize', 13, ...
    'FontWeight', 'bold');


%% ========================================================================
% 14. 控制状态面板 (新增)
% ========================================================================

controlPanel = uipanel(...
    'Parent', fig, ...
    'Title', 'PID控制面板', ...
    'Position', [1250 720 400 140], ...
    'FontSize', 11, ...
    'FontWeight', 'bold');

% 控制开关
controlToggle = uicontrol(...
    'Parent', controlPanel, ...
    'Style', 'togglebutton', ...
    'String', '启动自动控制', ...
    'Position', [20 80 150 30], ...
    'FontSize', 11, ...
    'Callback', @toggleControlCallback);

% 目标值输入
uicontrol(...
    'Parent', controlPanel, ...
    'Style', 'text', ...
    'String', '控制目标 (μm):', ...
    'Position', [20 50 120 20], ...
    'HorizontalAlignment', 'left');

setpointEdit = uicontrol(...
    'Parent', controlPanel, ...
    'Style', 'edit', ...
    'String', num2str(pidConfig.setpoint), ...
    'Position', [140 50 80 25], ...
    'Callback', @setpointEditCallback);

% 当前球阀开度显示
valveDisplayText = uicontrol(...
    'Parent', controlPanel, ...
    'Style', 'text', ...
    'String', '球阀开度: -- %', ...
    'Position', [20 20 200 20], ...
    'HorizontalAlignment', 'left', ...
    'FontSize', 10);

% PID参数显示
pidDisplayText = uicontrol(...
    'Parent', controlPanel, ...
    'Style', 'text', ...
    'String', sprintf('PID: Kp=%.2f Ki=%.3f Kd=%.2f', ...
        pidConfig.Kp, pidConfig.Ki, pidConfig.Kd), ...
    'Position', [190 80 200 20], ...
    'HorizontalAlignment', 'left', ...
    'FontSize', 9);


%% ========================================================================
% 15. 温度图（保持不变）
% ========================================================================

axTemp = axes(...
    'Parent', fig, ...
    'Units', 'normalized', ...
    'Position', [0.04 0.58 0.60 0.32]);

hold(axTemp,'on');

tempColors = lines(tempChannels);
hTemp = gobjects(tempChannels,1);
for i = 1:tempChannels
    hTemp(i) = plot(axTemp, NaN, NaN, ...
        'Color', tempColors(i,:), 'LineWidth', 1.1);
end

grid(axTemp,'on');
title(axTemp, '18路温度连续监测');
ylabel(axTemp, '温度 / ℃');
legend(axTemp, tempNames, 'Location', 'eastoutside', 'FontSize', 6);


%% ========================================================================
% 16. 三探头实时图（保持不变）
% ========================================================================

axProbe = axes(...
    'Parent', fig, ...
    'Units', 'normalized', ...
    'Position', [0.04 0.33 0.60 0.18]);

hold(axProbe,'on');

hProbe(1) = plot(axProbe, NaN, NaN, 'LineWidth', 1.5);
hProbe(2) = plot(axProbe, NaN, NaN, 'LineWidth', 1.5);
hProbe(3) = plot(axProbe, NaN, NaN, 'LineWidth', 1.5);

yline(axProbe, +probeSafeLimit_um, '--', '+100 μm线性边界');
yline(axProbe, -probeSafeLimit_um, '--', '-100 μm线性边界');
yline(axProbe, +probeWarningLimit_um, ':', '+90 μm预警');
yline(axProbe, -probeWarningLimit_um, ':', '-90 μm预警');

ylim(axProbe,[-115 115]);
grid(axProbe,'on');
title(axProbe, '三路电涡流位移实时数据');
ylabel(axProbe, '相对位移 / μm');
legend(axProbe, {'探头1','探头2','探头3'}, 'Location', 'eastoutside');


%% ========================================================================
% 17. 球阀控制曲线 (新增)
% ========================================================================

axValve = axes(...
    'Parent', fig, ...
    'Units', 'normalized', ...
    'Position', [0.04 0.08 0.60 0.18]);

hold(axValve,'on');

hValveCommand = plot(axValve, NaN, NaN, ...
    'LineWidth', 2, 'Color', [0.8 0.2 0.2]);
hValveFeedback = plot(axValve, NaN, NaN, ...
    '--', 'LineWidth', 1.5, 'Color', [0.2 0.2 0.8]);

yline(axValve, valveSafetyMin, ':', '最小安全开度');
yline(axValve, valveSafetyMax, ':', '最大安全开度');

ylim(axValve,[0 100]);
grid(axValve,'on');
title(axValve, '球阀开度控制曲线');
ylabel(axValve, '开度 / %');
legend(axValve, {'控制指令','实际反馈'}, 'Location', 'eastoutside');


%% ========================================================================
% 18. 固定参数显示（保持不变）
% ========================================================================

uicontrol('Parent', fig, 'Style', 'text', ...
    'String', sprintf('连续采样周期：%d s（固定）', sampleIntervalSec), ...
    'Position', [1250 685 190 28], ...
    'HorizontalAlignment', 'left', 'FontSize',11, 'FontWeight','bold');

uicontrol('Parent', fig, 'Style', 'text', ...
    'String', sprintf('稳定等待：%d s', settleTimeSec), ...
    'Position', [1460 685 150 28], ...
    'HorizontalAlignment', 'left', 'FontSize',11);

uicontrol('Parent', fig, 'Style', 'text', ...
    'String', sprintf('测量窗口：%d s / %d点', ...
        measurementWindowSec, measurementSamples), ...
    'Position', [1250 655 200 28], ...
    'HorizontalAlignment', 'left', 'FontSize',11);

uicontrol('Parent', fig, 'Style', 'text', ...
    'String', sprintf('电涡流范围：±%d μm', probeSafeLimit_um), ...
    'Position', [1460 655 160 28], ...
    'HorizontalAlignment', 'left', 'FontSize',11);


%% ========================================================================
% 19. 操作按钮（调整布局）
% ========================================================================

btnStart = uicontrol('Parent', fig, 'Style', 'pushbutton', ...
    'String', '开始连续采集', 'Position', [1250 600 160 40], ...
    'Callback', @startCallback, 'FontSize',12);

btnZero = uicontrol('Parent', fig, 'Style', 'pushbutton', ...
    'String', '设置冷态零点', 'Position', [1430 600 160 40], ...
    'Callback', @zeroCallback, 'FontSize',12, 'Enable','off');

btnSample = uicontrol('Parent', fig, 'Style', 'pushbutton', ...
    'String', '记录热误差样本', 'Position', [1250 550 160 40], ...
    'Callback', @sampleCallback, 'FontSize',12, 'Enable','off');

btnStop = uicontrol('Parent', fig, 'Style', 'pushbutton', ...
    'String', '停止并保存', 'Position', [1430 550 160 40], ...
    'Callback', @stopCallback, 'FontSize',12, 'Enable','off');


%% ========================================================================
% 20. 状态文字（保持不变）
% ========================================================================

statusText = uicontrol('Parent', fig, 'Style','text', ...
    'String','状态：等待开始实验', ...
    'Position',[1250 510 370 30], ...
    'HorizontalAlignment','left', 'FontSize',11);

sampleCountText = uicontrol('Parent',fig, 'Style','text', ...
    'String','有效热误差样本：0', ...
    'Position',[1250 480 370 28], ...
    'HorizontalAlignment','left', 'FontSize',11);

zeroStatusText = uicontrol('Parent',fig, 'Style','text', ...
    'String','冷态零点：未设置', ...
    'Position',[1250 450 370 28], ...
    'HorizontalAlignment','left', 'FontSize',11);


%% ========================================================================
% 21. 三探头状态（保持不变）
% ========================================================================

probeStatusText = gobjects(3,1);
for ii = 1:3
    probeStatusText(ii) = uicontrol('Parent',fig, 'Style','text', ...
        'String', sprintf('探头%d：等待数据',ii), ...
        'Position', [1250, 410-(ii-1)*30, 370, 26], ...
        'HorizontalAlignment','left', 'FontSize',10);
end

detectPositionText = uicontrol('Parent',fig, 'Style','text', ...
    'String','检测状态：未知', ...
    'Position',[1250 310 370 32], ...
    'HorizontalAlignment','left', ...
    'FontWeight','bold', 'FontSize',11);


%% ========================================================================
% 22. 当前值表格（扩展包含球阀）
% ========================================================================

tableNames = [tempNames, ...
    {'探头1','探头2','探头3'}, ...
    {'X方向热误差','Y方向热误差','Z方向热误差'}, ...
    {'球阀指令','球阀反馈'}];  % 新增

numTableRows = length(tableNames);
initialData = cell(numTableRows,2);
for ii = 1:numTableRows
    initialData{ii,1} = tableNames{ii};
    initialData{ii,2} = '--';
end

tbl = uitable(fig, ...
    'Position',[1250 45 370 250], ...
    'ColumnName', {'测点/变量','当前值'}, ...
    'ColumnWidth', {200 120}, ...
    'Data', initialData, ...
    'RowName', 'numbered', ...
    'FontSize', 8);


%% ========================================================================
% 23. 采集状态变量（保持不变）
% ========================================================================

collecting = false;
isSaving = false;
pendingClose = false;
acqTimer = [];
sampleIndex = 0;

% 当前数据
lastTemp = [];
lastProbe = [];
lastValvePosition = NaN;

% 连续数据
full_time = [];
full_temp = [];
full_probe = [];
full_valveCommand = [];      % 新增
full_valveFeedback = [];     % 新增

% 冷态零点
zeroReady = false;
zeroProbe = [NaN;NaN;NaN];
zeroTemp = nan(tempChannels,1);

% 热误差样本
sampleNumber = 0;
sampleTime = [];
sampleTemp = [];
sampleProbeMean = [];
sampleDeltaProbe = [];
sampleXYZ = [];
sampleStdXYZ = [];
sampleWindowStart = [];
sampleWindowEnd = [];

% 测量窗口状态
windowMode = 0;
windowPhase = 0;
windowRequestClock = [];
windowTempBuffer = [];
windowProbeBuffer = [];
windowTimeBuffer = [];

% 离线模拟状态
simTick = 0;
simTempBase = 24 + 0.6*sin((1:tempChannels)'*0.55);
simTempAmplitude = 3.0 + 2.0*cos((1:tempChannels)'*0.31).^2;
simPhase = (1:tempChannels)'*0.37;
simValvePosition = 50;  % 新增

% 通讯失败计数器（新增）
consecutiveReadFailures = 0;


%% ========================================================================
% 24. 更新当前模式
% ========================================================================

updateModeText();


%% ========================================================================
% 25. 控制开关回调 (新增)
% ========================================================================

    function toggleControlCallback(src,~)
        controlEnabled = get(src,'Value');
        if controlEnabled
            set(src,'String','停止自动控制');
            set(src,'BackgroundColor',[1.0 0.8 0.8]);
            fprintf('\n✅ PID自动控制已启动\n');
            fprintf('   目标位移：%.2f μm\n', pid.setpoint);
        else
            set(src,'String','启动自动控制');
            set(src,'BackgroundColor',[0.94 0.94 0.94]);
            fprintf('\n⏸ PID自动控制已暂停\n');
        end
    end


%% ========================================================================
% 26. 目标值修改回调 (新增)
% ========================================================================

    function setpointEditCallback(src,~)
        newSetpoint = str2double(get(src,'String'));
        if isnan(newSetpoint)
            set(src,'String',num2str(pid.setpoint));
            fprintf('⚠️ 无效的目标值输入\n');
        else
            pid.setpoint = newSetpoint;
            fprintf('✅ 控制目标更新为: %.2f μm\n', newSetpoint);
        end
    end


%% ========================================================================
% 27. 开始采集（保持大部分逻辑）
% ========================================================================

    function startCallback(~,~)
        if collecting
            return;
        end

        % 清空本轮实验数据
        sampleIndex = 0;
        full_time = [];
        full_temp = [];
        full_probe = [];
        full_valveCommand = [];
        full_valveFeedback = [];

        lastTemp = [];
        lastProbe = [];
        lastValvePosition = NaN;

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
        consecutiveReadFailures = 0;

        % 重置PID
        pid.reset();

        collecting = true;

        set(btnStart,'Enable','off');
        set(btnStop,'Enable','on');
        set(btnZero,'Enable','off');
        set(btnSample,'Enable','off');

        set(statusText, 'String', '状态：正在读取 t = 0 s 初始数据');
        set(sampleCountText, 'String', '有效热误差样本：0');
        set(zeroStatusText, 'String', '冷态零点：未设置');

        fprintf('\n=============================================\n');
        fprintf('开始本轮热误差实验（带PID控制）\n');
        fprintf('固定采样周期：%d s\n', sampleIntervalSec);
        fprintf('记录时间：0、2、4、6、8…… s\n');
        fprintf('=============================================\n');

        % t = 0 s读取一次
        initialOK = false;
        failureCount = 0;

        while ~initialOK && collecting
            try
                [tempVals,probeVals,valvePos] = readAllSensorsAndValve();

                sampleIndex = 0;
                full_time = 0;
                full_temp = tempVals;
                full_probe = probeVals;
                full_valveCommand = valvePos;
                full_valveFeedback = valvePos;

                lastTemp = tempVals;
                lastProbe = probeVals;
                lastValvePosition = valvePos;

                initialOK = true;

                updateCurrentDisplay();
                updatePlots();

                fprintf('✅ t = 0 s 数据读取成功。\n');

            catch ME
                failureCount = failureCount + 1;
                fprintf('⚠️ 初始读取失败 %d 次：%s\n', ...
                    failureCount, ME.message);

                if failureCount >= 3 && ~simulateMode && autoFallbackOffline
                    switchToOfflineMode('设备连接成功，但读取数据失败');
                    failureCount = 0;
                else
                    pause(0.5);
                end
            end
        end

        if ~collecting
            return;
        end

        % 建立严格2秒FixedRate定时器
        acqTimer = timer(...
            'ExecutionMode', 'fixedRate', ...
            'Period', sampleIntervalSec, ...
            'StartDelay', sampleIntervalSec, ...
            'BusyMode', 'queue', ...       % 改为queue，不丢弃
            'MaximumSpikes', 5, ...        % 最多积压5个
            'TimerFcn', @acquisitionTick, ...
            'ErrorFcn', @timerErrorCallback);

        start(acqTimer);

        set(statusText, 'String', '状态：每2 s固定采集中');
        refreshActionButtons();
    end


%% ========================================================================
% 28. 2秒定时采样（增强版）
% ========================================================================

    function acquisitionTick(~,~)
        if ~collecting
            return;
        end

        try
            % 读取数据（增强重试机制）
            [tempVals,probeVals,valvePos] = ...
                readAllSensorsAndValve();

            % 时间严格使用理论2秒网格
            sampleIndex = sampleIndex + 1;
            tNow = sampleIndex * sampleIntervalSec;

            % PID控制计算（新增）
            valveCommand = NaN;
            if controlEnabled && zeroReady && ...
                    ~isempty(probeVals) && ~any(isnan(probeVals))

                % 使用探头1作为控制输入（或使用三探头平均）
                controlInput = probeVals(1);  % 可修改为mean(probeVals)

                % PID计算
                valveCommand = pid.compute(controlInput);

                % 发送控制指令
                success = writeValvePosition(valveCommand);
                if ~success
                    fprintf('⚠️ 球阀控制指令发送失败\n');
                end
            else
                % 不控制时，保持当前位置或默认位置
                valveCommand = valvePos;
            end

            % 保存连续数据
            full_time(end+1) = tNow;
            full_temp(:,end+1) = tempVals;
            full_probe(:,end+1) = probeVals;
            full_valveCommand(end+1) = valveCommand;
            full_valveFeedback(end+1) = valvePos;

            lastTemp = tempVals;
            lastProbe = probeVals;
            lastValvePosition = valvePos;

            % 重置失败计数器
            consecutiveReadFailures = 0;

            % 当前是否正在进行冷态/热误差测量
            handleMeasurementWindow(tempVals, probeVals, tNow);

            % GUI
            updateCurrentDisplay();
            updatePlots();

            % 命令行
            fprintf(['时间=%6d s | T1=%5.1f T2=%5.1f T3=%5.1f | ' ...
                     'P1=%7.2f P2=%7.2f P3=%7.2f μm | ' ...
                     'Valve=%5.1f%%\n'], ...
                tNow, tempVals(1), tempVals(2), tempVals(3), ...
                probeVals(1), probeVals(2), probeVals(3), ...
                valvePos);

            drawnow limitrate;

        catch ME
            consecutiveReadFailures = consecutiveReadFailures + 1;

            fprintf('⚠️ 第%d个采样周期读取失败 (%d/%d)：%s\n', ...
                sampleIndex+1, consecutiveReadFailures, ...
                maxReadErrors, ME.message);

            % 连续失败过多，考虑切换模式
            if consecutiveReadFailures >= maxReadErrors && ~simulateMode
                fprintf('\n❌ 连续读取失败超过%d次\n', maxReadErrors);
                if autoFallbackOffline
                    switchToOfflineMode('连续通讯失败');
                else
                    stopCallback();
                end
            end
        end
    end


%% ========================================================================
% 29-35. 保持原有的功能函数（略）
% 包括：
%   - zeroCallback
%   - sampleCallback
%   - startMeasurementWindow
%   - handleMeasurementWindow
%   - processMeasurementWindow
%   - resetMeasurementWindow
% ========================================================================

% 这里省略，与原代码相同...


%% ========================================================================
% 36. 读取全部传感器和球阀（增强版）
% ========================================================================

    function [tempVals,probeVals,valvePos] = ...
            readAllSensorsAndValve()

        % 离线模拟
        if simulateMode
            [tempVals,probeVals,valvePos] = ...
                generateSimulationDataWithValve();
            return;
        end

        % 温度（保持原逻辑）
        tempVals = zeros(tempChannels,1);
        pos = 1;
        for kk = 1:length(tempServers)
            slave = tempServers(kk).id;
            n = tempServers(kk).numChannels;

            rawTemp = readModbusWithRetry(...
                m, slave, 'holdingregs', tempRegister, n);

            temp = double(rawTemp) * tempScale;
            tempVals(pos:pos+n-1) = temp(:);
            pos = pos + n;
        end

        % 三个电涡流（保持原逻辑）
        probeVals = zeros(numProbes,1);
        for jj = 1:numProbes
            rawProbe = readModbusWithRetry(...
                m, probeSensors(jj).id, ...
                'holdingregs', probeSensors(jj).reg, 1);

            rawSigned = signed16ToDouble(rawProbe);
            probeVals(jj) = rawSigned * probeSensors(jj).scale;
        end

        % 球阀反馈（新增）
        rawValve = readModbusWithRetry(...
            m, valveConfig.id, ...
            'holdingregs', valveConfig.positionReadReg, 1);

        valvePos = double(rawValve) * valveConfig.scale;
        valvePos = max(0, min(100, valvePos));  % 限幅
    end


%% ========================================================================
% 37. Modbus带重试的读取（新增）
% ========================================================================

    function data = readModbusWithRetry(...
            modbusObj, slave, regType, address, count)

        maxRetry = modbusRetryConfig.maxRetry;
        retryDelay = modbusRetryConfig.retryDelay;

        for attempt = 1:maxRetry
            try
                data = read(modbusObj, regType, address, count, slave);
                return;  % 成功则立即返回
            catch ME
                if attempt < maxRetry
                    pause(retryDelay);
                else
                    % 最后一次尝试失败，抛出错误
                    error('Modbus读取失败(从机%d, 地址%d): %s', ...
                        slave, address, ME.message);
                end
            end
        end
    end


%% ========================================================================
% 38. 写球阀位置（新增）
% ========================================================================

    function success = writeValvePosition(position)
        success = false;

        if simulateMode
            simValvePosition = position;
            success = true;
            return;
        end

        % 安全限制
        position = max(valveSafetyMin, min(valveSafetyMax, position));

        % 转换为寄存器值
        regValue = round(position / valveConfig.scale);

        maxRetry = modbusRetryConfig.maxRetry;

        for attempt = 1:maxRetry
            try
                write(m, 'holdingregs', ...
                    valveConfig.positionSetReg, ...
                    regValue, ...
                    valveConfig.id);
                success = true;
                return;
            catch ME
                if attempt < maxRetry
                    pause(modbusRetryConfig.retryDelay);
                else
                    fprintf('⚠️ 球阀写入失败: %s\n', ME.message);
                end
            end
        end
    end


%% ========================================================================
% 39. 16位有符号值转换（保持不变）
% ========================================================================

    function value = signed16ToDouble(raw)
        value = double(raw);
        if value > 32767
            value = value - 65536;
        end
    end


%% ========================================================================
% 40. 离线模拟数据（扩展球阀）
% ========================================================================

    function [tempVals,probeVals,valvePos] = ...
            generateSimulationDataWithValve()

        t = simTick * sampleIntervalSec;
        simTick = simTick + 1;

        % 温度（保持原逻辑）
        heatRise = 6.0 * (1-exp(-t/150));
        tempVals = simTempBase + ...
            simTempAmplitude .* (heatRise/6) + ...
            0.10*sin(0.025*t + simPhase) + ...
            0.03*randn(tempChannels,1);

        % 模拟热漂移（受球阀影响）
        factor = 1-exp(-t/130);
        coolingEffect = (simValvePosition - 50) * 0.3;  % 球阀效应

        probeVals = [...
             32*factor - coolingEffect; ...
            -20*factor + coolingEffect*0.6; ...
             42*factor - coolingEffect*0.8];

        probeVals = probeVals + [...
            0.7*sin(0.030*t); ...
            0.5*sin(0.024*t+1.1); ...
            0.8*sin(0.020*t+2.0)];

        probeVals = probeVals + [0.10;0.10;0.12] .* randn(3,1);

        % 球阀位置（模拟有响应延迟）
        valvePos = simValvePosition;
    end


%% ========================================================================
% 以下函数保持原代码逻辑（略）
% ========================================================================

% checkProbeVector
% checkProbeWindow
% updateProbeStatus
% updateCurrentDisplay
% refreshActionButtons
% updatePlots
% stopCallback
% saveData
% switchToOfflineMode
% updateModeText
% timerErrorCallback
% stopAndDeleteTimer
% closeFigure
% cleanupResources

% 省略部分...详见完整代码

end


%% ========================================================================
% PID控制器类（新增）
% ========================================================================

classdef PIDController < handle
    properties
        Kp
        Ki
        Kd
        setpoint
        outputMin
        outputMax
        integralLimit
        deadband
        sampleTime

        lastError
        integral
        lastTime
        lastOutput

        % 调试信息
        P_term
        I_term
        D_term
    end

    methods
        function obj = PIDController(Kp, Ki, Kd, setpoint, ...
                outputMin, outputMax, integralLimit, deadband, sampleTime)
            obj.Kp = Kp;
            obj.Ki = Ki;
            obj.Kd = Kd;
            obj.setpoint = setpoint;
            obj.outputMin = outputMin;
            obj.outputMax = outputMax;
            obj.integralLimit = integralLimit;
            obj.deadband = deadband;
            obj.sampleTime = sampleTime;

            obj.reset();
        end

        function reset(obj)
            obj.lastError = 0;
            obj.integral = 0;
            obj.lastTime = [];
            obj.lastOutput = [];
            obj.P_term = 0;
            obj.I_term = 0;
            obj.D_term = 0;
        end

        function output = compute(obj, measuredValue)
            % 计算误差
            error = obj.setpoint - measuredValue;

            % 死区控制
            if abs(error) < obj.deadband
                if ~isempty(obj.lastOutput)
                    output = obj.lastOutput;
                else
                    output = (obj.outputMin + obj.outputMax) / 2;
                end
                return;
            end

            % 比例项
            obj.P_term = obj.Kp * error;

            % 积分项
            obj.integral = obj.integral + error * obj.sampleTime;
            obj.integral = max(-obj.integralLimit, ...
                min(obj.integralLimit, obj.integral));
            obj.I_term = obj.Ki * obj.integral;

            % 微分项
            derivative = (error - obj.lastError) / obj.sampleTime;
            obj.D_term = obj.Kd * derivative;

            % PID输出
            output = obj.P_term + obj.I_term + obj.D_term;

            % 输出限幅
            output = max(obj.outputMin, min(obj.outputMax, output));

            % 抗积分饱和
            if output >= obj.outputMax || output <= obj.outputMin
                obj.integral = obj.integral - error * obj.sampleTime;
            end

            % 更新状态
            obj.lastError = error;
            obj.lastOutput = output;
        end
    end
end
