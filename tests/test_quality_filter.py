import importlib.util
from pathlib import Path
import unittest

SOURCE=Path(__file__).resolve().parents[1]/'tools/quality_filter.py'
class QualityTests(unittest.TestCase):
    def api(self):
        self.assertTrue(SOURCE.is_file(),'实际分析排除工具尚未实现')
        spec=importlib.util.spec_from_file_location('quality_filter',SOURCE);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
    def policy(self):
        return {'workbook_sha256':'0'*64,'sheet':'热误差建模样本','sample_id_column':'样本编号','exclusions':[{'sample_id':15,'reason_code':'USER_CONFIRMED_INVALID_DATA','reason':'用户已确认错误，具体原因未知'}]}
    def test_excludes_only_confirmed_sample_and_preserves_original(self):
        api=self.api();records=[{'样本编号':i,'X':i*2} for i in range(1,23)];before=[dict(r) for r in records]
        reviewed,candidates=api.classify_records(records,self.policy(),'0'*64,'热误差建模样本')
        self.assertEqual(records,before);self.assertEqual(len(reviewed),22);self.assertEqual(len(candidates),21)
        self.assertEqual(reviewed[14]['quality_status'],'excluded');self.assertEqual(reviewed[14]['quality_reason_code'],'USER_CONFIRMED_INVALID_DATA')
        self.assertNotIn(15,[r['样本编号'] for r in candidates]);self.assertTrue(all(r['quality_status']=='candidate_not_fully_validated' for r in candidates))
    def test_wrong_provenance_rejected(self):
        api=self.api()
        with self.assertRaises(ValueError):api.classify_records([{'样本编号':15}],self.policy(),'1'*64,'热误差建模样本')
        with self.assertRaises(ValueError):api.classify_records([{'样本编号':15}],self.policy(),'0'*64,'other')
    def test_duplicate_sample_ids_rejected(self):
        with self.assertRaises(ValueError):self.api().classify_records([{'样本编号':15},{'样本编号':15}],self.policy(),'0'*64,'热误差建模样本')
    def test_missing_confirmed_target_rejected(self):
        with self.assertRaises(ValueError):self.api().classify_records([{'样本编号':1}],self.policy(),'0'*64,'热误差建模样本')

if __name__=='__main__':unittest.main()
