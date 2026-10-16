# 20261009 实验数据质量记录

原始工作簿和 `ThreeProbeCalibration.mat` 均未修改。

`exclusions_20261009.json` 用原工作簿SHA-256、工作表“热误差建模样本”和原样本号定位。样本15已由用户确认有误，具体原因和确认日期没有充分记录，因此不补造。

- 原始窗口22个；排除样本15后剩21个**候选窗口**。
- `20261009/window_quality_register.csv` 保留22行及质量标记；`candidate_windows_excluding_15.csv` 只含21个候选。
- 其余窗口没有自动变为有效样本；历史窗口漂移、量程余量、复位及时间可比性仍需检查。
- 历史时间列按原值复制，不能反推出当时真实经过时间；不直接用于精确时滞辨识。
- 新统计、拟合或作图应使用排除策略，并记录其他质量筛选。旧分析若引用样本15，需重算相关结果；不自动改动使用其他标定数据生成的矩阵。

从仓库根目录复现（只读原工作簿，输出派生CSV）：

```bash
python -m pip install -r tools/requirements-quality.txt
python tools/quality_filter.py --input "热误差测量/实验数据-澳/龙门机床热误差实验_20261009(10.9上午第一组)_160435.xlsx" --policy data_quality/exclusions_20261009.json --output-dir work/quality_review
```

输入哈希或工作表不匹配、样本号重复或找不到已确认排除的样本时，工具拒绝应用策略，不按行号误删其他数据。
