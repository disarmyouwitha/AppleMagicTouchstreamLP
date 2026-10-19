"""Offline regression: a zero exit code with Invalid must not reach stapling."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NotarizationTests(unittest.TestCase):
    def run_pipeline(self, status):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            fake = folder/'xcrun'
            fake.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$TEST_CALL_LOG"
if [[ "$1 $2" == "notarytool submit" ]]; then
    printf '{"status":"%s","id":"fixture-submission"}\\n' "$TEST_STATUS"
fi
''')
            fake.chmod(0o755)
            source = (ROOT/'release.sh').read_text()
            a = source.index('notarize() {')
            b = source.index('\nstaple_and_validate()', a)
            functions = source[a:b]
            script = '''set -euo pipefail
log_step() { printf '[STEP] %s\\n' "$1"; }
log_pass() { printf '[PASS] %s\\n' "$1"; }
log_fail() { printf '[FAIL] %s\\n' "$1"; exit 1; }
NOTARY_ARGS=(--keychain-profile fixture)
'''+functions+'''
notarize "$TEST_ARTIFACT" "fixture"
xcrun stapler staple "$TEST_ARTIFACT"
'''
            environment = dict(os.environ, PATH=str(folder)+os.pathsep+os.environ['PATH'],
                SCRIPT_DIR=str(ROOT), TEST_CALL_LOG=str(folder/'calls'), TEST_STATUS=status,
                TEST_ARTIFACT=str(folder/'fixture.zip'))
            result = subprocess.run(['/bin/bash','-c',script],env=environment,capture_output=True,text=True)
            return result, (folder/'calls').read_text()

    def test_invalid_with_zero_exit_stops_before_stapling_and_downloads_log(self):
        result,calls = self.run_pipeline('Invalid')
        self.assertNotEqual(result.returncode,0)
        self.assertNotIn('[PASS]',result.stdout)
        self.assertIn('notarytool log fixture-submission',calls)
        self.assertNotIn('stapler',calls)

    def test_accepted_can_proceed_to_stapling(self):
        result,calls = self.run_pipeline('Accepted')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('[PASS] fixture notarization accepted',result.stdout)
        self.assertIn('stapler staple',calls)

    def test_in_progress_cannot_be_mistaken_for_accepted(self):
        result,calls = self.run_pipeline('In Progress')
        self.assertNotEqual(result.returncode,0)
        self.assertNotIn('stapler',calls)


if __name__ == '__main__':
    unittest.main()
