# 龙门机床热误差与分区冷却研究

以A＝床身、B＝立柱、C＝横梁的冷却干预研究固定检测位三维相对热位移改善，各区两支路，共八组合。测量保留主轴等热影响。当前兼容目标为MATLAB R2021b。

2026-10-16已按[修正登记表](docs/repository-corrections-20261016.csv)实施可离线修正，见[修正结果与验证范围](docs/repository-correction-results-20261016.md)。真实设备地址、协议、单位和动态参数待核实，当前维护入口不提供未核实的真实采集/控阀。

## 当前入口

| 入口 | 作用与状态 |
|---|---|
| `start_lab` | 推荐MATLAB入口：18温度、3探头、三区六支路统一模拟；基础MATLAB，无需通信工具箱 |
| [网页演示](prototypes/IntegratedThermalLab/preview/index.html) | 下载程序包后打开本地HTML，点自动演示；GitHub源码页本身不是在线运行界面 |
| `热误差测量/ThermalError_18T_3Probe_V3.m` | 保留完整V3GUI，修正实际时间、唯一基准、有效窗口；默认simulation，real在打开端口前拒绝 |
| `温度位移采集/main_measurement.m` | 兼容启动统一18通道模拟，不再启动17通道历史类 |
| `热误差测量/自创的/ThermalError_18T_3Probe_V3_Fixed.m` | 调用父目录完整修正版V3，避免复制残缺补丁 |
| `热误差测量/自创的/ThermalErrorControl_WithPID_V1.m` | 固定冷却模拟兼容入口；不是已实现PID，位移闭环未启用 |

在仓库根目录运行：

```matlab
start_lab
% 或查看保留的V3界面：
addpath(fullfile(pwd,'热误差测量'));
ThermalError_18T_3Probe_V3
```

V3保留5s等待、20s实际截止和至少10点的旧门槛，点数不足如实无效；这些不是已冻结现场参数。统一原型使用2s等待、5点演示。两版合成热模型不同，不能互相比数值证明机床响应。正式取数必须实际停转、同向到位、独立角向复位，勾选框仅记录确认，不控制CNC。

位移差统一为 `XYZ = C × (当前探头 − 本轮冷态基准)`。原型矩阵和前向已等价迁移，既有实测标定文件未改。标定零位与每轮基准分别保存。V3从自身目录读取ThreeProbeCalibration.mat，缺失时XYZ缺失，不自动启用演示C。

## 历史程序与片段

旧TempEddyCurrentSystem/SystemConfig为17路历史协议参考，已停用原硬件连接。ADRC/阶跃/MPC GUI仅保留独立温控模拟，真实多串口模式拒绝，模拟模式锁定，日志带来源和实际时间；历史数值u不代表核实后的百分比或角度。one_steep/two_step/decoupling_test三个旧直写脚本已停用。其他独立标定GUI及WC_Temp_Address_Test_Full保留历史工具，可能打开串口，不属于维护的模拟入口；不要与单总线系统同时运行。

自创的目录中补充函数和快速修复片段是历史参考，不单独启动或拼接覆盖当前程序；旧自动补丁已停用。原始内容可由Git历史追溯。不再承诺fixedSpacing保证严格2秒、不丢点或旧PID草稿完整可运行。

## 数据与设备准备

- [样本15排除策略与派生数据](data_quality/README.md)：原表保留，22个窗口排除15后剩21个候选，未自动判合格。
- [设备表模板](prototypes/IntegratedThermalLab/config/device_map_template.csv)：18温度为8+8+2，三探头与六支路分别登记；站号、寄存器与阀门单位未核实则空白。
- [接入核对](prototypes/IntegratedThermalLab/config/hardware_readiness.md)：单RS485、单串口、唯一通信所有者；同总线不同物理设备地址唯一，同一设备多个信号可共享站号。

离线校验模板（因未配置，应以退出码2报告未核实）：

```bash
node prototypes/IntegratedThermalLab/preview/validate-device-map.js prototypes/IntegratedThermalLab/config/device_map_template.csv
```

字段校验通过也不启用真实适配器。请求、限幅、编码、发送结果和反馈分开；没有实测流量/水温则缺失或人工记录。断通信动作和PID增益不凭旧代码猜测。

## 验证

```bash
node --test prototypes/IntegratedThermalLab/preview/tests/*.test.js
node prototypes/IntegratedThermalLab/preview/tests/browser-smoke.js
python -m unittest discover -s tests -v
```

浏览器测试需要Playwright/Chromium；界面本身没有第三方前端依赖。本环境无MATLAB/Octave，以下脚本及GUI需本机运行，语法解析不等于运行通过：

```matlab
addpath(fullfile(pwd,'prototypes','IntegratedThermalLab','matlab'));
run_core_tests; run_contract_tests; run_legacy_contract_tests;
addpath(fullfile(pwd,'热误差测量'));
run_v3_correction_tests;
```

当前主要保留内存记录，正常停止/导出时写盘；异常退出自动恢复尚未完成，不承诺整轮抗断电保存。

## 研究方案

- [当前研究总方案](研究方案/论文研究内容与技术路线.md)：测量边界、八组合、归因和间歇反馈。
- [三因素设计评估](研究方案/三因素全因子设计与热主动控制思路评估.md)：历史探索和后续路线。
- [ANSYS补充](研究方案/分区冷却归因与ANSYS流量筛选补充_20261013.md)：历史数据和仿真；样本15状态已同步。
- [采集方案](热误差测量/ThermalError_Acquisition_Plan_V1.md)：单总线、窗口和现场待确认项。
- [已批准修正计划](docs/superpowers/plans/2026-10-16-repository-corrections.md)：初始登记；实际状态以结果与CSV为准。
