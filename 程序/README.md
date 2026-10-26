# MATLAB 程序入口、版本和依赖

这里保留已有采集、控制、标定及仿真程序。当前 API 实验通过厂家的 Spindle Measurement System 采集，尚没有经过真实 API 文件验证的 MATLAB 导入程序或实时预测冷却控制入口。

## 按任务找程序

| 目录 | 入口或文件 | 用途与状态 |
|---|---|---|
| [三探头测量](三探头测量/) | `ThermalError_18T_3Probe_V3.m` | 原 18 温度/3 电涡流采集；属于旧测量系统 |
| 三探头测量 | `ThreeProbe_XYZ_Calibration_GUI.m`、`ThreeProbe_XYZ_Calibration_GUI_select_delete.m` | 原三探头标定及选点删除版本；输出/读取同目录 `ThreeProbeCalibration.mat` |
| [修复与 PID 草稿](三探头测量/修复与PID草稿/) | Fixed、PID、补充函数、修复脚本及说明 | 未经本次运行验证的历史修改，不作为默认运行入口 |
| [温度采集与冷却控制](温度采集与冷却控制/) | `main_measurement.m`、`TempEddyCurrentSystem.m`、`SystemConfig.m` | 一套旧温度/电涡流入口，注释为 17 温度/3 位移；配置与 18 温度 V3 不同，需核对实际使用情况 |
| 温度采集与冷却控制 | `ADRC_Active_Control_GUI_Dark_Final.m` | 六阀温度反馈控制参考；尚未接入 API 位移或预测模型 |
| 温度采集与冷却控制 | `StepResponse_Exp_GUI_WC_Temp_Final.m` | 旧阶跃响应实验入口 |
| 温度采集与冷却控制 | `WC_Temp_Address_Test_Full.m` | 水冷机地址测试程序，涉及硬件通信 |
| [水冷控制历史版本](水冷控制历史版本/) | `mpc_Control_GUI_WC_Temp_Final.m`、`ADRC_Active_Control_GUI_WC_Temp.m`、`StepResponse_Exp_GUI_WC_Temp_Final.m` | 原双层“程序加水冷温度”目录中的代码，保留历史版本；不由文件名推断已经验证 |
| [仿真示例](仿真示例/) | `one_steep.m`、`two_step.m`、`decoupling_test.m` | 仿真与算法学习参考，不能作为实机辨识结果或已完成控制验证 |

## 运行前的依赖与路径

- MATLAB 版本尚待现场确认。部分代码使用 `modbus`、timer、GUI 及 Excel 读写；旧 `main_measurement.m` 检查 Instrument Control Toolbox。具体还需按选定入口和本机 MATLAB 环境核对，未据代码存在就宣称兼容。
- 打开旧 V3 或标定程序时，将 MATLAB 当前目录设为 [三探头测量](三探头测量/)，保证相对名 `ThreeProbeCalibration.mat` 可找到。其内容适用于旧系统，不用于 API 装置。
- `main_measurement.m` 与其类文件、配置文件仍放在同目录。运行该入口时将当前目录设为 [温度采集与冷却控制](温度采集与冷却控制/)。
- 多个目录存在同名阶跃程序，历史 ADRC 的文件名与首函数名称也有不一致；Fixed/PID 草稿另有自身依赖。不要对整个仓库执行 `addpath(genpath(...))` 后凭短名称启动，先选定具体目录，用 `which 函数名 -all` 核对来源。
- 旧修复脚本 `应用修复.m` 按当前目录读取原 V3 并写出 Fixed 文件；如研究该补丁，应在副本工作区按其说明核对源/目标路径，避免覆盖已有参考版本。其默认行为未因整理而修改。
- 通信、阀门与水冷机程序涉及设备操作，必须先核对现场接口、单位、标定及参数。仓库整理没有改写这些算法或地址。
- 历史 Excel 已归类到 [实验数据](../实验数据/README.md)。这些程序多数按 MATLAB 当前目录写新结果；运行时使用独立实验工作目录并明确代码搜索路径，避免覆盖已归档原文件。涉及相对标定名时，另行选择/复制本轮适用标定并记录来源，不能随意换用现有 `.mat`。

## 下一步开发

API 原始解析和双温度源合并需真实文件样例；预测控制需有效模型点数据、动态辨识和独立验证，见 [当前方案](../研究方案/API测量与预测冷却控制方案调整_20261026.md)。现有代码保留供适配参考，本次未执行 MATLAB 或硬件验证。
