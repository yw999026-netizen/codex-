"""只读复核四份 R-test 工作簿，保留原值/复算值，不推断停机分段。"""
from pathlib import Path
import csv
import hashlib
import json

import numpy as np
import openpyxl

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / '实验数据/热误差/20261018-20261021_无水冷四工况'
OUT = ROOT / '论文写作—无api/分析结果'


def write_csv(name, rows):
    with (OUT / name).open('w', encoding='utf-8-sig', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)


def main():
    OUT.mkdir(exist_ok=True)
    samples, summaries, issues, sources = [], [], [], []
    cases = [('X', 'X轴动（V_26mm-45mm）.xlsx'),
             ('Y', 'Y轴动（V_26mm）.xlsx'),
             ('Z', 'Z轴动（V_59.5mm）.xlsx'), ('XYZ', 'XYZ联动.xlsx')]
    for case, name in cases:
        path = DATA / name
        before = hashlib.sha256(path.read_bytes()).hexdigest()
        book = openpyxl.load_workbook(path, data_only=True, read_only=True)
        zero = np.array([r[1] for r in list(book['冷态零点'].values)[1:]], float)
        matrix = np.array([r[1:4] for r in list(book['三探头标定矩阵'].values)[1:]], float)
        rows = list(book['热误差建模样本'].values)
        head = list(rows[0])
        cont = list(book['连续采集数据'].values)
        raw = np.asarray(cont[1:], float)
        local_samples = []
        for excel_row, row in enumerate(rows[1:], start=2):
            if row[0] is None:
                continue
            get = lambda key: row[head.index(key)]
            means = np.array([get(f'探头{i}平均值/μm') for i in (1, 2, 3)], float)
            delta = np.array([get(f'探头{i}相对冷态变化/μm') for i in (1, 2, 3)], float)
            assert np.allclose(means-zero, delta, atol=1e-8, rtol=0), (case, row[0], '冷态差值不一致')
            stored = np.array([get(f'{a}方向热误差/μm') for a in 'XYZ'], float)
            calc = matrix @ delta
            start, end = get('测量起始时间/s'), get('测量结束时间/s')
            window = raw[(raw[:, 0] >= start) & (raw[:, 0] <= end)]
            assert len(window) == 5, (case, row[0], '窗口点数')
            assert np.allclose(window[:, 19:22].mean(axis=0), means, atol=1e-8, rtol=0)
            window_xyz = (window[:, 19:22]-zero) @ matrix.T
            saved_std = np.array([get(f'{a}方向窗口标准差/μm') for a in 'XYZ'], float)
            assert np.allclose(window_xyz.std(axis=0, ddof=1), saved_std, atol=1e-8, rtol=0)
            mismatch = bool(np.any(np.abs(stored-calc) > 1e-6))
            for a, value, expected in zip('XYZ', stored, calc):
                if abs(value-expected) > 1e-6:
                    issues.append(dict(case=case, file=name, sheet='热误差建模样本',
                                       excel_row=excel_row, sample_id=row[0], axis=a,
                                       stored_um=value, recalculated_um=expected,
                                       stored_minus_recalculated_um=value-expected,
                                       status='用户确认无人为加值；原值与矩阵复算不一致，原因待追溯；不覆盖原文件'))
            record = dict(case=case, source=name, excel_row=excel_row, sample_id=row[0],
                          elapsed_s=get('实验时间/s'), elapsed_min=get('实验时间/min'),
                          window_start_s=start, window_end_s=end, n_window=len(window),
                          phase='待实验记录确认',
                          x_stored_um=stored[0], y_stored_um=stored[1], z_stored_um=stored[2],
                          x_calc_um=calc[0], y_calc_um=calc[1], z_calc_um=calc[2],
                          norm_stored_um=float(np.linalg.norm(stored)),
                          norm_calc_um=float(np.linalg.norm(calc)),
                          requires_review=mismatch,
                          window_probe_max_abs_um=float(np.abs(window[:, 19:22]).max()))
            samples.append(record)
            local_samples.append(record)
        recalc = np.array([[r[f'{a}_calc_um'] for a in 'xyz'] for r in local_samples])
        stored_norm = np.array([r['norm_stored_um'] for r in local_samples])
        norms = np.linalg.norm(recalc, axis=1)
        peak = int(norms.argmax())
        summaries.append(dict(case=case, source=name, continuous_rows=len(raw),
                              recorded_end_min=float(raw[-1, 0]/60), n_samples=len(local_samples),
                              n_inconsistent_samples=sum(r['requires_review'] for r in local_samples),
                              ambient_first_C=raw[0, 5], ambient_last_C=raw[-1, 5],
                              observed_max_norm_stored_um=float(stored_norm.max()),
                              observed_max_norm_calc_um=float(norms.max()),
                              max_calc_sample_id=local_samples[peak]['sample_id'],
                              max_calc_time_min=local_samples[peak]['elapsed_min'],
                              last_x_calc_um=recalc[-1, 0], last_y_calc_um=recalc[-1, 1],
                              last_z_calc_um=recalc[-1, 2],
                              last_norm_stored_um=local_samples[-1]['norm_stored_um'],
                              last_norm_calc_um=float(norms[-1]),
                              rms_sample_stored_um=float(np.sqrt(np.mean(stored_norm**2))),
                              rms_sample_calc_um=float(np.sqrt(np.mean(norms**2))),
                              rms_scope='不等间隔全部已存窗口；仅描述本记录，不作工况优劣排序',
                              raw_probe_rows_over_100=int(np.any(np.abs(raw[:, 19:22]) > 100, axis=1).sum()),
                              matrix_condition_2=float(np.linalg.cond(matrix))))
        book.close()
        after = hashlib.sha256(path.read_bytes()).hexdigest()
        assert before == after, name
        sources.append(dict(file=str(path.relative_to(ROOT)), sha256=before))
    assert len(samples) == 54
    write_csv('Rtest_有效窗口原值与复算值.csv', samples)
    write_csv('Rtest_四工况描述统计.csv', summaries)
    if issues:
        write_csv('Rtest_计算差异清单.csv', issues)
    (OUT/'Rtest_原文件校验.json').write_text(json.dumps(sources, ensure_ascii=False, indent=2)+'\n')
    plot_samples(samples)
    print(json.dumps(dict(summaries=summaries, issues=issues), ensure_ascii=False, indent=2))


