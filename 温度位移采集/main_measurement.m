% 主程序 - 启动温度和电涡流测量系统
% 使用方法：
% 1. 确保MATLAB已安装Instrument Control Toolbox
% 2. 连接设备到COM4
% 3. 运行此脚本

clear all;
close all;
clc;

fprintf('==================================\n');
fprintf('  温度与电涡流测量系统 v1.0\n');
fprintf('==================================\n\n');

% 检查所需工具箱
if ~license('test', 'Instrument_Control_Toolbox')
    error('需要安装 Instrument Control Toolbox！');
end

% 创建系统对象
try
    system = TempEddyCurrentSystem();
    fprintf('系统初始化成功！\n');
    fprintf('请点击"开始采集"按钮开始测量\n\n');
    
    fprintf('系统配置:\n');
    fprintf('- 串口: COM4\n');
    fprintf('- 波特率: 9600\n');
    fprintf('- 温度传感器: 17路 PT100\n');
    fprintf('- 电涡流传感器: 3路 (X/Y/Z)\n');
    fprintf('- 采样间隔: 1秒\n\n');
    
catch ME
    fprintf('系统初始化失败: %s\n', ME.message);
end