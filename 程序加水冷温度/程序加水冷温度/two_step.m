% 历史直接写硬件脚本，仅保留参考；当前共享总线未完成接入核实。
error('lab:LegacyHardwareDisabled','历史直接控阀入口已停用；请先完成统一设备表与只读验证。');
clc;
clear;
close all;

%% =========================
% 1. 系统参数
% ==========================

a = 0.98;
b = 0.02;

Ts = 1;

%% =========================
% 2. 仿真参数
% ==========================

N = 100;

T = zeros(1,N);

T(1) = 8;

T_ref = 5;

u_prev = 0;
%% =========================
% 3. 候选控制输入
% ==========================

u_candidates = 0:10:60;

%% =========================
% 4. MPC预测步长
% ==========================

Np = 5;

%% =========================
% 5. 控制过程
% ==========================

u_history = zeros(1,N);

for k = 1:N-1

    % 如果剩余时间不足预测步长
    if k + Np > N
        horizon = N-k;
    else
        horizon = Np;
    end

    best_cost = inf;
    best_u = 0;

    % ---------------------------------
    % 遍历候选控制量
    % ---------------------------------

    for i = 1:length(u_candidates)

        u_test = u_candidates(i);

        T_pred = T(k);

        cost = 0;

        % ---------------------------------
        % 预测未来
        % ---------------------------------

        for j = 1:horizon

            T_pred = a*T_pred + b*u_test;

            lambda = 0.05;

            cost = cost + (T_pred - T_ref)^2 ...
             + lambda*(u_test - u_history(k))^2;
        end

        % ---------------------------------
        % 找最小代价
        % ---------------------------------

        if cost < best_cost

            best_cost = cost;
            best_u = u_test;

        end

    end

    % ---------------------------------
    % 只执行当前这一步
    % ---------------------------------

    u_history(k) = best_u;

    T(k+1) = a*T(k) + b*best_u;

end

%% =========================
% 6. 绘图
% ==========================

figure;

subplot(2,1,1);

plot(1:N,T,'LineWidth',1.5);
hold on;

yline(T_ref,'--');

grid on;

xlabel('采样时间');
ylabel('温度');

title('1×1 简单MPC');

legend('温度','目标温度');

subplot(2,1,2);

stairs(1:N,u_history,'LineWidth',1.5);

grid on;

xlabel('采样时间');
ylabel('阀门开度');

title('MPC控制输入');
