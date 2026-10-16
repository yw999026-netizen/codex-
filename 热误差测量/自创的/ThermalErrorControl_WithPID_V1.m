function engine=ThermalErrorControl_WithPID_V1
% Compatibility entry: fixed-cooling integrated simulation, not a PID controller.
% The incomplete historical draft remains in git at830212c4; no gains inferred.
repositoryRoot=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(repositoryRoot,'prototypes','IntegratedThermalLab','matlab'));
warning('lab:PIDNotCommissioned','位移闭环未启用：启动固定冷却组合模拟。先完成有效窗口与动态辨识。');
engine=IntegratedThermalLab;
end
