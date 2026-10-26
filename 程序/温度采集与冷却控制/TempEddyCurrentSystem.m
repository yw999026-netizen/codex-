% 温度和电涡流测量系统
% 作者：Claude
% 日期：2026-10-07

classdef TempEddyCurrentSystem < handle
    properties
        % Modbus通信
        modbusObj
        serialPort = 'COM4'
        baudRate = 9600
        
        % 温度传感器配置
        tempSlaveIDs = [1, 2, 3]  % Modbus从机ID
        
        % 传感器位置标签
        sensorLabels
        
        % 数据存储
        temperatureData
        eddyCurrentData
        timeStamps
        
        % 采集参数
        samplingInterval = 1  % 采样间隔（秒）
        isRunning = false
        
        % 图形界面
        fig
        tempAxes
        eddyAxes
        dataTable
    end
    
    methods
        function obj = TempEddyCurrentSystem()
            % 构造函数 - 初始化系统
            obj.initSensorLabels();
            obj.initData();
            obj.initGUI();
        end
        
        function initSensorLabels(obj)
            % 初始化传感器位置标签
            obj.sensorLabels = {
                % ID1的8个传感器
                'ID1-1: 床身右侧', ...
                'ID1-2: 立柱左侧', ...
                'ID1-3: 立柱右侧', ...
                'ID1-4: 横梁上端', ...
                'ID1-5: 环境温度', ...
                'ID1-6: Z轴前端轴承', ...
                'ID1-7: Z轴后端轴承', ...
                'ID1-8: X轴前端', ...
                % ID2的8个传感器
                'ID2-1: Y2+前端', ...
                'ID2-2: Y1+前端', ...
                'ID2-3: Y1+后端', ...
                'ID2-4: Z+螺母', ...
                'ID2-5: Y2+螺母', ...
                'ID2-6: Y1+螺母', ...
                'ID2-7: Y2+后端', ...
                'ID2-8: X轴螺母', ...
                % ID3的1个传感器
                'ID3-1: X轴后端轴承'
            };
        end
        
        function initData(obj)
            % 初始化数据存储
            obj.temperatureData = [];
            obj.eddyCurrentData = [];
            obj.timeStamps = [];
        end
        
        function success = connectModbus(obj)
            % 连接Modbus RTU设备
            try
                % 清除已存在的串口对象
                delete(instrfind('Port', obj.serialPort));
                
                % 创建Modbus RTU对象
                obj.modbusObj = modbus('serialrtu', obj.serialPort, ...
                    'BaudRate', obj.baudRate, ...
                    'DataBits', 8, ...
                    'Parity', 'none', ...
                    'StopBits', 1, ...
                    'Timeout', 2);
                
                fprintf('Modbus RTU连接成功 - 端口: %s\n', obj.serialPort);
                success = true;
            catch ME
                fprintf('Modbus连接失败: %s\n', ME.message);
                success = false;
            end
        end
        
        function temps = readTemperatures(obj)
            % 读取所有温度传感器数据
            temps = zeros(1, 17);  % 17路温度
            
            try
                % 读取ID1的8个传感器（保持寄存器地址0开始）
                data1 = read(obj.modbusObj, 'holdingregs', 0, 8, 1);
                temps(1:8) = double(data1) / 10;  % PT100通常需要除以10
                
                % 读取ID2的8个传感器
                data2 = read(obj.modbusObj, 'holdingregs', 0, 8, 2);
                temps(9:16) = double(data2) / 10;
                
                % 读取ID3的1个传感器
                data3 = read(obj.modbusObj, 'holdingregs', 0, 1, 3);
                temps(17) = double(data3) / 10;
                
            catch ME
                fprintf('温度读取错误: %s\n', ME.message);
                temps = nan(1, 17);
            end
        end
        
        function [x, y, z] = readEddyCurrent(obj)
            % 读取三路电涡流传感器数据（基于Rtest三坐标法）
            % 假设电涡流传感器通过Modbus从机ID4读取
            
            try
                % 读取三个电涡流传感器值（寄存器地址根据实际情况调整）
                data = read(obj.modbusObj, 'holdingregs', 100, 3, 4);
                
                % 转换为实际位移值（单位：μm）
                x = double(data(1)) / 100;  % X方向位移
                y = double(data(2)) / 100;  % Y方向位移
                z = double(data(3)) / 100;  % Z方向位移
                
            catch ME
                fprintf('电涡流读取错误: %s\n', ME.message);
                x = nan;
                y = nan;
                z = nan;
            end
        end
        
        function initGUI(obj)
            % 初始化图形用户界面
            obj.fig = figure('Name', '温度与电涡流测量系统', ...
                'NumberTitle', 'off', ...
                'Position', [100, 100, 1200, 800], ...
                'CloseRequestFcn', @(src, evt) obj.closeGUI());
            
            % 温度曲线显示区域
            obj.tempAxes = subplot(2, 2, [1, 2]);
            title('温度实时曲线');
            xlabel('时间 (秒)');
            ylabel('温度 (°C)');
            grid on;
            hold on;
            
            % 电涡流显示区域
            obj.eddyAxes = subplot(2, 2, 3);
            title('电涡流三坐标位移');
            xlabel('测量点');
            ylabel('位移 (μm)');
            grid on;
            
            % 数据表格
            uicontrol('Style', 'text', ...
                'String', '当前测量值', ...
                'Position', [650, 350, 500, 30], ...
                'FontSize', 12, ...
                'FontWeight', 'bold', ...
                'HorizontalAlignment', 'left');
            
            obj.dataTable = uitable(obj.fig, ...
                'Position', [650, 50, 500, 300], ...
                'ColumnName', {'传感器', '数值'}, ...
                'ColumnWidth', {300, 150});
            
            % 控制按钮
            uicontrol('Style', 'pushbutton', ...
                'String', '开始采集', ...
                'Position', [50, 20, 100, 40], ...
                'Callback', @(src, evt) obj.startAcquisition());
            
            uicontrol('Style', 'pushbutton', ...
                'String', '停止采集', ...
                'Position', [170, 20, 100, 40], ...
                'Callback', @(src, evt) obj.stopAcquisition());
            
            uicontrol('Style', 'pushbutton', ...
                'String', '保存数据', ...
                'Position', [290, 20, 100, 40], ...
                'Callback', @(src, evt) obj.saveData());
            
            uicontrol('Style', 'pushbutton', ...
                'String', '清除数据', ...
                'Position', [410, 20, 100, 40], ...
                'Callback', @(src, evt) obj.clearData());
        end
        
        function startAcquisition(obj)
            % 开始数据采集
            if ~obj.isRunning
                if obj.connectModbus()
                    obj.isRunning = true;
                    fprintf('开始数据采集...\n');
                    
                    % 启动采集循环
                    while obj.isRunning
                        % 读取数据
                        temps = obj.readTemperatures();
                        [x, y, z] = obj.readEddyCurrent();
                        
                        % 存储数据
                        obj.temperatureData = [obj.temperatureData; temps];
                        obj.eddyCurrentData = [obj.eddyCurrentData; x, y, z];
                        obj.timeStamps = [obj.timeStamps; datetime('now')];
                        
                        % 更新显示
                        obj.updateDisplay();
                        
                        % 等待采样间隔
                        pause(obj.samplingInterval);
                        
                        % 处理GUI事件
                        drawnow;
                    end
                else
                    errordlg('Modbus连接失败，请检查串口设置！', '连接错误');
                end
            end
        end
        
        function stopAcquisition(obj)
            % 停止数据采集
            obj.isRunning = false;
            fprintf('停止数据采集\n');
        end
        
        function updateDisplay(obj)
            % 更新界面显示
            if isempty(obj.temperatureData)
                return;
            end
            
            % 更新温度曲线
            axes(obj.tempAxes);
            cla;
            
            numPoints = size(obj.temperatureData, 1);
            timeVector = (1:numPoints) * obj.samplingInterval;
            
            % 只显示关键传感器的曲线（避免太拥挤）
            keyIndices = [5, 6, 7, 8, 17];  % 环境温度和几个关键轴承
            plot(timeVector, obj.temperatureData(:, keyIndices), 'LineWidth', 1.5);
            legend(obj.sensorLabels(keyIndices), 'Location', 'best');
            xlabel('时间 (秒)');
            ylabel('温度 (°C)');
            title('温度实时曲线');
            grid on;
            
            % 更新电涡流显示
            axes(obj.eddyAxes);
            cla;
            
            if ~isempty(obj.eddyCurrentData)
                latestEddy = obj.eddyCurrentData(end, :);
                bar(latestEddy);
                set(gca, 'XTickLabel', {'X轴', 'Y轴', 'Z轴'});
                ylabel('位移 (μm)');
                title('电涡流三坐标位移');
                grid on;
            end
            
            % 更新数据表格
            if ~isempty(obj.temperatureData)
                latestTemp = obj.temperatureData(end, :);
                latestEddy = obj.eddyCurrentData(end, :);
                
                tableData = cell(20, 2);
                
                % 温度数据
                for i = 1:17
                    tableData{i, 1} = obj.sensorLabels{i};
                    tableData{i, 2} = sprintf('%.2f °C', latestTemp(i));
                end
                
                % 电涡流数据
                tableData{18, 1} = '电涡流 X轴';
                tableData{18, 2} = sprintf('%.3f μm', latestEddy(1));
                tableData{19, 1} = '电涡流 Y轴';
                tableData{19, 2} = sprintf('%.3f μm', latestEddy(2));
                tableData{20, 1} = '电涡流 Z轴';
                tableData{20, 2} = sprintf('%.3f μm', latestEddy(3));
                
                set(obj.dataTable, 'Data', tableData);
            end
        end
        
        function saveData(obj)
            % 保存数据到文件
            if isempty(obj.temperatureData)
                warndlg('没有数据可保存！', '警告');
                return;
            end
            
            [fileName, pathName] = uiputfile('*.mat', '保存数据文件');
            if fileName ~= 0
                sensorLabels = obj.sensorLabels;
                temperatureData = obj.temperatureData;
                eddyCurrentData = obj.eddyCurrentData;
                timeStamps = obj.timeStamps;
                
                save(fullfile(pathName, fileName), ...
                    'sensorLabels', 'temperatureData', ...
                    'eddyCurrentData', 'timeStamps');
                
                % 同时保存为CSV格式
                [~, name, ~] = fileparts(fileName);
                csvFileName = fullfile(pathName, [name, '.csv']);
                obj.exportToCSV(csvFileName);
                
                msgbox('数据保存成功！', '成功');
            end
        end
        
        function exportToCSV(obj, fileName)
            % 导出数据到CSV文件
            fid = fopen(fileName, 'w');
            
            % 写入表头
            fprintf(fid, '时间,');
            for i = 1:17
                fprintf(fid, '%s,', obj.sensorLabels{i});
            end
            fprintf(fid, '电涡流X,电涡流Y,电涡流Z\n');
            
            % 写入数据
            for i = 1:size(obj.temperatureData, 1)
                fprintf(fid, '%s,', datestr(obj.timeStamps(i), 'yyyy-mm-dd HH:MM:SS'));
                fprintf(fid, '%.2f,', obj.temperatureData(i, :));
                fprintf(fid, '%.3f,%.3f,%.3f\n', obj.eddyCurrentData(i, :));
            end
            
            fclose(fid);
        end
        
        function clearData(obj)
            % 清除数据
            obj.initData();
            cla(obj.tempAxes);
            cla(obj.eddyAxes);
            set(obj.dataTable, 'Data', {});
            fprintf('数据已清除\n');
        end
        
        function closeGUI(obj)
            % 关闭GUI时的清理工作
            obj.stopAcquisition();
            
            if ~isempty(obj.modbusObj)
                try
                    clear obj.modbusObj;
                catch
                end
            end
            
            delete(obj.fig);
        end
    end
end