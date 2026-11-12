"""Publish only the guarded staging profile reader. Never changes IAM or tables."""
import argparse, hashlib, base64, json, pathlib, subprocess, zipfile
p=argparse.ArgumentParser();p.add_argument('--publish',action='store_true');args=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
archive=pathlib.Path('/private/tmp/customer-profile-447.zip')
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    z.writestr('index.js',(root/'src/functions/get-user-profile/index.js').read_text().replace("require('../create-order/account-guard')","require('./account-guard')").replace("require('../shared/customer-promotion-consent-449')","require('./customer-promotion-consent-449')"))
    z.write(root/'src/functions/create-order/account-guard.js','account-guard.js')
    z.write(root/'src/functions/shared/customer-promotion-consent-449.js','customer-promotion-consent-449.js')
expected=base64.b64encode(hashlib.sha256(archive.read_bytes()).digest()).decode()
common=['--profile','Wizz_stg_UserApp','--region','us-east-1']
name='WizzUser-GetUserProfile-staging'
if args.publish:
    revision=json.loads(subprocess.check_output(['aws','lambda','get-function-configuration','--function-name',name,*common]))['RevisionId']
    result=json.loads(subprocess.check_output(['aws','lambda','update-function-code','--function-name',name,'--revision-id',revision,'--zip-file','fileb://'+str(archive),*common]))
    if result['CodeSha256'] != expected: raise RuntimeError('Code hash mismatch')
print(json.dumps({'function':name,'archive':str(archive),'sha256':expected,'published':args.publish}))
