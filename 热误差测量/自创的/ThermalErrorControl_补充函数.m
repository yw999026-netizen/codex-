% ========================================================================
% ThermalErrorControl_WithPID_V1.m 的补充函数部分
%
% 这些函数需要添加到主程序文件中
% 放在PIDController类定义之前
% ========================================================================


%% ========================================================================
% 设置冷态零点（保持不变）
% ========================================================================

    function zeroCallback(~,~)
        if ~collecting || windowMode ~= 0
            return;
        end

        if isempty(lastProbe)
            return;
        end

        [OK,message] = checkProbeVector(lastProbe);

        if ~OK
            fprintf('\n❌ 不能设置冷态零点：%s\n', message);
            return;
        end

        startMeasurementWindow(1);
    end


%% ========================================================================
% 记录热误差样本（保持不变）
% ========================================================================

    function sampleCallback(~,~)
        if ~collecting || windowMode ~= 0
            return;
        end

        if ~zeroReady
            fprintf('\n⚠️ 请先设置冷态零点。\n');
            return;
        end

        if isempty(lastProbe)
            return;
        end

        [OK,message] = checkProbeVector(lastProbe);

        if ~OK
            fprintf('\n❌ 当前不能记录样本：%s\n', message);
            return;
        end

        startMeasurementWindow(2);
    end


%% ========================================================================
% 启动测量任务（保持不变）
% ========================================================================

    function startMeasurementWindow(modeValue)
        windowMode = modeValue;
        windowPhase = 1;
        windowRequestClock = tic;
        windowTempBuffer = [];
        windowProbeBuffer = [];
        windowTimeBuffer = [];

        set(btnZero,'Enable','off');
        set(btnSample,'Enable','off');

        if modeValue == 1
            fprintf('\n=============================================\n');
            fprintf('开始设置冷态零点\n');
        else
            fprintf('\n=============================================\n');
            fprintf('开始记录第 %d 个热误差样本\n', sampleNumber+1);
        end

        fprintf('先等待稳定：%d s\n', settleTimeSec);
        fprintf('随后采集：%d 个点 × %d s\n', ...
            measurementSamples, sampleIntervalSec);
        fprintf('=============================================\n');

        set(statusText, 'String', ...
            sprintf('状态：等待机械稳定 %d s', settleTimeSec));
    end


%% ========================================================================
% 处理稳定和测量窗口（保持不变）
% ========================================================================

    function handleMeasurementWindow(tempVals, probeVals, tNow)
        if windowMode == 0
            return;
        end

        % 等待5秒
        if windowPhase == 1
            elapsed = toc(windowRequestClock);
            remaining = settleTimeSec - elapsed;

            if remaining > 0
                set(statusText, 'String', ...
                    sprintf('状态：等待稳定，还剩约 %.1f s', remaining));
                return;
            end

            windowPhase = 2;
            fprintf('✅ 稳定等待完成，开始正式取10个点。\n');
        end

        % 正式收集2秒采样点
        if windowPhase == 2
            windowTempBuffer(:,end+1) = tempVals;
            windowProbeBuffer(:,end+1) = probeVals;
            windowTimeBuffer(end+1) = tNow;

            currentCount = size(windowProbeBuffer,2);

            set(statusText, 'String', ...
                sprintf('状态：测量中 %d / %d 个点', ...
                    currentCount, measurementSamples));

            if currentCount >= measurementSamples
                processMeasurementWindow();
            end
        end
    end


