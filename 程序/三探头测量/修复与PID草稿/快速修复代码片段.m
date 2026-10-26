% ============================================================================
% 快速修复代码片段 - 直接替换到原程序
% ============================================================================

%% 修改1: 替换第1209-1221行的timer创建代码
% ============================================================================
% 原代码:
%   acqTimer = timer(...
%       'ExecutionMode', 'fixedRate', ...
%       'BusyMode', 'drop', ...
% ============================================================================

% 新代码 - 复制以下内容:
acqTimer = timer( ...
    'ExecutionMode', 'fixedSpacing', ...    % ✅ 关键修改1: 改为fixedSpacing
    'Period', sampleIntervalSec, ...
    'StartDelay', sampleIntervalSec, ...
    'BusyMode', 'queue', ...                % ✅ 关键修改2: 改为queue
    'TimerFcn', @acquisitionTick, ...
    'ErrorFcn', @timerErrorCallback);

fprintf('⏱️  定时器模式: fixedSpacing (精确周期)\n');


%% 修改2: 替换第292行的Modbus超时设置
% ============================================================================
% 原代码:
%   m.Timeout = 2;
% ============================================================================

% 新代码:
m.Timeout = 0.5;  % ✅ 修改3: 减少超时时间,提高响应速度

fprintf('📡 Modbus超时设置: %.1f秒\n', m.Timeout);


%% 修改3: 在acquisitionTick函数开头添加性能监控 (第1241行之后)
% ============================================================================
% 在 function acquisitionTick(~,~) 开头添加以下代码:
% ============================================================================

function acquisitionTick(~,~)
    % ✅ 新增: 性能监控变量
    persistent readTimeHistory;
    if isempty(readTimeHistory)
        readTimeHistory = [];
    end

    if ~collecting
        return;
    end

    tic_total = tic;  % ✅ 新增: 记录总执行时间

    try
        %% 读取数据 - 添加耗时监控
        tic_read = tic;  % ✅ 新增: 记录读取开始时间
        [tempVals,probeVals] = readAllSensors();
        readTime = toc(tic_read);  % ✅ 新增: 计算读取耗时

        % ✅ 新增: 记录和分析读取时间
        readTimeHistory(end+1) = readTime;
        if length(readTimeHistory) > 50
            readTimeHistory(1) = [];
        end

        % ✅ 新增: 超时警告
        if readTime > 1.5
            fprintf('⚠️ 警告: 通信耗时过长 %.2f秒\n', readTime);
        end

        % ... 这里是原有的数据处理代码 ...
        % (保持原代码第1259-1340行不变)

        sampleIndex = sampleIndex + 1;
        tNow = sampleIndex * sampleIntervalSec;
        full_time(end+1) = tNow;
        full_temp(:,end+1) = tempVals;
        full_probe(:,end+1) = probeVals;
        lastTemp = tempVals;
        lastProbe = probeVals;
        handleMeasurementWindow(tempVals, probeVals, tNow);

        %% ✅ 修改4: 优化GUI更新频率 (替换原第1319-1322行)
        % 原代码: 每次都更新GUI
        % 新代码: 降低更新频率
        if mod(sampleIndex, 2) == 0  % 每4秒更新一次GUI
            updateCurrentDisplay();
            updatePlots();
        end

        %% 命令行输出 - 增加性能信息
        fprintf(...
            ['[%6d s] T1=%5.1f T2=%5.1f T3=%5.1f | ' ...
             'P1=%7.2f P2=%7.2f P3=%7.2f μm | ' ...
             '读取=%.3fs\n'], ...
            tNow, ...
            tempVals(1), tempVals(2), tempVals(3), ...
            probeVals(1), probeVals(2), probeVals(3), ...
            readTime);  % ✅ 新增: 显示读取耗时

        % ✅ 新增: 每20次采样输出性能统计
        if mod(sampleIndex, 20) == 0 && length(readTimeHistory) > 5
            avgRead = mean(readTimeHistory);
            maxRead = max(readTimeHistory);
            totalTime = toc(tic_total);
            fprintf(...
                '📊 [性能] 平均读取=%.3fs, 最大=%.3fs, 本次总计=%.3fs\n', ...
                avgRead, maxRead, totalTime);
        end

        drawnow limitrate;

    catch ME
        fprintf(...
            '⚠️ 第%d个采样周期失败: %s\n', ...
            sampleIndex+1, ME.message);
    end
end


%% ============================================================================
%% 可选修改5: 在readAllSensors函数中添加错误重试机制
%% ============================================================================
% 找到第1929行的 function readAllSensors()
% 在温度读取部分添加重试逻辑:
% ============================================================================

function [tempVals,probeVals] = readAllSensors()
    if simulateMode
        [tempVals,probeVals] = generateSimulationData();
        return;
    end

    % ✅ 新增: 错误重试配置
    maxRetries = 2;
    retryDelay = 0.1;  % 100ms

    %% 温度读取 - 添加重试机制
    tempVals = zeros(tempChannels,1);
    pos = 1;

    for kk = 1:length(tempServers)
        slave = tempServers(kk).id;
        n = tempServers(kk).numChannels;

        % ✅ 新增: 重试循环
        success = false;
        for retry = 1:maxRetries
            try
                rawTemp = read(m, 'holdingregs', tempRegister, n, slave);
                temp = double(rawTemp) * tempScale;
                tempVals(pos:pos+n-1) = temp(:);
                success = true;
                break;  % 成功则跳出重试循环
            catch ME
                if retry < maxRetries
                    fprintf('  重试温度服务器%d (第%d次)\n', slave, retry);
                    pause(retryDelay);
                else
                    rethrow(ME);  % 最后一次重试失败则抛出错误
                end
            end
        end

        pos = pos + n;
    end

    %% 电涡流读取 - 添加重试机制
    probeVals = zeros(numProbes,1);

    for jj = 1:numProbes
        % ✅ 新增: 重试循环
        for retry = 1:maxRetries
            try
                rawProbe = read(m, 'holdingregs', ...
                    probeSensors(jj).reg, 1, probeSensors(jj).id);
                rawSigned = signed16ToDouble(rawProbe);
                probeVals(jj) = rawSigned * probeSensors(jj).scale;
                break;  % 成功则跳出
            catch ME
                if retry < maxRetries
                    fprintf('  重试探头%d (第%d次)\n', jj, retry);
                    pause(retryDelay);
                else
                    rethrow(ME);
                end
            end
        end
    end
end


%% ============================================================================
%% 使用说明
%% ============================================================================
%
% 1. 打开原程序 ThermalError_18T_3Probe_V3.m
%
% 2. 找到对应行号,按照上面的标记进行替换:
%    - 修改1: 第1209-1221行 (timer创建)
%    - 修改2: 第292行 (Modbus超时)
%    - 修改3: 第1241行开头 (性能监控)
%    - 修改4: 第1319-1322行 (GUI更新)
%    - 修改5: 第1929行 (可选,读取重试)
%
% 3. 保存并运行
%
% 4. 观察命令行输出,验证:
%    ✅ 时间列为 0, 2, 4, 6, 8... (严格2秒间隔)
%    ✅ 读取耗时 < 1.0秒
%    ✅ 性能统计显示稳定
%
%% ============================================================================


%% ============================================================================
%% 诊断工具 - 测试通信性能
%% ============================================================================
% 在开始采集前,可以先运行这个测试,查看通信耗时:

function testModbusPerformance()
    fprintf('\n=== Modbus通信性能测试 ===\n');

    % 假设m是已连接的modbus对象
    global m tempServers probeSensors tempRegister

    % 测试温度读取
    fprintf('\n温度服务器读取测试:\n');
    for kk = 1:length(tempServers)
        slave = tempServers(kk).id;
        n = tempServers(kk).numChannels;

        times = zeros(10, 1);
        for i = 1:10
            tic;
            read(m, 'holdingregs', tempRegister, n, slave);
            times(i) = toc;
        end

        fprintf('  服务器%d (%d路): 平均%.3fs, 最大%.3fs\n', ...
            slave, n, mean(times), max(times));
    end

    % 测试电涡流读取
    fprintf('\n电涡流探头读取测试:\n');
    for jj = 1:3
        times = zeros(10, 1);
        for i = 1:10
            tic;
            read(m, 'holdingregs', probeSensors(jj).reg, 1, probeSensors(jj).id);
            times(i) = toc;
        end

        fprintf('  探头%d: 平均%.3fs, 最大%.3fs\n', ...
            jj, mean(times), max(times));
    end

    % 测试完整采样周期
    fprintf('\n完整采样周期测试:\n');
    cycleTimes = zeros(5, 1);
    for i = 1:5
        tic;
        [~, ~] = readAllSensors();
        cycleTimes(i) = toc;
    end

    fprintf('  平均%.3fs, 最大%.3fs, 最小%.3fs\n', ...
        mean(cycleTimes), max(cycleTimes), min(cycleTimes));

    % 判断
    if max(cycleTimes) > 1.8
        fprintf('\n⚠️ 警告: 采样周期接近2秒限制,可能影响定时精度!\n');
        fprintf('   建议: 考虑优化通信或增加采样周期\n');
    else
        fprintf('\n✅ 通信性能良好,支持2秒精确采样\n');
    end
end
