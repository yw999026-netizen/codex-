function mpc_Control_GUI_WC_Temp_Final()
% 2026-10-16：历史温控算法模拟演示；真实设备入口已禁用。
% 开度u为未核实历史数值单位，不能解释为百分比或角度。
addpath(fileparts(fileparts(fileparts(mfilename('fullpath')))));
% =====================================================================
% 五轴机床 MIMO-MPC 智能全解耦控制平台 - 水冷温度扩展完整版本
% 核心特性：三段全景监测 UI、零崩溃容错机制、辅机启停状态监控
% 新增内容：3路水冷机水箱温度采集、界面显示、Excel输出
% =====================================================================

%% ------------------- [1. 主窗口设计] -------------------
hFig = figure('Name', '历史模拟 · MIMO-MPC 五轴机床智能热控制平台', ...
'Position', [100, 50, 1350, 750], ...
'MenuBar', 'none', 'ToolBar', 'none', ...
'Color', [0.92 0.94 0.96], ...
'CloseRequestFcn', @closeApp);

handles = guihandles(hFig);
handles.isRunning = false;
handles.sim_timer = [];
handles.mpcobj = [];
handles.xc = [];

handles.time_log = [];
handles.temp5_log = [];
handles.wc3_log = [];
handles.wc_temp_log = [];
handles.valve6_log = [];
handles.sim_T_curr = [31.5; 29.0; 28.2; 26.5; 24.0];
handles.sim_last_u = zeros(6, 1);

%% ------------------- [2. 左侧：通讯与参数配置区] -------------------
hSysPanel = uipanel(hFig, 'Title', '⚙️ 系统与算法配置', 'FontSize', 12, 'FontWeight', 'bold', ...
'BackgroundColor', 'white', 'Position', [0.01, 0.70, 0.32, 0.28]);

uicontrol(hSysPanel, 'Style', 'text', 'String', '温度COM:', 'BackgroundColor', 'white', 'Units', 'normalized', 'Position', [0.01, 0.65, 0.18, 0.20], 'FontSize', 10, 'HorizontalAlignment', 'right');
handles.editCOM_Temp = uicontrol(hSysPanel, 'Style', 'edit', 'String', 'COM4', 'Units', 'normalized', 'Position', [0.20, 0.67, 0.12, 0.20], 'FontSize', 10);

uicontrol(hSysPanel, 'Style', 'text', 'String', '阀门COM:', 'BackgroundColor', 'white', 'Units', 'normalized', 'Position', [0.34, 0.65, 0.18, 0.20], 'FontSize', 10, 'HorizontalAlignment', 'right');
handles.editCOM_Valve = uicontrol(hSysPanel, 'Style', 'edit', 'String', 'COM5', 'Units', 'normalized', 'Position', [0.53, 0.67, 0.12, 0.20], 'FontSize', 10);

uicontrol(hSysPanel, 'Style', 'text', 'String', '水冷机COM:', 'BackgroundColor', 'white', 'Units', 'normalized', 'Position', [0.67, 0.65, 0.18, 0.20], 'FontSize', 10, 'HorizontalAlignment', 'right');
handles.editCOM_WC = uicontrol(hSysPanel, 'Style', 'edit', 'String', 'COM6', 'Units', 'normalized', 'Position', [0.86, 0.67, 0.12, 0.20], 'FontSize', 10);

uicontrol(hSysPanel, 'Style', 'text', 'String', '预测步数 P:', 'BackgroundColor', 'white', 'Units', 'normalized', 'Position', [0.05, 0.35, 0.25, 0.20], 'FontSize', 10, 'HorizontalAlignment', 'right');
handles.edit_P = uicontrol(hSysPanel, 'Style', 'edit', 'String', '60', 'Units', 'normalized', 'Position', [0.32, 0.37, 0.15, 0.20], 'FontSize', 10);

uicontrol(hSysPanel, 'Style', 'text', 'String', '控制步数 M:', 'BackgroundColor', 'white', 'Units', 'normalized', 'Position', [0.52, 0.35, 0.25, 0.20], 'FontSize', 10, 'HorizontalAlignment', 'right');
handles.edit_M = uicontrol(hSysPanel, 'Style', 'edit', 'String', '3', 'Units', 'normalized', 'Position', [0.79, 0.37, 0.15, 0.20], 'FontSize', 10);

