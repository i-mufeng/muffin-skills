"""Known ratios, threshold boundary, invalid input, and CLI exit semantics."""
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name('check-contrast.py')
SPEC = importlib.util.spec_from_file_location('contrast_checker', SCRIPT)
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)


class ContrastTests(unittest.TestCase):
    def test_known_ratios(self):
        self.assertAlmostEqual(checker.contrast('#000', '#fff'), 21)
        self.assertAlmostEqual(checker.contrast('#123456', '#123456'), 1)
        self.assertAlmostEqual(checker.contrast('#777', '#fff'), 4.478089453577214)

    def test_unrounded_boundary(self):
        result = checker.check([dict(name='boundary', foreground='#777', background='#fff', minimum=4.5)])
        self.assertFalse(result[0][3])

    def test_invalid_data(self):
        for value in ['#ffff', '#ffffffff', 'red', 'var(--color)', None]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                checker.contrast(value, '#fff')
        for minimum in [True, float('nan'), 0, 22, '4.5']:
            with self.subTest(minimum=minimum), self.assertRaises(ValueError):
                checker.check([dict(name='invalid', foreground='#000', background='#fff', minimum=minimum)])
        with self.assertRaises(ValueError):
            checker.check([])

    def test_cli_exit_status(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'pairs.json'
            for color, expected in [('#000', 0), ('#777', 1), ('transparent', 2)]:
                target.write_text(json.dumps([dict(name='CLI', foreground=color, background='#fff', minimum=4.5)]))
                result = subprocess.run([sys.executable, str(SCRIPT), str(target)], capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