%% ========================================================================
% 处理一个完整测量窗口（保持大部分不变）
% ========================================================================

    function processMeasurementWindow()
        % 整个窗口都必须在±100 μm以内
        [OK,message] = checkProbeWindow(windowProbeBuffer);

        if ~OK
            fprintf('\n=============================================\n');
            fprintf('❌ 本次测量无效\n');
            fprintf('原因：%s\n',message);
            fprintf('本次数据不会进入建模样本。\n');
            fprintf('=============================================\n');
            resetMeasurementWindow();
            return;
        end

        % 平均值
        meanTemp = mean(windowTempBuffer,2);
        meanProbe = mean(windowProbeBuffer,2);
        tMean = round(mean(windowTimeBuffer));
        tStart = windowTimeBuffer(1);
        tEnd = windowTimeBuffer(end);

        % 冷态零点
        if windowMode == 1
            zeroProbe = meanProbe;
            zeroTemp = meanTemp;
            zeroReady = true;

            fprintf('\n=============================================\n');
            fprintf('✅ 冷态零点设置完成\n');
            fprintf('探头1零点 = %.3f μm\n', zeroProbe(1));
            fprintf('探头2零点 = %.3f μm\n', zeroProbe(2));
            fprintf('探头3零点 = %.3f μm\n', zeroProbe(3));

            for ii = 1:3
                if abs(zeroProbe(ii)) > probeRecommendedZeroLimit_um
                    fprintf('⚠️ 探头%d冷态位置离中点较远：%.2f μm\n', ...
                        ii, zeroProbe(ii));
                end
            end

            fprintf('=============================================\n');

            set(zeroStatusText, 'String', ...
                sprintf('冷态零点：P1=%.2f，P2=%.2f，P3=%.2f μm', ...
                    zeroProbe(1), zeroProbe(2), zeroProbe(3)));

        % 正式热误差样本
        elseif windowMode == 2
            deltaProbe = meanProbe - zeroProbe;

            % XYZ转换
            if calibrationEnabled
                xyzMean = C_xyz_from_probe * deltaProbe;
                deltaProbeWindow = windowProbeBuffer - zeroProbe;
                xyzWindow = C_xyz_from_probe * deltaProbeWindow;
                xyzStd = std(xyzWindow, 0, 2);
            else
                xyzMean = [NaN;NaN;NaN];
                xyzStd = [NaN;NaN;NaN];
            end

            % 保存正式样本
            sampleNumber = sampleNumber + 1;
            sampleTime(end+1) = tMean;
            sampleTemp(:,end+1) = meanTemp;
            sampleProbeMean(:,end+1) = meanProbe;
            sampleDeltaProbe(:,end+1) = deltaProbe;
            sampleXYZ(:,end+1) = xyzMean;
            sampleStdXYZ(:,end+1) = xyzStd;
            sampleWindowStart(end+1) = tStart;
            sampleWindowEnd(end+1) = tEnd;

            % 显示
            fprintf('\n=============================================\n');
            fprintf('✅ 第 %d 个热误差样本完成\n', sampleNumber);
            fprintf('实验时间：%d s\n', tMean);
            fprintf('\n测量窗口：%d s ～ %d s\n', tStart, tEnd);
            fprintf('\n探头平均值：\n');
            fprintf('P1 = %.3f μm\n', meanProbe(1));
            fprintf('P2 = %.3f μm\n', meanProbe(2));
            fprintf('P3 = %.3f μm\n', meanProbe(3));
            fprintf('\n相对冷态变化：\n');
            fprintf('ΔP1 = %.3f μm\n', deltaProbe(1));
            fprintf('ΔP2 = %.3f μm\n', deltaProbe(2));
            fprintf('ΔP3 = %.3f μm\n', deltaProbe(3));

            if calibrationEnabled
                fprintf('\nXYZ热误差：\n');
                fprintf('X = %.3f μm\n', xyzMean(1));
                fprintf('Y = %.3f μm\n', xyzMean(2));
                fprintf('Z = %.3f μm\n', xyzMean(3));
                fprintf('\n窗口波动标准差：\n');
                fprintf('σX = %.3f μm\n', xyzStd(1));
                fprintf('σY = %.3f μm\n', xyzStd(2));
                fprintf('σZ = %.3f μm\n', xyzStd(3));
            else
                fprintf('\n⚠️ 当前没有真实XYZ标定矩阵。\n');
            end

            fprintf('=============================================\n');

            set(sampleCountText, 'String', ...
                sprintf('有效热误差样本：%d', sampleNumber));
        end

        resetMeasurementWindow();
    end


