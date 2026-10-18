import datetime,importlib.util,pathlib,plistlib,unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('probe_sign',pathlib.Path(__file__).resolve().parents[1]/'sign.py')
sign=importlib.util.module_from_spec(spec);spec.loader.exec_module(sign)
class SigningTests(unittest.TestCase):
    def profile(self, extra=None):
        ent={'com.apple.application-identifier':'TEAM.test.host','com.apple.developer.system-extension.install':True,'get-task-allow':True}
        ent.update(extra or {})
        return plistlib.dumps({'Entitlements':ent,'ExpirationDate':datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)+datetime.timedelta(days=1),'TeamIdentifier':['TEAM'],'DeveloperCertificates':[b'fixture']})
    def load(self,extra=None,userclient=None,required=None):
        with patch.object(sign.subprocess,'check_output',return_value=self.profile(extra)):
            return sign.load_profile(pathlib.Path('test.provisionprofile'),'test.host',required or ['com.apple.developer.system-extension.install'],userclient)
    def test_scoped_access_preserves_application_identity_and_array(self):
        _,_,ent=self.load({'com.apple.developer.driverkit.userclient-access':['test.driver']},'test.driver')
        self.assertEqual(ent['com.apple.application-identifier'],'TEAM.test.host')
        self.assertEqual(ent['com.apple.developer.driverkit.userclient-access'],['test.driver'])
        self.assertNotIn('com.apple.developer.driverkit.allow-any-userclient-access',ent)
    def test_missing_scoped_access_fails(self):
        with self.assertRaises(ValueError):self.load(userclient='test.driver')
    def test_scoped_access_to_different_driver_fails(self):
        with self.assertRaises(ValueError):self.load({'com.apple.developer.driverkit.userclient-access':['other.driver']},'test.driver')
    def test_string_in_place_of_array_fails(self):
        with self.assertRaises(ValueError):self.load({'com.apple.developer.driverkit.userclient-access':'test.driver'},'test.driver')
    def test_development_capability_must_be_apple_authorized(self):
        key='com.apple.developer.driverkit.allow-any-userclient-access'
        with self.assertRaises(ValueError):self.load(required=[key])
        _,_,ent=self.load({key:True},required=[key])
        self.assertIs(ent[key],True)
    def test_unrequested_profile_capability_is_not_signed_in(self):
        _,_,ent=self.load({'com.apple.developer.driverkit.allow-any-userclient-access':True})
        self.assertNotIn('com.apple.developer.driverkit.allow-any-userclient-access',ent)
if __name__=='__main__':unittest.main()
