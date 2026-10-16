# 仓库修正结果与验收范围 · 2026-10-16

已按用户“修正”指令实施可离线完成的代码、数据质量和文档修正，保存于独立修正分支。原main、原始工作簿、既有实测标定矩阵及其他工程资产保留。此记录区分源码修正、已执行离线验证和待本机/现场验收；不将10组问题视为全部硬件验收关闭。

## 逐项结果

| 编号 | 已落地修正 | 当前证据与未完成项 |
|---|---|---|
| R01 单总线 | 模板按物理设备身份校验地址、统一帧格式和来源；模拟请求串行。维护入口真实模式在打开端口前拒绝，旧多串口GUI限制为历史模拟 | Node校验/队列断言通过；空配置CLI退出2。真实适配器、超时重试/响应匹配及全线通信尚未实现/验收 |
| R02 18T与XYZ | 推荐入口统一18T、三原始探头、正式窗XYZ；旧17路类标为历史且停用连接，不补造T18。V3保留18曲线和原六表 | Node流程/导出通过；MATLAB断言和逐通道身份/缩放待本机、现场 |
| R03 时间与窗口 | V3用UTC及tic/toc，保留读起止、失败行和不可补齐的无效窗；不再用成功行号乘2s。截止窗先结算，窗外故障不污染已完成窗 | V3源码独立复核与语法解析通过；MATLAB运行待验。原型实际时间Node断言通过 |
| R04 唯一基准 | 同轮基准冻结；恢复保留基准、清除确认；换基准需新实验。V3各类记录携基准/标定ID，原型窗口与元数据记录对应身份 | Node冻结/恢复通过；V3完整GUI和MATLAB断言待运行 |
| R05 指令与反馈 | 请求/限幅/编码/发送/反馈分列；旧u单位明确未核实。阶跃模型与日志用同一限幅值，非法输入拒绝。MATLAB失败指令先记结构化事件，再进入故障；成功旧状态单独保留 | Node契约通过；两处审查发现已修并静态复核。MATLAB断言未执行；阀单位/边界/写应答/实际流量待现场 |
| R06 间歇XYZ | 不完整PID入口改为固定冷却模拟兼容启动；仅提供有效XYZ/身份/龄期候选检查，不由原始探头1驱动控制 | Node拒绝无效/超龄/无标定窗口通过。控制律、窗口去重执行、真实阀写入尚未实现；按辨识后再设计闭环 |
| R07 来源隔离 | 维护入口显式simulation、real拒绝；失败保留NaN和来源，不以模拟补真实失败；旧GUI模式锁定、历史标签 | Node故障与模式断言通过；MATLAB本机验收待做。独立历史标定/地址测试工具另见下文 |
| R08 入口分级 | 新start_lab；main_measurement转18T原型；Fixed调用完整V3；PID入口明确未实现闭环；旧自动补丁停用。研究/采集/使用说明同步 | 入口与依赖独立审查、41个.m语法解析通过；MATLAB启动/GUI/导出待本机 |
| R09 样本15 | SHA-256+表名+原样本号绑定排除，22行完整质量表与21行候选表，原因不明不补造。原始表、C均未改 | Python4项通过；派生文件可逐字节复现。其余21行未自动判合格；引用15的旧统计/模型需重新筛选计算 |
| R10 符号兼容 | 统一XYZ=C*(当前−基准)，保留实测C符号。演示C取反并同步MATLAB前向，网页独立H不变；元数据记录新约定 | Node迁移前金样本验证探头/XYZ/标准差不变；MATLAB迁移断言待运行，现场独立位移标定待做 |

机器可读状态见[修正登记CSV](repository-corrections-20261016.csv)；初始方法快照见[已批准计划](superpowers/plans/2026-10-16-repository-corrections.md)。历史计划中的0/0和待实施为编制当时状态。

## 已执行验证

