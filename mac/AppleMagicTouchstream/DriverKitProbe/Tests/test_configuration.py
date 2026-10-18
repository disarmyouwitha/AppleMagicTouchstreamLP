"""Guard the deployment manifest across the app, helper and driver packages."""
import json
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class ConfigurationTests(unittest.TestCase):
    def test_generated_language_bindings_are_current(self):
        subprocess.run([sys.executable, str(ROOT/'generate-config.py'), '--check'], check=True)

    def test_packaged_driver_and_helper_use_same_manifest(self):
        config = json.loads((ROOT/'takeover-config.json').read_text())
        with tempfile.TemporaryDirectory() as directory:
            app = pathlib.Path(directory)/config['helperAppName']
            dext = app/'Contents/Library/SystemExtensions'/(config['driverBundleID']+'.dext')
            dext.mkdir(parents=True)
            subprocess.run([sys.executable, str(ROOT/'package.py'), str(app), str(dext)], check=True)
            host = plistlib.loads((app/'Contents/Info.plist').read_bytes())
            driver = plistlib.loads((dext/'Info.plist').read_bytes())
            self.assertEqual(host['CFBundleIdentifier'], config['helperBundleID'])
            self.assertEqual(driver['CFBundleIdentifier'], config['driverBundleID'])
            for info in [host, driver]:
                self.assertEqual(info['CFBundleVersion'], str(config['driverBuild']))
                self.assertEqual(info['CFBundleShortVersionString'], config['driverVersion'])
            for personality in driver['IOKitPersonalities'].values():
                self.assertEqual(personality['IOUserServerName'], config['driverBundleID'])
                self.assertNotIn('HandoffClientProperties', personality)

    def test_owner_identity_matches_project_identity_and_is_not_wildcard(self):
        config = json.loads((ROOT/'takeover-config.json').read_text())
        project = (ROOT.parent/'project.env').read_text()
        self.assertIn('EXPECTED_BUNDLE_ID="'+config['appBundleID']+'"', project)
        self.assertNotIn('*', config['appBundleID'])
        self.assertNotIn('*', config['teamID'])

if __name__ == '__main__': unittest.main()