%% ========================================================================
% 重置测量窗口（保持不变）
% ========================================================================

    function resetMeasurementWindow()
        windowMode = 0;
        windowPhase = 0;
        windowTempBuffer = [];
        windowProbeBuffer = [];
        windowTimeBuffer = [];

        set(statusText, 'String', '状态：每2 s固定连续采集中');
        refreshActionButtons();
    end


%% ========================================================================
% 单点探头范围检查（保持不变）
% ========================================================================

    function [OK,message] = checkProbeVector(probeVals)
        OK = true;
        message = '';

        if any(~isfinite(probeVals))
            OK = false;
            message = '存在无效探头数据';
            return;
        end

        for ii = 1:3
            if abs(probeVals(ii)) > probeSafeLimit_um
                OK = false;
                message = sprintf(...
                    '探头%d超出±%d μm范围，当前值%.2f μm', ...
                    ii, probeSafeLimit_um, probeVals(ii));
                return;
            end
        end
    end


%% ========================================================================
% 测量窗口范围检查（保持不变）
% ========================================================================

    function [OK,message] = checkProbeWindow(buffer)
        OK = true;
        message = '';

        if isempty(buffer)
            OK = false;
            message = '测量窗口为空';
            return;
        end

        if any(~isfinite(buffer(:)))
            OK = false;
            message = '测量窗口存在无效数据';
            return;
        end

        for ii = 1:3
            if any(abs(buffer(ii,:)) > probeSafeLimit_um)
                OK = false;
                maxValue = max(abs(buffer(ii,:)));
                message = sprintf(...
                    '探头%d在测量窗口内曾超出±%d μm，最大绝对值%.2f μm', ...
                    ii, probeSafeLimit_um, maxValue);
                return;
            end
        end
    end


%% ========================================================================
% GUI探头状态（保持不变）
% ========================================================================

    function updateProbeStatus()
        if isempty(lastProbe)
            return;
        end

        allOK = true;

        for ii = 1:3
            value = lastProbe(ii);
            absValue = abs(value);

            % 正常区域
            if absValue < probeWarningLimit_um
                status = '正常';
                bg = [0.84 1.00 0.84];

            % 90~100
            elseif absValue <= probeSafeLimit_um
                status = '接近线性边界';
                bg = [1.00 0.93 0.72];

            % 超范围
            else
                status = '超出线性范围';
                bg = [1.00 0.80 0.80];
                allOK = false;
            end

            set(probeStatusText(ii), 'String', ...
                sprintf('探头%d：%8.2f μm    %s', ii, value, status), ...
                'BackgroundColor', bg);
        end

        if allOK
            set(detectPositionText, 'String', ...
                '检测状态：三个探头均在±100 μm有效范围内', ...
                'BackgroundColor', [0.84 1.00 0.84]);
        else
            set(detectPositionText, 'String', ...
                '检测状态：当前不能记录热误差样本', ...
                'BackgroundColor', [1.00 0.80 0.80]);
        end
    end


