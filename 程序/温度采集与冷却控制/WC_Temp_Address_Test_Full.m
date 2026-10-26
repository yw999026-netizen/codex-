function WC_Temp_Address_Test_Full()
% =====================================================================
% 水冷机水箱温度地址完整检测程序
% 功能：
% 1. 自动连接水冷机 COM6
% 2. 同时测试两套地址：101/102/103 和 100/101/102
% 3. 直接在命令行输出两套结果
% 4. 你只需要看哪一套更接近水冷机屏幕显示值即可
% =====================================================================

clc;
fprintf('\n');
fprintf('============================================================\n');
fprintf('         水冷机水箱温度 Modbus 地址检测完整程序\n');
fprintf('============================================================\n');

%% ------------------- [1. 串口配置] -------------------
COM_port = 'COM6';
BaudRate = 9600;
DataBits = 8;
StopBits = 1;
Parity   = 'none';

fprintf('【当前配置】\n');
fprintf('  串口号   : %s\n', COM_port);
fprintf('  波特率   : %d\n', BaudRate);
fprintf('  数据位   : %d\n', DataBits);
fprintf('  停止位   : %d\n', StopBits);
fprintf('  校验位   : %s\n\n', Parity);

%% ------------------- [2. 建立连接] -------------------
try
    wc = modbus('serialrtu', COM_port, ...
        'BaudRate', BaudRate, ...
        'DataBits', DataBits, ...
        'StopBits', StopBits, ...
        'Parity', Parity);
    fprintf('✅ 水冷机串口连接成功。\n\n');
catch ME
    fprintf('❌ 水冷机串口连接失败！\n');
    fprintf('错误信息：%s\n', ME.message);
    fprintf('请检查：\n');
    fprintf('1. COM6 是否正确；\n');
    fprintf('2. 水冷机是否已上电；\n');
    fprintf('3. 是否有别的 MATLAB 程序占用了 COM6。\n');
    return;
end

%% ------------------- [3. 读取方案A] -------------------
fprintf('------------------------------------------------------------\n');
fprintf('【方案A】读取地址：101 / 102 / 103\n');
fprintf('说明：这套通常对应 MATLAB 1-based 写法\n');
try
    A1_raw = read(wc, 'holdingregs', 101, 1);
    A2_raw = read(wc, 'holdingregs', 102, 1);
    A3_raw = read(wc, 'holdingregs', 103, 1);

    A1 = A1_raw / 10;
    A2 = A2_raw / 10;
    A3 = A3_raw / 10;

    fprintf('  WC1 原始值 = %d, 温度 = %.1f ℃\n', A1_raw, A1);
    fprintf('  WC2 原始值 = %d, 温度 = %.1f ℃\n', A2_raw, A2);
    fprintf('  WC3 原始值 = %d, 温度 = %.1f ℃\n', A3_raw, A3);
catch ME
    fprintf('  ❌ 方案A读取失败：%s\n', ME.message);
    A1 = NaN; A2 = NaN; A3 = NaN;
end
fprintf('\n');

%% ------------------- [4. 读取方案B] -------------------
fprintf('------------------------------------------------------------\n');
fprintf('【方案B】读取地址：100 / 101 / 102\n');
fprintf('说明：这套通常对应协议偏移地址写法\n');
try
    B1_raw = read(wc, 'holdingregs', 100, 1);
    B2_raw = read(wc, 'holdingregs', 101, 1);
    B3_raw = read(wc, 'holdingregs', 102, 1);

    B1 = B1_raw / 10;
    B2 = B2_raw / 10;
    B3 = B3_raw / 10;

    fprintf('  WC1 原始值 = %d, 温度 = %.1f ℃\n', B1_raw, B1);
    fprintf('  WC2 原始值 = %d, 温度 = %.1f ℃\n', B2_raw, B2);
    fprintf('  WC3 原始值 = %d, 温度 = %.1f ℃\n', B3_raw, B3);
catch ME
    fprintf('  ❌ 方案B读取失败：%s\n', ME.message);
    B1 = NaN; B2 = NaN; B3 = NaN;
end
fprintf('\n');

%% ------------------- [5. 判断说明] -------------------
fprintf('============================================================\n');
fprintf('【你怎么判断哪套地址是对的】\n');
fprintf('1. 看水冷机屏幕上的 1# / 2# / 3# 水箱温度。\n');
fprintf('2. 对比上面方案A和方案B的三个数。\n');
fprintf('3. 哪一套更接近屏幕显示值，就选哪一套。\n\n');
fprintf('举例：\n');
fprintf('如果水冷机屏幕显示大约是 15.6 / 16.1 / 15.8 ℃，\n');
fprintf('而方案A输出也接近 15.6 / 16.1 / 15.8 ℃，\n');
fprintf('那以后程序里就用 101 / 102 / 103。\n\n');
fprintf('如果方案B更接近，就把正式程序改成 100 / 101 / 102。\n');
fprintf('============================================================\n');

%% ------------------- [6. 断开连接] -------------------
try
    clear wc;
    fprintf('\n✅ 检测结束，串口已释放。\n');
catch
end
end
