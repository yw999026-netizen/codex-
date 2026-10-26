"""从既有派生 CSV 复核论文表 2—4 和指定窗口增量；不改写任何输入。

仓库根目录运行：
    python 论文写作—无api/分析工具/verify_manuscript_metrics.py

仅使用 Python 标准库，JSON 输出到标准输出。
原 Excel 的窗口均值、标准差及矩阵复算仍由 analyze_rtest.py 完成。
"""
from pathlib import Path
import csv
import hashlib
import json
import math

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "论文写作—无api" / "分析结果"
WINDOWS = DATA / "Rtest_有效窗口原值与复算值.csv"
SUMMARY = DATA / "Rtest_四工况描述统计.csv"
EXPECTED_COUNTS = {"X": 14, "Y": 16, "Z": 17, "XYZ": 7}


def read_csv(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def value(row, key):
    result = float(row[key])
    if not math.isfinite(result):
        raise ValueError(f"非有限值：{key}")
    return result


def close(actual, expected, label, tol=1e-8):
    if not math.isclose(actual, expected, rel_tol=0, abs_tol=tol):
        raise ValueError(f"{label}: {actual} != {expected}")


def vector(row):
    return [value(row, f"{axis}_calc_um") for axis in "xyz"]


def norm(row):
    return math.sqrt(sum(item * item for item in vector(row)))


def interval(start, end):
    return {
        "start_sample": int(start["sample_id"]),
        "end_sample": int(end["sample_id"]),
        "start_min": value(start, "elapsed_min"),
        "end_min": value(end, "elapsed_min"),
        "delta_xyz_um": [b - a for a, b in zip(vector(start), vector(end))],
        "delta_norm_um": norm(end) - norm(start),
    }


def main():
    before = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
              for path in (WINDOWS, SUMMARY)}
    rows = read_csv(WINDOWS)
    summaries = read_csv(SUMMARY)
    if len(rows) != 54 or len(summaries) != 4:
        raise ValueError("数据规模已改变，请重新审阅正文")

    summary_by_case = {row["case"]: row for row in summaries}
    if len(summary_by_case) != 4 or set(summary_by_case) != set(EXPECTED_COUNTS):
        raise ValueError("描述统计工况缺失或重复")
    if set(row["case"] for row in rows) != set(EXPECTED_COUNTS):
        raise ValueError("窗口工况集合发生变化")

    mismatches, records = [], []
    for case, expected_count in EXPECTED_COUNTS.items():
        group = sorted((r for r in rows if r["case"] == case),
                       key=lambda r: value(r, "elapsed_s"))
        if len(group) != expected_count:
            raise ValueError(f"{case} 窗口数已改变")
        if len({r["sample_id"] for r in group}) != len(group):
            raise ValueError(f"{case} 样本号重复")
        for row in group:
            if int(row["n_window"]) != 5:
                raise ValueError("窗口点数已改变")
            close(value(row, "elapsed_s") / 60,
                  value(row, "elapsed_min"), f"{case} 时间换算")
            close((value(row, "window_start_s") + value(row, "window_end_s")) / 2,
                  value(row, "elapsed_s"), f"{case} 窗口中心时间")
            close(norm(row), value(row, "norm_calc_um"), f"{case} 三维幅值")
            for axis in "xyz":
                delta = value(row, f"{axis}_stored_um") - value(row, f"{axis}_calc_um")
                if abs(delta) > 1e-6:
                    mismatches.append({
                        "case": case, "sample": int(row["sample_id"]),
                        "axis": axis.upper(), "stored_minus_calc_um": delta,
                    })

        peak = max(group, key=norm)
        last = group[-1]
        summary = summary_by_case[case]
        close(len(group), value(summary, "n_samples"), f"{case} 样本数")
        close(norm(peak), value(summary, "observed_max_norm_calc_um"), f"{case} 最大值")
        close(int(peak["sample_id"]), value(summary, "max_calc_sample_id"), f"{case} 峰值样本")
        close(norm(last), value(summary, "last_norm_calc_um"), f"{case} 末点幅值")
        for axis, component in zip("xyz", vector(last)):
            close(component, value(summary, f"last_{axis}_calc_um"), f"{case} 末点分量")

        records.append({
            "case": case, "n_windows": len(group),
            "first_window_min": value(group[0], "elapsed_min"),
            "last_window_min": value(last, "elapsed_min"),
            "observed_max_sample": int(peak["sample_id"]),
            "observed_max_time_min": value(peak, "elapsed_min"),
            "observed_max_norm_um": norm(peak),
            "last_xyz_um": vector(last), "last_norm_um": norm(last),
            "last_two_windows": interval(group[-2], last),
        })

    if len(mismatches) != 1:
        raise ValueError("原值/复算差异集合已改变")
    issue = mismatches[0]
    if (issue["case"], issue["sample"], issue["axis"]) != ("XYZ", 7, "Y"):
        raise ValueError("差异样本已改变")
    close(issue["stored_minus_calc_um"], 30, "XYZ 末点 Y 差异", tol=1e-6)

    x_rows = {int(r["sample_id"]): r for r in rows if r["case"] == "X"}
    x_selected = interval(x_rows[22], x_rows[25])
    after = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
             for path in (WINDOWS, SUMMARY)}
    if before != after:
        raise RuntimeError("输入校验值发生变化")

    print(json.dumps({
        "scope": "复核既有派生 CSV 的正文数值；不代替原 Excel 或硬件验证",
        "sources_sha256": before, "records": records,
        "stored_vs_recomputed_differences": mismatches,
        "X_sample_22_to_25": x_selected,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