handles.chk_SimMode = uicontrol(hSysPanel, 'Style', 'checkbox', 'String', '开启离线仿真测试 (无实机时务必勾选)', 'BackgroundColor', 'white', 'ForegroundColor', 'red', 'Units', 'normalized', 'Position', [0.05, 0.08, 0.90, 0.20], 'Value', 1);

%% ------------------- [3. 中间：控制发令区] -------------------
hControlPanel = uipanel(hFig, 'Title', '🧠 核心控制单元', 'FontSize', 12, 'FontWeight', 'bold', ...
'BackgroundColor', 'white', 'Position', [0.34, 0.70, 0.22, 0.28]);

handles.startBtn = uicontrol(hControlPanel, 'Style', 'pushbutton', 'String', '▶ 启动闭环控制', 'FontSize', 11, 'FontWeight', 'bold', 'Units', 'normalized', 'Position', [0.1, 0.55, 0.8, 0.35], 'BackgroundColor', [0.2 0.8 0.2], 'ForegroundColor', 'white', 'Callback', @startSystem);
handles.stopBtn = uicontrol(hControlPanel, 'Style', 'pushbutton', 'String', '⏹ 停止并保存数据', 'FontSize', 11, 'FontWeight', 'bold', 'Units', 'normalized', 'Position', [0.1, 0.10, 0.8, 0.35], 'BackgroundColor', [0.9 0.3 0.3], 'ForegroundColor', 'white', 'Callback', @stopSystem);

%% ------------------- [4. 右侧：全景数据看板] -------------------
hMonitorPanel = uipanel(hFig, 'Title', '📈 实时数据监控矩阵', 'FontSize', 12, 'FontWeight', 'bold', ...
'BackgroundColor', 'white', 'Position', [0.57, 0.70, 0.42, 0.28]);

handles.txt_TempInfo = uicontrol(hMonitorPanel, 'Style', 'text', 'String', sprintf('机床温度 (℃):\nT1(床身): -- \nT2(柱左): -- \nT3(柱右): -- \nT4(梁上): -- \nT5(环境): -- '), ...
'BackgroundColor', 'white', 'ForegroundColor', [0.7 0.1 0.1], 'FontSize', 10, 'FontWeight', 'bold', 'Units', 'normalized', 'Position', [0.02, 0.05, 0.32, 0.9], 'HorizontalAlignment', 'left');

handles.txt_WCInfo = uicontrol(hMonitorPanel, 'Style', 'text', 'String', sprintf('水冷状态/温度:\nWC1(床身): -- | --.-℃\nWC2(立柱): -- | --.-℃\nWC3(横梁): -- | --.-℃\n'), ...
'BackgroundColor', 'white', 'ForegroundColor', [0.1 0.6 0.1], 'FontSize', 10, 'FontWeight', 'bold', 'Units', 'normalized', 'Position', [0.36, 0.05, 0.30, 0.9], 'HorizontalAlignment', 'left');

handles.txt_ValveInfo = uicontrol(hMonitorPanel, 'Style', 'text', 'String', sprintf('历史模拟指令u（单位未核实）:\nV1(床左): -- V2(床右): -- \nV4(柱左): -- V5(柱右): -- \nV7(梁上): -- V8(梁下): -- '), ...
'BackgroundColor', 'white', 'ForegroundColor', [0.1 0.4 0.8], 'FontSize', 10, 'FontWeight', 'bold', 'Units', 'normalized', 'Position', [0.68, 0.05, 0.30, 0.9], 'HorizontalAlignment', 'left');

