function ADRC_Active_Control_GUI_Dark_Final()
% =====================================================================
% 五轴机床多温区自抗扰热主动控制系统 (ADRC 暗黑科技实战版 终极封板)
% 核心更新 1：完美吸收实机成功经验，使用高级 modbus 的第5参数进行点名下发
% 核心更新 2：彻底阉割抗积分饱和机制，解决离散步长下的高频 Bang-Bang 震荡
% 物理匹配：球阀动作上限死锁 60°，寄存器地址修正为 2
% [2026-06 新增] 水冷机3路实时水箱温度采集（寄存器偏移100/101/102，÷10）
% =====================================================================

%% ------------------- [UI 主题配色预设] -------------------
bg_main = [0.12 0.14 0.18]; 
bg_panel = [0.18 0.20 0.25]; 
bg_edit = [0.08 0.10 0.12]; 
tc_norm = [0.85 0.88 0.90]; 
tc_high = [0.20 0.80 1.00]; 
tc_warn = [1.00 0.40 0.40]; 
tc_val = [0.00 1.00 0.40]; 

%% ------------------- [1. 主窗口设计] -------------------
hFig = figure('Name', '自抗扰(ADRC)热主动控制闭环系统 ', ...
'Position', [100, 50, 1350, 750], ... 
'MenuBar', 'none', 'ToolBar', 'none', ...
'Color', bg_main, ... 
'CloseRequestFcn', @closeApp); 

handles = guihandles(hFig);
handles.isRunning = false; 
handles.sim_timer = []; 

handles.time_log = []; handles.temp5_log = []; 
handles.valve6_log = []; handles.wc3_log = [];
handles.wc_temp_log = [];   % ★【新增】3路水冷机水箱实时温度记录
handles.sim_T_curr = [28.5; 29.0; 28.2; 26.5; 24.0]; 

%% ------------------- [2. 左侧：通讯与系统控制区] -------------------
hSysPanel = uipanel(hFig, 'Title', '🔌 硬件通讯配置', 'FontSize', 12, 'FontWeight', 'bold', ...
'BackgroundColor', bg_panel, 'ForegroundColor', tc_high, 'Position', [0.01, 0.70, 0.25, 0.28]);

uicontrol(hSysPanel, 'Style', 'text', 'String', '温度COM:', 'BackgroundColor', bg_panel, 'ForegroundColor', tc_norm, 'Units', 'normalized', 'Position', [0.05, 0.75, 0.35, 0.15], 'FontSize', 10);
handles.editCOM_Temp = uicontrol(hSysPanel, 'Style', 'edit', 'String', 'COM4', 'BackgroundColor', bg_edit, 'ForegroundColor', tc_val, 'Units', 'normalized', 'Position', [0.45, 0.75, 0.45, 0.15], 'FontSize', 10, 'FontWeight', 'bold');
uicontrol(hSysPanel, 'Style', 'text', 'String', '阀门COM:', 'BackgroundColor', bg_panel, 'ForegroundColor', tc_norm, 'Units', 'normalized', 'Position', [0.05, 0.55, 0.35, 0.15], 'FontSize', 10);
handles.editCOM_Valve = uicontrol(hSysPanel, 'Style', 'edit', 'String', 'COM5', 'BackgroundColor', bg_edit, 'ForegroundColor', tc_val, 'Units', 'normalized', 'Position', [0.45, 0.55, 0.45, 0.15], 'FontSize', 10, 'FontWeight', 'bold');
uicontrol(hSysPanel, 'Style', 'text', 'String', '水冷COM:', 'BackgroundColor', bg_panel, 'ForegroundColor', tc_norm, 'Units', 'normalized', 'Position', [0.05, 0.35, 0.35, 0.15], 'FontSize', 10);
handles.editCOM_WC = uicontrol(hSysPanel, 'Style', 'edit', 'String', 'COM6', 'BackgroundColor', bg_edit, 'ForegroundColor', tc_val, 'Units', 'normalized', 'Position', [0.45, 0.35, 0.45, 0.15], 'FontSize', 10, 'FontWeight', 'bold');

