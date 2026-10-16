function accepted=requireSimulation(requestedSimulation)
% Historical multi-port scripts cannot access the current shared physical bus.
if ~isscalar(requestedSimulation) || ~ismember(requestedSimulation,[0 1]) || ~logical(requestedSimulation)
    error('lab:LegacyHardwareDisabled', ...
        '旧多串口硬件入口未启用。单RS485设备表、协议及阀门单位尚未核实；请使用模拟模式。');
end
accepted=true;
end