def plot_samples(samples):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(2, 2, figsize=(10, 6.7), sharey=True)
    for ax, case in zip(axes.flat, ['X', 'Y', 'Z', 'XYZ']):
        items = [r for r in samples if r['case'] == case]
        for axis, color in zip('xyz', ['#d95f02', '#1b70b4', '#238b45']):
            ax.scatter([r['elapsed_min'] for r in items],
                       [r[f'{axis}_stored_um'] for r in items],
                       s=23, color=color, label=f'{axis.upper()} stored')
        for r in items:
            if r['requires_review']:
                ax.scatter(r['elapsed_min'], r['y_calc_um'], s=65, color='black',
                           marker='x', label='Y recalculated (review)')
        ax.axhline(0, color='gray', lw=.65)
        ax.set(title=f'{case} feed record with spindle rotation',
               xlabel='Recorded elapsed time (min)', ylabel='Relative displacement (μm)')
        ax.grid(alpha=.15)
    handles, labels = axes.flat[-1].get_legend_handles_labels()
    fig.legend(handles, labels, loc='lower center', ncol=4, fontsize=9)
    fig.suptitle('R-test saved measurement windows; phase boundaries unconfirmed', fontsize=11)
    fig.tight_layout(rect=(0, 0.05, 1, 0.96))
    fig.savefig(OUT/'Rtest_三向窗口散点图.png', dpi=220)
    fig.savefig(OUT/'Rtest_三向窗口散点图.pdf')
    plt.close(fig)


if __name__ == '__main__':
    main()
