# API 资料与软件说明书

当前实验操作见 [API 实验步骤](../实验操作/API测量/README.md)，本轮方案见 [研究方案调整](../研究方案/API测量与预测冷却控制方案调整_20261026.md)。

本目录统一保存用户提供的 API 主轴测量系统资料与软件说明书。2026-10-26 已归档 5 份原始文档和 2 个软件快捷方式，保留原文件名、格式和字节内容。

## 使用教程

[本轮 API 测量实验步骤](../实验操作/API测量/README.md)：针对主轴停转、XYZ 运行后定点回测的现场操作 README，含预试验、正式测量循环及记录表。

[API 使用教程：Spindle Measurement System 与 SpindleModel](API使用教程_SpindleMeasurementSystem与SpindleModel.md)：根据原始手册整理安装、测量、热数据分析、模型点设置、温度传感器筛选与模型保存流程，并说明运行时间单位、位移列错标及现场待确认事项。

## 原始资料分类

| 文件夹 | 用途 | 当前归档状态 |
|---|---|---|
| [API资料](API资料) | API 主轴测量系统报价资料 | 已归档 1 份 PDF |
| [软件说明书](软件说明书) | SPN 安装与使用手册、主轴热变形建模软件说明书 | 已归档 2 份 PDF、2 份 DOC |
| [软件快捷方式](软件快捷方式) | 用户提供的软件入口，用于确认程序信息 | 已归档 2 个 LNK 文件 |

## 文件清单

| 文件 | 大小（字节） |
|---|---:|
| [API 主轴测量系统报价_20131122(3)(1).pdf](<API资料/API 主轴测量系统报价_20131122(3)(1).pdf>) | 1,657,239 |
| [SPN SW Installation manual.pdf](<软件说明书/SPN SW Installation manual.pdf>) | 1,757,253 |
| [SPN_MANUAL.doc](软件说明书/SPN_MANUAL.doc) | 7,535,616 |
| [SPN_MANUAL_41 _3_.pdf](<软件说明书/SPN_MANUAL_41 _3_.pdf>) | 4,464,342 |
| [主轴热变形建模软件使用说明书.doc](软件说明书/主轴热变形建模软件使用说明书.doc) | 1,202,688 |
| [Spindle Measurement System.lnk](<软件快捷方式/Spindle Measurement System.lnk>) | 1,391 |
| [SpindleModel.lnk](软件快捷方式/SpindleModel.lnk) | 1,798 |

快捷方式是 Windows 本机程序入口，不包含软件或安装包，也不保证在其他电脑上有效。`Spindle Measurement System.lnk` 的目标为 `C:\Program Files (x86)\Automated Precision, Inc\Spindle Measurement System\Spincheck.exe`；`SpindleModel.lnk` 中记录的程序路径为 `C:\Program Files (x86)\Spindle model\SpindleModel.exe`。已读取快捷方式信息，未执行其中的程序。

## 完整性校验

已逐份比对上传原文件与归档文件的 SHA-256，全部一致。校验值保存在 [SHA256SUMS](SHA256SUMS)，可在本目录运行 `sha256sum -c SHA256SUMS` 复核。
