% 历史直接写硬件脚本，仅保留参考；当前共享总线未完成接入核实。
error('lab:LegacyHardwareDisabled','历史直接控阀入口已停用；请先完成统一设备表与只读验证。');
clc;
clear;
close all;

%% =========================
% 1. 真实热系统参数
% ==========================
K = 0.8;
T = 300;       % 时间常数
tau = 50;      % 纯滞后

%% =========================
% 2. 实验参数
% ==========================
Ts = 1;                    % 采样时间 1 s
t = 0:Ts:2000;             % 总实验时间
N = length(t);

% 阀门输入
u = zeros(1, N);

% 100 s 时阀门突然打开
u(t >= 100) = 10;

%% =========================
% 3. 根据真实模型生成温度
% ==========================
y = zeros(1, N);

for k = 2:N

    % 计算纯滞后后的输入索引
    delayStep = round(tau / Ts);

    if k > delayStep
        u_delay = u(k-delayStep);
    else
        u_delay = 0;
    end

    % 一阶热系统
    dy = (-y(k-1) + K*u_delay) / T;

    y(k) = y(k-1) + Ts*dy;
end

%% =========================
% 4. 加入测量噪声
% ==========================
noise = 0.05 * randn(size(y));

y_measured = y + noise;

%% =========================
% 5. 绘图
% ==========================
figure;

plot(t, u, 'LineWidth', 1.2);
hold on;

plot(t, y_measured, 'LineWidth', 1.2);

grid on;

xlabel('时间 / s');
ylabel('输入 / 温度变化');

title('带噪声的一阶纯滞后热系统实验数据');

legend('阀门输入 u', '测量温度 y');
