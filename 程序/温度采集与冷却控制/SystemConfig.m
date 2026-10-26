% 系统配置文件
% 根据实际硬件情况修改以下参数

classdef SystemConfig
    properties (Constant)
        % 串口设置
        SERIAL_PORT = 'COM4';
        BAUD_RATE = 9600;
        DATA_BITS = 8;
        STOP_BITS = 1;
        PARITY = 'none';
        
        % Modbus从机ID
        TEMP_SLAVE_ID_1 = 1;  % ID1: 8个温度传感器
        TEMP_SLAVE_ID_2 = 2;  % ID2: 8个温度传感器
        TEMP_SLAVE_ID_3 = 3;  % ID3: 1个温度传感器
        EDDY_SLAVE_ID = 4;    % ID4: 3个电涡流传感器
        
        % 寄存器地址（根据实际设备调整）
        TEMP_START_REG = 0;      % 温度传感器起始寄存器
        EDDY_START_REG = 100;    % 电涡流传感器起始寄存器
        
        % 数据转换系数
        TEMP_SCALE = 10;         % PT100温度值缩放系数
        EDDY_SCALE = 100;        % 电涡流位移值缩放系数（转换为μm）
        
        % 采样参数
        SAMPLING_INTERVAL = 1;   % 采样间隔（秒）
        
        % Rtest三坐标测量参数
        RTEST_SENSITIVITY = 1.0; % 灵敏度系数
        RTEST_OFFSET_X = 0;      % X方向零点偏移
        RTEST_OFFSET_Y = 0;      % Y方向零点偏移
        RTEST_OFFSET_Z = 0;      % Z方向零点偏移
    end
end