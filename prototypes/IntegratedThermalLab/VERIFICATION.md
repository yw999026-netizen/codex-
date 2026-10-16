# 验证记录 · 2026-10-16

本版本是离线模拟，真实串口、阀门写入和XYZ闭环未实现。网页与MATLAB热模型不同，不用于验证机床响应。

| 检查 | 实际执行及限制 |
|---|---|
| Node | 28项模型/契约断言通过：窗口、故障、基准冻结、位姿、串行队列、导出、实际时间、设备配置校验、指令分层、XYZ候选以及符号迁移金样本 |
| Chromium/Playwright | 本地静态服务下，自动三个热窗、手动AC、CSV下载、组别锁定、故障恢复、无效自动窗退出、配置页及页面JS错误检查通过 |
| MATLAB | 全仓库相关源文件语法解析与独立源码审查；没有MATLAB/Octave，GUI和所有MATLAB断言均未运行 |
| 真实设备 | 未连接；未核实设备表故意拒绝真实模式，无硬件验证结论 |

复跑：`node --test preview/tests/*.test.js`；`node preview/tests/browser-smoke.js`。浏览器脚本使用系统`/usr/bin/chromium`，仅测试依赖Playwright，网页自身无外部依赖。

MATLAB本机需运行`run_core_tests`和`run_contract_tests`。仓库另附`run_legacy_contract_tests`、`run_v3_correction_tests`。解析通过不能证明MATLAB R2021b运行通过。

演示矩阵与差分约定一起迁移为current-minus-baseline，独立保留迁移前固定输入/结果，检查原始探头、XYZ和窗口内标准差不变。此项说明代数兼容，不证明既有实测C曾经错误。C实际符号需现场标定，原MAT文件保持不变。

全仓库验证与尚未关闭的现场项见[修正结果](../../docs/repository-correction-results-20261016.md)。
