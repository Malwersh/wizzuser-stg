"""Patch captured staging bundles with revision fences; preserve deployed dependencies."""
import argparse,base64,hashlib,json,pathlib,subprocess,zipfile
args=argparse.ArgumentParser();args.add_argument('--publish',action='store_true');args.add_argument('--function');opt=args.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];stage=pathlib.Path('/private/tmp/phone451')
common=['--profile','Wizz_stg_UserApp','--region','us-east-1']
for name,files in [('WizzUser-phone-auth-staging',{'index.js':root/'phone-auth/index.js'}),('WizzUser-phone-link-staging',{'index.js':root/'phone-link/index.js','profile-link-451.js':root/'phone-link/profile-link-451.js'})]:
 if opt.function and name!=opt.function:continue
 folder=stage/name;cfg=json.loads((folder/'config.json').read_text());out=folder/'patched.zip'
 with zipfile.ZipFile(folder/'before.zip') as old,zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
  for item in old.infolist():
   if item.filename not in files:z.writestr(item,old.read(item.filename))
  for filename,path in files.items():z.writestr(filename,path.read_bytes())
 digest=base64.b64encode(hashlib.sha256(out.read_bytes()).digest()).decode()
 if opt.publish:
  live=json.loads(subprocess.check_output(['aws','lambda','get-function-configuration','--function-name',name,*common]))
  if live['RevisionId']!=cfg['RevisionId']:raise RuntimeError('Deployment changed; recapture and review '+name)
  result=json.loads(subprocess.check_output(['aws','lambda','update-function-code','--function-name',name,'--revision-id',cfg['RevisionId'],'--zip-file','fileb://'+str(out),*common]))
  if result['CodeSha256']!=digest:raise RuntimeError('Hash mismatch')
  subprocess.check_call(['aws','lambda','wait','function-updated-v2','--function-name',name,*common])
 print(json.dumps({'function':name,'sha256':digest,'published':opt.publish}))