%% ------------------- [5. 下方：三段式绘图区] -------------------
handles.axTemp = axes('Parent', hFig, 'Position', [0.05, 0.49, 0.92, 0.19]);
ylabel('温度(℃)', 'FontWeight', 'bold'); grid(handles.axTemp, 'on'); hold(handles.axTemp, 'on');
set(handles.axTemp, 'Color', [0.98 0.98 0.98]);
handles.lineT1 = plot(handles.axTemp, NaN, NaN, '-', 'Color', [0.8 0.1 0.1], 'LineWidth', 2.5);
handles.lineT2 = plot(handles.axTemp, NaN, NaN, '-', 'Color', [0.1 0.6 0.1], 'LineWidth', 2.5);
handles.lineT3 = plot(handles.axTemp, NaN, NaN, '--', 'Color', [0.1 0.8 0.3], 'LineWidth', 2);
handles.lineT4 = plot(handles.axTemp, NaN, NaN, '-', 'Color', [0.1 0.1 0.8], 'LineWidth', 2.5);
handles.lineT5 = plot(handles.axTemp, NaN, NaN, '-', 'Color', [0.4 0.4 0.4], 'LineWidth', 2);
legend(handles.axTemp, 'T1(床身)', 'T2(柱左)', 'T3(柱右)', 'T4(梁上)', 'T5(环境)', 'Location', 'northwest', 'Orientation', 'horizontal');

handles.axWC = axes('Parent', hFig, 'Position', [0.05, 0.33, 0.92, 0.11]);
ylabel('水冷状态', 'FontWeight', 'bold'); grid(handles.axWC, 'on'); hold(handles.axWC, 'on');
ylim(handles.axWC, [-0.2 1.2]); yticks(handles.axWC, [0 1]);
set(handles.axWC, 'Color', [0.98 0.98 0.98]);
handles.lineWC1 = plot(handles.axWC, NaN, NaN, '-', 'Color', [0.8 0.1 0.1], 'LineWidth', 2);
handles.lineWC2 = plot(handles.axWC, NaN, NaN, '-', 'Color', [0.1 0.6 0.1], 'LineWidth', 2);
handles.lineWC3 = plot(handles.axWC, NaN, NaN, '-', 'Color', [0.1 0.1 0.8], 'LineWidth', 2);
legend(handles.axWC, 'WC1(床身)', 'WC2(立柱)', 'WC3(横梁)', 'Location', 'northwest', 'Orientation', 'horizontal');

handles.axValve = axes('Parent', hFig, 'Position', [0.05, 0.06, 0.92, 0.22]);
xlabel('运行时间 (秒)', 'FontWeight', 'bold'); ylabel('阀门指令u（单位未核实）', 'FontWeight', 'bold');
grid(handles.axValve, 'on'); hold(handles.axValve, 'on'); ylim(handles.axValve, [-5 95]);
set(handles.axValve, 'Color', [0.98 0.98 0.98]);
handles.lineV1 = plot(handles.axValve, NaN, NaN, '-', 'Color', [0.8 0.1 0.1], 'LineWidth', 2);
handles.lineV2 = plot(handles.axValve, NaN, NaN, '--', 'Color', [0.8 0.4 0.4], 'LineWidth', 2);
handles.lineV4 = plot(handles.axValve, NaN, NaN, '-', 'Color', [0.1 0.6 0.1], 'LineWidth', 2);
handles.lineV5 = plot(handles.axValve, NaN, NaN, '--', 'Color', [0.1 0.8 0.3], 'LineWidth', 2);
handles.lineV7 = plot(handles.axValve, NaN, NaN, '-', 'Color', [0.1 0.1 0.8], 'LineWidth', 2);
handles.lineV8 = plot(handles.axValve, NaN, NaN, '--', 'Color', [0.4 0.4 0.8], 'LineWidth', 2);
legend(handles.axValve, 'V1(床左)', 'V2(床右)', 'V4(柱左)', 'V5(柱右)', 'V7(梁上)', 'V8(梁下)', 'Location', 'northwest', 'Orientation', 'horizontal');

guidata(hFig, handles);

%% ===================== [启动程序] =====================
function startSystem(hObj, ~)
handles = guidata(hObj);
if handles.isRunning; return; end

isSimMode = get(handles.chk_SimMode, 'Value');
try
    labshared.requireSimulation(isSimMode);
catch err
    errordlg(err.message,'真实模式未启用'); return;
end
handles.executionMode='simulation'; handles.wallClock=tic;
set(handles.chk_SimMode,'Enable','off');
P = str2double(get(handles.edit_P, 'String'));
M = str2double(get(handles.edit_M, 'String'));
Ts = 1;

handles.time_log = [];
handles.temp5_log = [];
handles.wc3_log = [];
handles.wc_temp_log = [];
handles.valve6_log = [];
handles.sim_T_curr = [23.5; 22.0; 21.2; 20.5; 19.0];
handles.sim_last_u = zeros(6, 1);

