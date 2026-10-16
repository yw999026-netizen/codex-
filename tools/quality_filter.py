"""Apply provenance-bound exclusions without changing a source workbook.

Remaining rows are candidates, never automatically declared valid. Historical
time columns are copied as recorded; actual elapsed time cannot be reconstructed.
"""
from pathlib import Path
import argparse
import csv
import hashlib
import json
import math

def _sample_key(value):
    try:
        number=float(value)
    except (TypeError,ValueError) as exc:
        raise ValueError('Original sample ID must be an integer') from exc
    if not math.isfinite(number) or number!=int(number):
        raise ValueError('Original sample ID must be an integer')
    return int(number)

def classify_records(records,policy,workbook_sha256,sheet):
    if workbook_sha256!=policy['workbook_sha256'] or sheet!=policy['sheet']:
        raise ValueError('Exclusion policy does not match workbook hash and sheet')
    column=policy['sample_id_column'];exclusions={_sample_key(r['sample_id']):r for r in policy['exclusions']}
    if len(exclusions)!=len(policy['exclusions']):raise ValueError('Duplicate exclusion IDs')
    reviewed=[];seen=set()
    for source in records:
        key=_sample_key(source.get(column))
        if key in seen:raise ValueError('Duplicate original sample ID')
        seen.add(key);row=dict(source);rule=exclusions.get(key)
        row['quality_status']='excluded' if rule else 'candidate_not_fully_validated'
        row['quality_reason_code']=rule['reason_code'] if rule else 'OTHER_QUALITY_CHECKS_PENDING'
        row['quality_reason']=rule['reason'] if rule else '仅应用已确认排除规则，尚未完成其他质量验证'
        reviewed.append(row)
    if not set(exclusions).issubset(seen):raise ValueError('Confirmed excluded sample is missing')
    return reviewed,[r for r in reviewed if r['quality_status']!='excluded']

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--input',required=True);parser.add_argument('--policy',required=True);parser.add_argument('--output-dir',required=True)
    args=parser.parse_args();source=Path(args.input);policy=json.loads(Path(args.policy).read_text(encoding='utf-8'))
    digest=hashlib.sha256(source.read_bytes()).hexdigest()
    if digest!=policy['workbook_sha256']:raise ValueError('Source workbook hash mismatch')
    import openpyxl
    book=openpyxl.load_workbook(source,read_only=True,data_only=True);sheet=book[policy['sheet']]
    iterator=sheet.iter_rows(values_only=True);headers=list(next(iterator))
    if len(set(headers))!=len(headers):raise ValueError('Duplicate column names')
    records=[dict(zip(headers,row)) for row in iterator if any(v is not None for v in row)]
    reviewed,candidates=classify_records(records,policy,digest,policy['sheet']);book.close()
    output=Path(args.output_dir);output.mkdir(parents=True,exist_ok=True)
    for name,rows in [('window_quality_register.csv',reviewed),('candidate_windows_excluding_15.csv',candidates)]:
        with (output/name).open('w',encoding='utf-8-sig',newline='') as handle:
            writer=csv.DictWriter(handle,fieldnames=headers+['quality_status','quality_reason_code','quality_reason'],lineterminator='\n');writer.writeheader();writer.writerows(rows)
    summary={'source_workbook_sha256':digest,'source_sheet':policy['sheet'],'original_rows':len(reviewed),'excluded_rows':len(reviewed)-len(candidates),'candidate_rows':len(candidates),'remaining_rows_validated':False,'historical_time_fields':'copied as recorded; actual elapsed time unknown','measured_calibration_file_modified':False}
    (output/'quality_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if hashlib.sha256(source.read_bytes()).hexdigest()!=digest:raise RuntimeError('Source workbook changed')
    print(json.dumps(summary,ensure_ascii=False))

if __name__=='__main__':main()
