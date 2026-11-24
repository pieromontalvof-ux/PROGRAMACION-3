import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

spec=importlib.util.spec_from_file_location('backup_parts',Path(__file__).resolve().parents[2]/'database/backups/partes.py')


class BackupPartsTests(unittest.TestCase):
    def test_parts_reassemble_exact_bytes_and_reject_gaps(self):
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        with TemporaryDirectory() as folder:
            data=b'abcdefghijklmnopqrstuvwxyz'
            parts=module.dividir(data,'documents.zip.enc',10)
            self.assertEqual(len(parts),3)
            paths=[Path(folder)/name for name,_ in parts]
            for path,(_,content) in zip(paths,parts):path.write_bytes(content)
            self.assertEqual(module.leer(paths[0]),data)
            paths[1].unlink()
            with self.assertRaises(ValueError):module.leer(paths[0])

    def test_small_archive_keeps_compatible_single_file(self):
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        self.assertEqual(module.dividir(b'abc','small.enc',10),[('small.enc',b'abc')])
