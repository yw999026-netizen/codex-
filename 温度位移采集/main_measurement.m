% 18温度/3探头统一模拟入口；真实通信仍待设备表与驱动核实。
repositoryRoot=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repositoryRoot,'prototypes','IntegratedThermalLab','matlab'));
IntegratedThermalLab;