%% ========================================================================
% 更新当前值表格（扩展包含球阀和PID信息）
% ========================================================================

    function updateCurrentDisplay()
        if isempty(lastTemp) || isempty(lastProbe)
            return;
        end

        updateProbeStatus();

        dataCell = cell(numTableRows,2);
        row = 1;

        % 温度
        for ii = 1:tempChannels
            dataCell{row,1} = tempNames{ii};
            dataCell{row,2} = sprintf('%.2f ℃', lastTemp(ii));
            row = row + 1;
        end

        % 探头
        for ii = 1:3
            dataCell{row,1} = sprintf('探头%d',ii);
            dataCell{row,2} = sprintf('%.2f μm', lastProbe(ii));
            row = row + 1;
        end

        % XYZ
        xyzNames = {'X方向热误差','Y方向热误差','Z方向热误差'};
        if sampleNumber > 0
            xyzLatest = sampleXYZ(:,end);
        else
            xyzLatest = [NaN;NaN;NaN];
        end

        for ii = 1:3
            dataCell{row,1} = xyzNames{ii};
            if isnan(xyzLatest(ii))
                dataCell{row,2} = '--';
            else
                dataCell{row,2} = sprintf('%.3f μm', xyzLatest(ii));
            end
            row = row + 1;
        end

        % 球阀（新增）
        if ~isempty(full_valveCommand) && length(full_valveCommand) > 0
            dataCell{row,1} = '球阀指令';
            dataCell{row,2} = sprintf('%.1f %%', full_valveCommand(end));
            row = row + 1;

            dataCell{row,1} = '球阀反馈';
            if isnan(lastValvePosition)
                dataCell{row,2} = '--';
            else
                dataCell{row,2} = sprintf('%.1f %%', lastValvePosition);
            end
        end

        set(tbl,'Data',dataCell);

        % 更新球阀显示
        if isnan(lastValvePosition)
            set(valveDisplayText, 'String', '球阀开度: -- %');
        else
            set(valveDisplayText, 'String', ...
                sprintf('球阀开度: %.1f %%', lastValvePosition));
        end

        refreshActionButtons();
    end


%% ========================================================================
% 按钮有效状态（保持不变）
% ========================================================================

    function refreshActionButtons()
        if ~collecting || windowMode ~= 0
            set(btnZero,'Enable','off');
            set(btnSample,'Enable','off');
            return;
        end

        if isempty(lastProbe)
            set(btnZero,'Enable','off');
            set(btnSample,'Enable','off');
            return;
        end

        [OK,~] = checkProbeVector(lastProbe);

        if OK
            set(btnZero,'Enable','on');
            if zeroReady
                set(btnSample,'Enable','on');
            else
                set(btnSample,'Enable','off');
            end
        else
            set(btnZero,'Enable','off');
            set(btnSample,'Enable','off');
        end
    end


%% ========================================================================
% 更新图（扩展包含球阀曲线）
% ========================================================================

    function updatePlots()
        if isempty(full_time)
            return;
        end

        N = length(full_time);
        firstIndex = max(1, N-maxDisplayPoints+1);
        t = full_time(firstIndex:end);
        tempPlot = full_temp(:,firstIndex:end);
        probePlot = full_probe(:,firstIndex:end);

        % 温度
        for ii = 1:tempChannels
            set(hTemp(ii), 'XData', t, 'YData', tempPlot(ii,:));
        end

        allTemp = tempPlot(:);
        if ~isempty(allTemp)
            ymin = min(allTemp)-1;
            ymax = max(allTemp)+1;
            if ymax <= ymin
                ymax = ymin+5;
            end
            ylim(axTemp, [ymin ymax]);
        end

        % 探头
        for ii = 1:3
            set(hProbe(ii), 'XData', t, 'YData', probePlot(ii,:));
        end

        % 最近5分钟
        tNow = full_time(end);
        xLeft = max(0, tNow-300);
        xRight = max(60, tNow+10);
        xlim(axTemp, [xLeft xRight]);
        xlim(axProbe, [xLeft xRight]);

        % 球阀曲线（新增）
        if length(full_valveCommand) >= firstIndex
            valveCommandPlot = full_valveCommand(firstIndex:end);
            valveFeedbackPlot = full_valveFeedback(firstIndex:end);

            set(hValveCommand, 'XData', t, 'YData', valveCommandPlot);
            set(hValveFeedback, 'XData', t, 'YData', valveFeedbackPlot);
            xlim(axValve, [xLeft xRight]);
        end

        % XYZ离散样本（保持不变）
        if sampleNumber > 0 && calibrationEnabled
            sampleTime_min = sampleTime / 60;
            set(hXYZ(1), 'XData', sampleTime_min, 'YData', sampleXYZ(1,:));
            set(hXYZ(2), 'XData', sampleTime_min, 'YData', sampleXYZ(2,:));
            set(hXYZ(3), 'XData', sampleTime_min, 'YData', sampleXYZ(3,:));

            xyzAll = sampleXYZ(:);
            xyzAll = xyzAll(isfinite(xyzAll));

            if ~isempty(xyzAll)
                margin = max(5, 0.15 * (max(xyzAll)-min(xyzAll)) + 2);
                yMin = min(xyzAll)-margin;
                yMax = max(xyzAll)+margin;
                if yMax <= yMin
                    yMax = yMin+10;
                end
                ylim(axXYZ, [yMin yMax]);
            end

            xlim(axXYZ, [0, max(1, tNow/60+0.2)]);
        end
    end