if isnan(P) || isnan(M)
    errordlg('参数格式错误！请输入整数。', '配置异常');
    return;
end

try
    A = eye(5) * 0.95;
    B = [-0.05, -0.12, 0, 0, 0, 0; ...
          0, 0, -0.12, -0.02, 0, 0; ...
          0, 0, -0.02, -0.12, 0, 0; ...
          0, 0, 0, 0, -0.10, -0.08; ...
          0, 0, 0, 0, 0, 0];
    sys = ss(A, B, eye(5), zeros(5,6), Ts);
    handles.mpcobj = mpc(sys, Ts);
    handles.mpcobj.PredictionHorizon = P;
    handles.mpcobj.ControlHorizon = M;
    for i = 1:6
        handles.mpcobj.MV(i).Min = 0; handles.mpcobj.MV(i).Max = 90;
        handles.mpcobj.MV(i).RateMin = -15; handles.mpcobj.MV(i).RateMax = 15;
    end
    handles.mpcobj.Weights.OV = [10, 10, 10, 10, 0];
    handles.xc = mpcstate(handles.mpcobj);
catch ME
    errordlg(['核心矩阵构建失败：', ME.message], '严重故障');
    return;
end

if ~isSimMode
    try
        handles.temp_modbus = modbus('serialrtu', get(handles.editCOM_Temp, 'String'), 'BaudRate', 19200, 'DataBits', 8, 'StopBits', 1, 'Parity', 'none');
        handles.valve_modbus = modbus('serialrtu', get(handles.editCOM_Valve, 'String'), 'BaudRate', 9600, 'DataBits', 8, 'StopBits', 1, 'Parity', 'none');
        handles.wc_modbus = modbus('serialrtu', get(handles.editCOM_WC, 'String'), 'BaudRate', 9600, 'DataBits', 8, 'StopBits', 1, 'Parity', 'none');
    catch ME
        errordlg(['串口占线或断开，请检查物理连线: ' ME.message], '硬件异常');
        return;
    end
end

handles.dataFile = ['Exp_MPC_Data_' datestr(now, 'mmdd_HHMM') '.xlsx'];
header = {'Time(s)', 'T1_Bed', 'T2_Col_L', 'T3_Col_R', 'T4_Beam', 'T5_Env', ...
          'WC1_Temp', 'WC2_Temp', 'WC3_Temp', ...
          'WC1', 'WC2', 'WC3', ...
          'V1_u', 'V2_u', 'V4_u', 'V5_u', 'V7_u', 'V8_u', ...
                  'UTC','Mode','Quality','WriteStatus','CommandUnit','V1_requested','V2_requested','V4_requested','V5_requested','V7_requested','V8_requested', ...
                  'V1_register_legacy','V2_register_legacy','V4_register_legacy','V5_register_legacy','V7_register_legacy','V8_register_legacy'};
try writecell(header, handles.dataFile); catch, end

set(handles.lineT1, 'XData', [], 'YData', []); set(handles.lineT2, 'XData', [], 'YData', []);
set(handles.lineT3, 'XData', [], 'YData', []); set(handles.lineT4, 'XData', [], 'YData', []); set(handles.lineT5, 'XData', [], 'YData', []);
set(handles.lineWC1, 'XData', [], 'YData', []); set(handles.lineWC2, 'XData', [], 'YData', []); set(handles.lineWC3, 'XData', [], 'YData', []);
set(handles.lineV1, 'XData', [], 'YData', []); set(handles.lineV2, 'XData', [], 'YData', []);
set(handles.lineV4, 'XData', [], 'YData', []); set(handles.lineV5, 'XData', [], 'YData', []);
set(handles.lineV7, 'XData', [], 'YData', []); set(handles.lineV8, 'XData', [], 'YData', []);

handles.isRunning = true;
guidata(hObj, handles);
handles.sim_timer = timer('ExecutionMode', 'fixedRate', 'Period', 1, 'TimerFcn', {@mainLoop, hFig});
start(handles.sim_timer);
end

%% ===================== [循环执行] =====================
function mainLoop(~, ~, hFig)
try
if ~ishandle(hFig); return; end
handles = guidata(hFig);
if ~handles.isRunning; return; end

