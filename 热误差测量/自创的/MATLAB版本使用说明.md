# 兼容入口与历史草稿（2026-10-16）

推荐从仓库根目录运行start_lab，见[根README](../../README.md)。

| 文件 | 当前用途 |
|---|---|
| ThermalErrorControl_WithPID_V1.m | 固定冷却集成模拟。不是PID控制器，不使用运行中单探头原值调阀 |
| ThermalError_18T_3Probe_V3_Fixed.m | 调用父目录完整修正版V3，默认simulation |
| ThermalErrorControl_补充函数.m、快速修复代码片段.m | 历史片段，不是完整入口 |
| 应用修复.m | 旧补丁停用，避免覆盖已修正V3 |

原PID曾省略归零、窗口、保存等函数，不能称完整版本或说补充函数已包含。旧内容可在Git历史830212c4追溯，不机械拼接。

第一阶段固定冷却；真实设备未核实，位移闭环未启用。未来只接受停转回测后的有效XYZ窗口，需先完成动态辨识。MATLAB运行和硬件尚未验证。