handles.chk_SimMode = uicontrol(hSysPanel, 'Style', 'checkbox', 'String', '开启离线仿真(不连硬件)', 'BackgroundColor', bg_panel, 'ForegroundColor', tc_warn, 'Units', 'normalized', 'Position', [0.1, 0.20, 0.8, 0.12], 'Value', 1);
handles.startBtn = uicontrol(hSysPanel, 'Style', 'pushbutton', 'String', '▶ 启动闭环控制', 'FontSize', 11, 'FontWeight', 'bold', 'Units', 'normalized', 'Position', [0.05, 0.04, 0.42, 0.15], 'BackgroundColor', [0.1 0.5 0.2], 'ForegroundColor', [0.9 1 0.9], 'Callback', @startSystem);
handles.stopBtn = uicontrol(hSysPanel, 'Style', 'pushbutton', 'String', '⏹ 安全停机', 'FontSize', 11, 'FontWeight', 'bold', 'Units', 'normalized', 'Position', [0.50, 0.04, 0.42, 0.15], 'BackgroundColor', [0.6 0.2 0.2], 'ForegroundColor', [1 0.9 0.9], 'Callback', @stopSystem);

%% ------------------- [3. 中间：系统状态显示区] -------------------
hStatusPanel = uipanel(hFig, 'Title', '🎯 控制目标与状态', 'FontSize', 12, 'FontWeight', 'bold', ...
'BackgroundColor', bg_panel, 'ForegroundColor', tc_high, 'Position', [0.27, 0.70, 0.32, 0.28]);

uicontrol(hStatusPanel, 'Style', 'text', 'String', '全局目标温度 (℃):', 'BackgroundColor', bg_panel, 'ForegroundColor', tc_norm, 'Units', 'normalized', 'Position', [0.1, 0.6, 0.45, 0.2], 'FontSize', 12);
handles.editTargetT = uicontrol(hStatusPanel, 'Style', 'edit', 'String', '20.0', 'BackgroundColor', bg_edit, 'ForegroundColor', tc_val, 'Units', 'normalized', 'Position', [0.55, 0.6, 0.25, 0.2], 'FontSize', 16, 'FontWeight', 'bold');