isSimMode = strcmp(handles.executionMode,'simulation');

T_curr = zeros(5,1);
if isSimMode
    u = handles.sim_last_u;
    T_sim = handles.sim_T_curr;
    T_sim(1) = T_sim(1) + 0.05*(25.5 - T_sim(1)) - 0.005*u(1) - 0.012*u(2) + 0.01*randn;
    T_sim(2) = T_sim(2) + 0.05*(24.0 - T_sim(2)) - 0.012*u(3) - 0.002*u(4) + 0.01*randn;
    T_sim(3) = T_sim(3) + 0.05*(24.2 - T_sim(3)) - 0.002*u(3) - 0.012*u(4) + 0.01*randn;
    T_sim(4) = T_sim(4) + 0.05*(22.5 - T_sim(4)) - 0.010*u(5) - 0.008*u(6) + 0.01*randn;
    T_sim(5) = T_sim(5) + 0.005*randn;
    T_curr = T_sim;
    handles.sim_T_curr = T_sim;
else
    try
        for i = 1:5
            T_curr(i) = read(handles.temp_modbus, 'holdingregs', 1536 + i, 1) / 10;
        end
    catch
        if ~isempty(handles.temp5_log)
            T_curr = NaN(5,1); error('lab:ReadFailure','Temperature unavailable; no stale substitution');
        else
            T_curr = NaN(5,1); error('lab:ReadFailure','Temperature unavailable; no default substitution');
        end
    end
end

wc1 = double(T_curr(1) > 20);
wc2 = double(T_curr(2) > 20 || T_curr(3) > 20);
wc3 = double(T_curr(4) > 20);
if T_curr(1) <= 19.5; wc1 = 0; end
if T_curr(2) <= 19.5 && T_curr(3) <= 19.5; wc2 = 0; end
if T_curr(4) <= 19.5; wc3 = 0; end
wc_state = [wc1; wc2; wc3];

if ~isSimMode
    try
        write(handles.wc_modbus, 'holdingregs', 1, wc1);
        write(handles.wc_modbus, 'holdingregs', 2, wc2);
        write(handles.wc_modbus, 'holdingregs', 3, wc3);
    catch
    end
end

T_wc = NaN(3,1);
if ~isSimMode
    try
        T_wc(1) = read(handles.wc_modbus, 'holdingregs', 101, 1) / 10;
        T_wc(2) = read(handles.wc_modbus, 'holdingregs', 102, 1) / 10;
        T_wc(3) = read(handles.wc_modbus, 'holdingregs', 103, 1) / 10;
    catch
        if ~isempty(handles.wc_temp_log)
            T_wc = NaN(3,1); error('lab:ReadFailure','Water temperature unavailable');
        end
    end
else
    T_wc = [15.7; 15.7; 15.7] + 0.1 * randn(3,1);
end

T_target = [20; 20; 20; 20; 20];
u_cmd = mpcmove(handles.mpcobj, handles.xc, T_curr, T_target);
u_requested=u_cmd; [u_cmd,register_values]=labshared.legacyValveCommand(u_requested);
handles.sim_last_u = u_cmd;

if ~isSimMode
    slave_ids = [1, 2, 4, 5, 7, 8];
    for k = 1:6
        try
            write(handles.valve_modbus, 'holdingregs', 2, round(u_cmd(k) * 100), slave_ids(k));
        catch
        end
        pause(0.05);
    end
end

str_t = sprintf('机床温度 (℃):\nT1(床身): %.1f\nT2(柱左): %.1f\nT3(柱右): %.1f\nT4(梁上): %.1f\nT5(环境): %.1f', T_curr(1), T_curr(2), T_curr(3), T_curr(4), T_curr(5));
str_wc = sprintf('水冷状态/温度:\nWC1(床身): %d | %.1f℃\nWC2(立柱): %d | %.1f℃\nWC3(横梁): %d | %.1f℃', wc1, T_wc(1), wc2, T_wc(2), wc3, T_wc(3));
str_v = sprintf('历史模拟指令u（单位未核实）:\nV1(床左): %02.0f V2(床右): %02.0f\nV4(柱左): %02.0f V5(柱右): %02.0f\nV7(梁上): %02.0f V8(梁下): %02.0f', u_cmd(1), u_cmd(2), u_cmd(3), u_cmd(4), u_cmd(5), u_cmd(6));
set(handles.txt_TempInfo, 'String', str_t);
set(handles.txt_WCInfo, 'String', str_wc);
set(handles.txt_ValveInfo, 'String', str_v);