- `node --test prototypes/IntegratedThermalLab/preview/tests/*.test.js`：28项通过，0失败。
- `python -m unittest discover -s tests -v`：4项通过，0失败。
- `node prototypes/IntegratedThermalLab/preview/tests/browser-smoke.js`：Chromium/Playwright本地静态服务下，自动≥3热窗、手动AC、CSV下载、组别锁定、故障恢复、无效自动窗停止、配置页及页面JS错误检查通过。已查看实际截图；网页不依赖外部前端服务。
- 未配置设备表CLI：预期退出2并报告未核实；不打开串口。完整配置通过字段检查也不启用真实驱动。
- `quality_filter.py`只读原工作簿生成22/21行派生表，与入库CSV/JSON逐字节相同；输入哈希再次一致。
- tree-sitter-matlab解析41个.m，无语法错误；`git diff --check`通过。
- 独立审查发现的截止顺序、阶跃限幅/记录和失败指令记录均已修正并回查。语法解析和静态回查不等于MATLAB运行验证。

原工作簿SHA-256：`0eeddecd7d21a7a878267d8a0eb23910d18e01d6b282257017cba806317f1ba2`；Git blob：`a3f8a1e43103491a903bee2984b335485d14ebf0`。原ThreeProbeCalibration.mat Git blob：`b81c587ffca080eea5309c64ca9c2bf89e47329d`。发布使用原main树增量更新，保留未修改CAD、实验表和其他资产。

## 本机与现场待验

本环境无MATLAB/Octave，以下均未实际运行：MATLAB R2021b GUI、定时器生命周期、Excel/CSV保存与失败重试，以及四组MATLAB断言。在仓库根目录运行：

```matlab
addpath(fullfile(pwd,'prototypes','IntegratedThermalLab','matlab'));
run_core_tests; run_contract_tests; run_legacy_contract_tests;
addpath(fullfile(pwd,'热误差测量'));
run_v3_correction_tests;
start_lab
```

V3保留5s等待与随后20s半开采样区间，至少10点；调度延时可能使样本不足而无效，这不是已经冻结的现场参数。原型2s等待/5点仅演示。两版合成热模型不同，不用于比较物理数值。三项确认只记录操作者声明，不验证实际停转、到位或角向复位。

真实接入按[设备核对表](../prototypes/IntegratedThermalLab/config/hardware_readiness.md)和[采集方案](../热误差测量/ThermalError_Acquisition_Plan_V1.md)执行：先协议和逐设备只读，再单总线耗时和冲突核验，再受控写入与反馈。不填猜测站号/阀单位/PID或断通信泵阀动作。当前无XYZ闭环、Shapley自动计算或完整异常退出恢复；正常停止导出不能代替断电保护。

`ThreeProbe_XYZ_Calibration_GUI.m`及`_select_delete`、`WC_Temp_Address_Test_Full.m`为保留的独立历史工具，可能打开真实串口，不属于当前模拟维护入口，不能与共享总线系统同时运行。其他代码片段和.txt复制件均为历史参考；修正未声称所有仓库文件都已成为统一驱动。

## 使用方式

先下载完整修正分支或软件ZIP。MATLAB从根目录运行`start_lab`；网页打开`prototypes/IntegratedThermalLab/preview/index.html`并点击自动演示。企业浏览器限制本地文件时，可用本地静态服务打开。GitHub源码页不会直接运行HTML。

软件ZIP不含大体积原始实验工作簿和CAD，派生质量表已包含；重新应用排除工具时，从完整仓库取得原始表。ZIP中的实测MAT文件为原版本副本，不代表新标定。

## 实施检查单

- [x] 可离线实施的代码、数据侧车及当前说明已更新。
- [x] 独立审查发现已修正并回查；可执行的Node/Python/浏览器检查通过。
- [x] 原始工作簿和既有标定文件保留，派生候选数据可复现。
- [ ] MATLAB R2021b启动、断言、GUI与导出验收。
- [ ] 设备表、真实适配器、流量/水温及受控写入验收。
- [ ] 动态辨识与间歇XYZ控制律、去重执行及实机闭环验收。