handles.txt_SysStatus = uicontrol(hStatusPanel, 'Style', 'text', 'String', '▶ 系统状态：待机中，阀门全关', 'BackgroundColor', bg_panel, 'ForegroundColor', [0.6 0.6 0.6], 'Units', 'normalized', 'Position', [0.05, 0.15, 0.9, 0.25], 'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

%% ------------------- [4. 右侧：全景实时数据看板] -------------------
hMonitorPanel = uipanel(hFig, 'Title', '📊 实时流数据监控矩阵', 'FontSize', 12, 'FontWeight', 'bold', ...
'BackgroundColor', bg_panel, 'ForegroundColor', tc_high, 'Position', [0.60, 0.70, 0.39, 0.28]);

handles.txt_TempInfo = uicontrol(hMonitorPanel, 'Style', 'text', 'String', sprintf('T1(床身): -- ℃\nT2(柱左): -- ℃\nT3(柱右): -- ℃\nT4(梁上): -- ℃\nT5(环境): -- ℃'), ...
'BackgroundColor', bg_panel, 'ForegroundColor', [1 0.6 0.2], 'FontSize', 11, 'FontWeight', 'bold', 'Units', 'normalized', 'Position', [0.02, 0.1, 0.30, 0.8], 'HorizontalAlignment', 'left');

handles.txt_WCInfo = uicontrol(hMonitorPanel, 'Style', 'text', 'String', sprintf('WC1(床): --\nWC2(柱): --\nWC3(梁): --'), ...
'BackgroundColor', bg_panel, 'ForegroundColor', [0.2 0.8 1], 'FontSize', 11, 'FontWeight', 'bold', 'Units', 'normalized', 'Position', [0.35, 0.1, 0.25, 0.8], 'HorizontalAlignment', 'left');

handles.txt_ValveInfo = uicontrol(hMonitorPanel, 'Style', 'text', 'String', sprintf('V1(床左): -- %%\nV2(床右): -- %%\nV4(柱左): -- %%\nV5(柱右): -- %%\nV7(梁上): -- %%\nV8(梁下): -- %%'), ...
'BackgroundColor', bg_panel, 'ForegroundColor', [0.4 1 0.4], 'FontSize', 11, 'FontWeight', 'bold', 'Units', 'normalized', 'Position', [0.62, 0.1, 0.36, 0.8], 'HorizontalAlignment', 'left');

%% ------------------- [5. 下方：高对比度荧光绘图区] -------------------
handles.axTemp = axes('Parent', hFig, 'Position', [0.05, 0.38, 0.92, 0.28]);
ylabel('温度响应 (℃)', 'FontWeight', 'bold', 'Color', tc_norm); 
set(handles.axTemp, 'Color', bg_edit, 'XColor', tc_norm, 'YColor', tc_norm, 'GridColor', [0.3 0.3 0.4], 'GridAlpha', 0.5);
grid(handles.axTemp, 'on'); hold(handles.axTemp, 'on'); 

handles.lineT1 = plot(handles.axTemp, NaN, NaN, '-', 'Color', [1.0 0.2 0.2], 'LineWidth', 2.5); 
handles.lineT2 = plot(handles.axTemp, NaN, NaN, '-', 'Color', [0.2 1.0 0.2], 'LineWidth', 2.5); 
handles.lineT3 = plot(handles.axTemp, NaN, NaN, '--', 'Color', [0.2 0.8 1.0], 'LineWidth', 2); 
handles.lineT4 = plot(handles.axTemp, NaN, NaN, '-', 'Color', [1.0 0.8 0.1], 'LineWidth', 2.5); 
handles.lineTTarget = plot(handles.axTemp, NaN, NaN, '--', 'Color', [0.8 0.8 0.8], 'LineWidth', 1.5); 

lgd1 = legend(handles.axTemp, 'T1(床身)', 'T2(柱左)', 'T3(柱右)', 'T4(横梁)', 'T5(环境温度)', 'Location', 'northwest', 'Orientation', 'horizontal');
set(lgd1, 'TextColor', tc_norm, 'Color', bg_panel, 'EdgeColor', bg_main);

handles.axValve = axes('Parent', hFig, 'Position', [0.05, 0.08, 0.92, 0.24]);
xlabel('控制进行时间 (秒)', 'FontWeight', 'bold', 'Color', tc_norm); 
ylabel('ADRC 动态开度 (%)', 'FontWeight', 'bold', 'Color', tc_norm); 
set(handles.axValve, 'Color', bg_edit, 'XColor', tc_norm, 'YColor', tc_norm, 'GridColor', [0.3 0.3 0.4], 'GridAlpha', 0.5);

grid(handles.axValve, 'on'); hold(handles.axValve, 'on'); ylim(handles.axValve, [-5 65]); 

handles.lineV1 = plot(handles.axValve, NaN, NaN, '-', 'Color', [1.0 0.2 0.2], 'LineWidth', 2);
handles.lineV2 = plot(handles.axValve, NaN, NaN, '--', 'Color', [1.0 0.5 0.5], 'LineWidth', 2);
handles.lineV4 = plot(handles.axValve, NaN, NaN, '-', 'Color', [0.2 1.0 0.2], 'LineWidth', 2);
handles.lineV5 = plot(handles.axValve, NaN, NaN, '--', 'Color', [0.5 1.0 0.5], 'LineWidth', 2);
handles.lineV7 = plot(handles.axValve, NaN, NaN, '-', 'Color', [0.2 0.8 1.0], 'LineWidth', 2);
handles.lineV8 = plot(handles.axValve, NaN, NaN, '--', 'Color', [0.6 0.6 1.0], 'LineWidth', 2);

lgd2 = legend(handles.axValve, 'V1', 'V2', 'V4', 'V5', 'V7', 'V8', 'Location', 'northwest', 'Orientation', 'horizontal');
set(lgd2, 'TextColor', tc_norm, 'Color', bg_panel, 'EdgeColor', bg_main);

guidata(hFig, handles);

%% ===================== [核心流程] 启动控制 =====================
function startSystem(hObj, ~)
handles = guidata(hObj);
if handles.isRunning; return; end 
isSimMode = get(handles.chk_SimMode, 'Value');

handles.time_log = []; handles.temp5_log = []; handles.valve6_log = []; handles.wc3_log = [];
handles.wc_temp_log = [];   % ★【新增】重置水冷温度记录

handles.adrc = struct();
for i = 1:6
handles.adrc(i).v = [25; 0]; 
handles.adrc(i).z = [25; 0];
handles.adrc(i).h = 1; 
handles.adrc(i).r = 0.05; 
handles.adrc(i).beta1 = 0.2; 
handles.adrc(i).beta2 = 0.04;
handles.adrc(i).b0 = -0.1; 
end

if ~isSimMode
try
handles.temp_modbus = modbus('serialrtu', get(handles.editCOM_Temp, 'String'), ...
'BaudRate', 19200, 'DataBits', 8, 'StopBits', 1, 'Parity', 'none');
handles.valve_modbus = modbus('serialrtu', get(handles.editCOM_Valve, 'String'), ...
'BaudRate', 9600, 'DataBits', 8, 'StopBits', 1, 'Parity', 'none');
handles.wc_modbus = modbus('serialrtu', get(handles.editCOM_WC, 'String'), ...
'BaudRate', 9600, 'DataBits', 8, 'StopBits', 1, 'Parity', 'none');
catch ME
errordlg(['硬件串口握手失败: ' ME.message], '连接异常'); return; 
end
end

handles.dataFile = ['ADRC_Control_Data_' datestr(now, 'mmdd_HHMM') '.xlsx'];
% ★【新增 WC1_Temp / WC2_Temp / WC3_Temp 三列】
header = {'Time(s)', 'T1_Bed', 'T2_Col_L', 'T3_Col_R', 'T4_Beam', 'T5_Env', ...
          'WC1_Temp', 'WC2_Temp', 'WC3_Temp', ...
          'WC1_On', 'WC2_On', 'WC3_On', ...
          'V1', 'V2', 'V4', 'V5', 'V7', 'V8'};
try writecell(header, handles.dataFile); catch; end

handles.isRunning = true;
set(handles.txt_SysStatus, 'String', '▶ 系统状态：全自动闭环控温中...', 'ForegroundColor', [0.2 1.0 0.2]);

guidata(hObj, handles);

handles.sim_timer = timer('ExecutionMode', 'fixedRate', 'Period', 1, ...
'TimerFcn', {@mainLoop, hFig}, 'ErrorFcn', @timerError);
start(handles.sim_timer);
end

%% ===================== [循环节] ADRC 离散核心 =====================
function mainLoop(~, ~, hFig)
try 
if ~ishandle(hFig); return; end 
handles = guidata(hFig);
if ~handles.isRunning; return; end 
isSimMode = get(handles.chk_SimMode, 'Value');

T_target_val = str2double(get(handles.editTargetT, 'String'));
if isnan(T_target_val); T_target_val = 20.0; end

%% --- 读取机床5路温度 ---
T_curr = zeros(5,1);
if isSimMode
if isempty(handles.valve6_log)
u_sim = zeros(6,1);
else
u_sim = handles.valve6_log(:, end);
end
T_sim = handles.sim_T_curr; 
T_sim(1) = T_sim(1) + 0.05*(28.5-T_sim(1)) - 0.005*(u_sim(1)+u_sim(2));
T_sim(2) = T_sim(2) + 0.05*(29.0-T_sim(2)) - 0.008*u_sim(3);
T_sim(3) = T_sim(3) + 0.05*(28.2-T_sim(3)) - 0.008*u_sim(4);
T_sim(4) = T_sim(4) + 0.05*(26.5-T_sim(4)) - 0.006*(u_sim(5)+u_sim(6));
T_sim(5) = T_sim(5) + 0.005*randn;
T_curr = T_sim; handles.sim_T_curr = T_sim; 
else
try
for i = 1:5; T_curr(i) = read(handles.temp_modbus, 'holdingregs', 1536+i, 1) / 10; end
catch
if ~isempty(handles.temp5_log); T_curr = handles.temp5_log(:, end); else; T_curr = [25;25;25;25;25]; end
end
end

%% --- ADRC 计算6路球阀开度 ---
u_cmd = zeros(6, 1);
[u_cmd(1), handles.adrc(1)] = discrete_ADRC(T_target_val, T_curr(1), handles.adrc(1)); 
[u_cmd(2), handles.adrc(2)] = discrete_ADRC(T_target_val, T_curr(1), handles.adrc(2)); 
[u_cmd(3), handles.adrc(3)] = discrete_ADRC(T_target_val, T_curr(2), handles.adrc(3)); 
[u_cmd(4), handles.adrc(4)] = discrete_ADRC(T_target_val, T_curr(3), handles.adrc(4)); 
[u_cmd(5), handles.adrc(5)] = discrete_ADRC(T_target_val, T_curr(4), handles.adrc(5)); 
[u_cmd(6), handles.adrc(6)] = discrete_ADRC(T_target_val, T_curr(4), handles.adrc(6)); 

%% --- 水冷机启停回差保护逻辑 ---
wc1 = double(T_curr(1) > 20); wc2 = double(T_curr(2) > 20 || T_curr(3) > 20); wc3 = double(T_curr(4) > 20);
if T_curr(1) <= 19.5; wc1 = 0; end
if T_curr(2) <= 19.5 && T_curr(3) <= 19.5; wc2 = 0; end
if T_curr(4) <= 19.5; wc3 = 0; end
wc_state = [wc1; wc2; wc3];

if ~isSimMode
try
write(handles.wc_modbus, 'holdingregs', 1, wc_state(1));
write(handles.wc_modbus, 'holdingregs', 2, wc_state(2));
write(handles.wc_modbus, 'holdingregs', 3, wc_state(3));
catch; end
end

%% --- ★【新增】读取3台水冷机实时水箱温度 ---
% 寄存器地址表（3Ji-Yi-Ti.xlsx）：偏移100=水箱温度1，101=水箱温度2，102=水箱温度3
% 读出原始值需 ÷10 得到真实温度（例如读到156 → 15.6℃）
T_wc = zeros(3, 1);
if ~isSimMode
    try
        T_wc(1) = read(handles.wc_modbus, 'holdingregs', 101, 1) / 10;
        T_wc(2) = read(handles.wc_modbus, 'holdingregs', 102, 1) / 10;
        T_wc(3) = read(handles.wc_modbus, 'holdingregs', 103, 1) / 10;
    catch
        % 读取失败时保持上一时刻值，避免数据断档
        if ~isempty(handles.wc_temp_log)
            T_wc = handles.wc_temp_log(:, end);
        end
    end
else
    % 仿真模式：用设定值附近加小噪声模拟水箱温度
    T_wc = [15.7; 15.7; 15.7] + 0.1 * randn(3,1);
end

%% --- ★ 核心修复：点名下发球阀 ---
slave_ids = [1, 2, 4, 5, 7, 8]; % 对应 V1, V2, V4, V5, V7, V8
if ~isSimMode
for v_idx = 1:6
slaveID = slave_ids(v_idx);
dat = round(u_cmd(v_idx) * 100);
dat = max(0, min(6000, dat));
try
write(handles.valve_modbus, 'holdingregs', 2, dat, slaveID);
catch
end
pause(0.05);
end
end

%% --- 数据归档（时间、机床温度、水冷温度、水冷开关、球阀开度）---
t_now = length(handles.time_log);
handles.time_log     = [handles.time_log, t_now];
handles.temp5_log    = [handles.temp5_log, T_curr];
handles.valve6_log   = [handles.valve6_log, u_cmd];
handles.wc3_log      = [handles.wc3_log, wc_state];
handles.wc_temp_log  = [handles.wc_temp_log, T_wc];  % ★【新增】

%% --- 界面刷新 ---
set(handles.txt_TempInfo, 'String', sprintf('T1(床身): %.2f ℃\nT2(柱左): %.2f ℃\nT3(柱右): %.2f ℃\nT4(梁上): %.2f ℃\nT5(环境): %.2f ℃', T_curr(1), T_curr(2), T_curr(3), T_curr(4), T_curr(5)));
% ★【新增】界面也显示水冷实时温度而不只是开关状态
set(handles.txt_WCInfo, 'String', sprintf('WC1(床): %d | %.1f℃\nWC2(柱): %d | %.1f℃\nWC3(梁): %d | %.1f℃', wc_state(1), T_wc(1), wc_state(2), T_wc(2), wc_state(3), T_wc(3)));
set(handles.txt_ValveInfo, 'String', sprintf('V1(床左): %04.1f %%\nV2(床右): %04.1f %%\nV4(柱左): %04.1f %%\nV5(柱右): %04.1f %%\nV7(梁上): %04.1f %%\nV8(梁下): %04.1f %%', u_cmd(1), u_cmd(2), u_cmd(3), u_cmd(4), u_cmd(5), u_cmd(6)));

%% --- Excel 写入（★列顺序：时间|T1-T5|WC1-WC3温度|WC1-WC3开关|V1-V8）---
row_data = round([t_now, T_curr', T_wc', wc_state', u_cmd'], 2);
try writematrix(row_data, handles.dataFile, 'WriteMode', 'append'); catch; end

%% --- 绘图更新 ---
set(handles.lineT1, 'XData', handles.time_log, 'YData', handles.temp5_log(1,:));
set(handles.lineT2, 'XData', handles.time_log, 'YData', handles.temp5_log(2,:));
set(handles.lineT3, 'XData', handles.time_log, 'YData', handles.temp5_log(3,:));
set(handles.lineT4, 'XData', handles.time_log, 'YData', handles.temp5_log(4,:));
set(handles.lineTTarget, 'XData', handles.time_log, 'YData', repmat(T_target_val, 1, t_now+1));

set(handles.lineV1, 'XData', handles.time_log, 'YData', handles.valve6_log(1,:));
set(handles.lineV2, 'XData', handles.time_log, 'YData', handles.valve6_log(2,:));
set(handles.lineV4, 'XData', handles.time_log, 'YData', handles.valve6_log(3,:));
set(handles.lineV5, 'XData', handles.time_log, 'YData', handles.valve6_log(4,:));
set(handles.lineV7, 'XData', handles.time_log, 'YData', handles.valve6_log(5,:));
set(handles.lineV8, 'XData', handles.time_log, 'YData', handles.valve6_log(6,:));

if t_now > 180; xlim(handles.axTemp, [t_now-180 t_now+10]); xlim(handles.axValve, [t_now-180 t_now+10]);
else; xlim(handles.axTemp, [0 200]); xlim(handles.axValve, [0 200]); end

guidata(hFig, handles); drawnow; 
catch
end
end

%% ===================== [算法库] ADRC 离散内核 =====================
function [u_actual, s] = discrete_ADRC(v0, y, s)
fh = -s.r * (s.v(1) - v0) - 2 * sqrt(s.r) * s.v(2); 
s.v(1) = s.v(1) + s.h * s.v(2);
s.v(2) = s.v(2) + s.h * fh;

e_eso = s.z(1) - y; 

% ★ 核心修改：已彻底阉割抗积分饱和机制
% 现在的 ESO 只有最纯粹的误差与扰动观测功能
s.z(1) = s.z(1) + s.h * (s.z(2) - s.beta1 * e_eso + s.b0 * (s.v(1) - y));
s.z(2) = s.z(2) + s.h * (-s.beta2 * e_eso);

e1 = s.v(1) - s.z(1);
u0 = 1.2 * e1; 
u_ideal = (u0 - s.z(2)) / s.b0; 

% ★ 纯物理硬限幅：算出来多少就是多少，只拦截不反击
u_actual = max(0, min(60, u_ideal));
end

%% ===================== [安全收尾] =====================
function stopSystem(hObj, ~)
try
handles = guidata(hObj); handles.isRunning = false;
if ~isempty(handles.sim_timer); stop(handles.sim_timer); delete(handles.sim_timer); handles.sim_timer = []; end
try write(handles.wc_modbus, 'holdingregs', 1, 0); catch; end
try write(handles.wc_modbus, 'holdingregs', 2, 0); catch; end
try write(handles.wc_modbus, 'holdingregs', 3, 0); catch; end

% ★ 停机时也要挨个点名关阀门
try
slave_ids = [1, 2, 4, 5, 7, 8];
if isfield(handles, 'valve_modbus') && ~isempty(handles.valve_modbus)
for v_idx = 1:6
try write(handles.valve_modbus, 'holdingregs', 2, 0, slave_ids(v_idx)); catch; end
pause(0.05);
end
end
catch; end

try clear handles.temp_modbus; clear handles.valve_modbus; clear handles.wc_modbus; catch; end

set(handles.txt_SysStatus, 'String', '▶ 系统状态：已安全停机，阀门全关', 'ForegroundColor', [1.0 0.4 0.4]);

guidata(hObj, handles);
catch
end
end

function timerError(~, ~)
try handles = guidata(hFig); stopSystem(hFig, []); catch; end
end
function closeApp(hObj, ~)
stopSystem(hObj, []); delete(hObj);
end
end