t_now = toc(handles.wallClock);
handles.time_log = [handles.time_log, t_now];
handles.temp5_log = [handles.temp5_log, T_curr];
handles.wc3_log = [handles.wc3_log, wc_state];
handles.wc_temp_log = [handles.wc_temp_log, T_wc];
handles.valve6_log = [handles.valve6_log, u_cmd];

row_data = round([t_now, T_curr', T_wc', wc_state', u_cmd'], 2);
try writecell([num2cell(row_data),{labshared.utcNow(),'simulation','SYNTHETIC_DATA','SIMULATED_COMMAND_NOT_SENT','legacy_u_unverified'},num2cell(u_requested'),num2cell(register_values')], handles.dataFile, 'WriteMode', 'append'); catch, end

set(handles.lineT1, 'XData', handles.time_log, 'YData', handles.temp5_log(1,:));
set(handles.lineT2, 'XData', handles.time_log, 'YData', handles.temp5_log(2,:));
set(handles.lineT3, 'XData', handles.time_log, 'YData', handles.temp5_log(3,:));
set(handles.lineT4, 'XData', handles.time_log, 'YData', handles.temp5_log(4,:));
set(handles.lineT5, 'XData', handles.time_log, 'YData', handles.temp5_log(5,:));
set(handles.lineWC1, 'XData', handles.time_log, 'YData', handles.wc3_log(1,:) * 1.02);
set(handles.lineWC2, 'XData', handles.time_log, 'YData', handles.wc3_log(2,:) * 1.00);
set(handles.lineWC3, 'XData', handles.time_log, 'YData', handles.wc3_log(3,:) * 0.98);
set(handles.lineV1, 'XData', handles.time_log, 'YData', handles.valve6_log(1,:));
set(handles.lineV2, 'XData', handles.time_log, 'YData', handles.valve6_log(2,:));
set(handles.lineV4, 'XData', handles.time_log, 'YData', handles.valve6_log(3,:));
set(handles.lineV5, 'XData', handles.time_log, 'YData', handles.valve6_log(4,:));
set(handles.lineV7, 'XData', handles.time_log, 'YData', handles.valve6_log(5,:));
set(handles.lineV8, 'XData', handles.time_log, 'YData', handles.valve6_log(6,:));

if t_now > 150
    xlim(handles.axTemp, [t_now-150 t_now+10]);
    xlim(handles.axWC, [t_now-150 t_now+10]);
    xlim(handles.axValve, [t_now-150 t_now+10]);
else
    xlim(handles.axTemp, [0 160]);
    xlim(handles.axWC, [0 160]);
    xlim(handles.axValve, [0 160]);
end

guidata(hFig, handles); drawnow;

catch
try handles = guidata(hFig); if handles.isRunning; stopSystem(handles.stopBtn, []); end; catch, end
end
end

%% ===================== [收尾指令] =====================
function stopSystem(hObj, ~)
try
handles = guidata(hObj);
handles.isRunning = false;
            set(handles.chk_SimMode,'Enable','on');
if ~isempty(handles.sim_timer); stop(handles.sim_timer); delete(handles.sim_timer); handles.sim_timer = []; end

try write(handles.wc_modbus, 'holdingregs', 1, 0); catch, end
try write(handles.wc_modbus, 'holdingregs', 2, 0); catch, end
try write(handles.wc_modbus, 'holdingregs', 3, 0); catch, end

try
    slave_ids = [1, 2, 4, 5, 7, 8];
    if isfield(handles, 'valve_modbus') && ~isempty(handles.valve_modbus)
        for k = 1:6
            try
                write(handles.valve_modbus, 'holdingregs', 2, 0, slave_ids(k));
            catch
            end
            pause(0.05);
        end
    end
catch
end

try clear handles.temp_modbus; clear handles.valve_modbus; clear handles.wc_modbus; catch, end
guidata(hObj, handles);
catch
end
end

function closeApp(hObj, ~)
stopSystem(hObj, []); delete(hObj);
end
end