%% ========================================================================
% 停止并保存（扩展保存球阀数据）
% ========================================================================

    function stopCallback(~,~)
        if ~collecting
            return;
        end

        collecting = false;

        set(statusText, 'String', '状态：停止采集，正在保存数据');

        % 停止Timer
        stopAndDeleteTimer();

        % 保存
        saveData();

        % GUI按钮
        set(btnStart,'Enable','on');
        set(btnStop,'Enable','off');
        set(btnZero,'Enable','off');
        set(btnSample,'Enable','off');

        set(statusText, 'String', '状态：实验结束');

        fprintf('\n🏁 本轮实验结束。\n');

        if pendingClose && ishandle(fig)
            delete(fig);
        end
    end


%% ========================================================================
% 保存全部中文Excel（扩展包含球阀和PID数据）
% ========================================================================

    function saveData()
        if isSaving
            return;
        end

        isSaving = true;

        fileName = sprintf('龙门机床热误差实验_PID控制_%s.xlsx', ...
            datestr(now, 'yyyymmdd_HHMMSS'));

        fprintf('\n=============================================\n');
        fprintf('开始保存Excel...\n');

        try
            % Sheet 1：连续采集数据（扩展包含球阀）
            continuousHeader = cell(1, 1+tempChannels+3+2);  % 新增2列球阀
            continuousHeader{1} = '时间/s';

            for ii = 1:tempChannels
                continuousHeader{1+ii} = sprintf('%s/℃', tempNames{ii});
            end

            continuousHeader{1+tempChannels+1} = '探头1/μm';
            continuousHeader{1+tempChannels+2} = '探头2/μm';
            continuousHeader{1+tempChannels+3} = '探头3/μm';
            continuousHeader{1+tempChannels+4} = '球阀指令/%';
            continuousHeader{1+tempChannels+5} = '球阀反馈/%';

            continuousMatrix = [...
                full_time', ...
                full_temp', ...
                full_probe', ...
                full_valveCommand', ...
                full_valveFeedback'];

            writecell(continuousHeader, fileName, ...
                'Sheet', '连续采集数据', 'Range', 'A1');
            writematrix(continuousMatrix, fileName, ...
                'Sheet', '连续采集数据', 'Range', 'A2');

            % Sheet 2：热误差建模样本（保持不变）
            if sampleNumber > 0
                sampleHeader = {...
                    '样本编号', '实验时间/s', '实验时间/min', ...
                    '测量起始时间/s', '测量结束时间/s'};

                for ii = 1:tempChannels
                    sampleHeader{end+1} = ...
                        sprintf('%s平均温度/℃', tempNames{ii});
                end

                sampleHeader = [sampleHeader, {...
                    '探头1平均值/μm', '探头2平均值/μm', '探头3平均值/μm', ...
                    '探头1相对冷态变化/μm', '探头2相对冷态变化/μm', ...
                    '探头3相对冷态变化/μm', ...
                    'X方向热误差/μm', 'Y方向热误差/μm', 'Z方向热误差/μm', ...
                    'X方向窗口标准差/μm', 'Y方向窗口标准差/μm', ...
                    'Z方向窗口标准差/μm'}];

                sampleNo = (1:sampleNumber)';
                sampleMatrix = [...
                    sampleNo, sampleTime', sampleTime'/60, ...
                    sampleWindowStart', sampleWindowEnd', ...
                    sampleTemp', sampleProbeMean', sampleDeltaProbe', ...
                    sampleXYZ', sampleStdXYZ'];

                writecell(sampleHeader, fileName, ...
                    'Sheet', '热误差建模样本', 'Range', 'A1');
                writematrix(sampleMatrix, fileName, ...
                    'Sheet', '热误差建模样本', 'Range', 'A2');
            end

            % Sheet 3-6：保持原有Sheet（温度测点、冷态零点、标定矩阵、实验参数）
            % 省略...与原代码相同

            % Sheet 7：PID控制参数（新增）
            pidCell = {...
                'PID参数','设置值'; ...
                'Kp', pidConfig.Kp; ...
                'Ki', pidConfig.Ki; ...
                'Kd', pidConfig.Kd; ...
                '目标位移/μm', pidConfig.setpoint; ...
                '死区/μm', pidConfig.deadband; ...
                '积分限幅', pidConfig.integralLimit; ...
                '输出最小/%', pidConfig.outputMin; ...
                '输出最大/%', pidConfig.outputMax};

            writecell(pidCell, fileName, 'Sheet', 'PID控制参数');

            fprintf('✅ Excel保存成功。\n');
            fprintf('文件：%s\n', fileName);
            fprintf('连续采样点：%d\n', length(full_time));
            fprintf('热误差建模样本：%d\n', sampleNumber);
            fprintf('=============================================\n');

        catch ME
            fprintf('\n❌ Excel保存失败：\n');
            fprintf('%s\n',ME.message);
        end

        isSaving = false;
    end


%% ========================================================================
% 其他辅助函数（保持不变）
% ========================================================================

    function switchToOfflineMode(reason)
        fprintf('\n=============================================\n');
        fprintf('⚠️ 自动进入离线模拟模式\n');
        fprintf('原因：%s\n',reason);
        fprintf('=============================================\n');

        simulateMode = true;
        m = [];
        simTick = 0;

        if ~calibrationEnabled
            C_xyz_from_probe = [...
                 1.000,  0.035, -0.020; ...
                -0.025,  1.000,  0.030; ...
                 0.018, -0.022,  1.000];
            calibrationEnabled = true;
            calibrationIsDemo = true;
        end

        updateModeText();
    end

    function updateModeText()
        if ~ishandle(modeText)
            return;
        end

        if simulateMode
            set(modeText, 'String', '当前模式：离线模拟模式', ...
                'BackgroundColor', [1.00 0.92 0.72]);
        else
            set(modeText, 'String', ...
                sprintf('当前模式：真实采集模式  %s', comPort), ...
                'BackgroundColor', [0.84 1.00 0.84]);
        end
    end

    function timerErrorCallback(~,event)
        fprintf('\n⚠️ 2秒采样定时器发生错误。\n');
        try
            fprintf('%s\n', event.Data.Message);
        catch
        end
    end

    function stopAndDeleteTimer()
        if isempty(acqTimer)
            return;
        end

        try
            if isvalid(acqTimer)
                stop(acqTimer);
                delete(acqTimer);
            end
        catch
        end

        acqTimer = [];
    end

    function closeFigure(~,~)
        if collecting
            pendingClose = true;
            stopCallback();
        else
            stopAndDeleteTimer();
            if ishandle(fig)
                delete(fig);
            end
        end
    end

    function cleanupResources()
        fprintf('\n🧹 正在清理程序资源...\n');
        stopAndDeleteTimer();

        try
            m = [];
        catch
        end

        try
            delete(instrfindall);
        catch
        end

        fprintf('✅ 清理完成。\n');
    end
