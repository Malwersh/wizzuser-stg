from pathlib import Path
import subprocess,json,zipfile,hashlib,base64,copy,urllib.request,urllib.error
R=Path(__file__).resolve().parents[1];P=Path('/private/tmp/address-315');P.mkdir(exist_ok=True);B=['aws','--profile','Wizz_stg_UserApp','--region','us-east-1'];NAME='WizzUser-CreateAddress-staging'
def aws(*a):return json.loads(subprocess.check_output(B+list(a)+['--output','json'])or b'{}')
def digest(b):return base64.b64encode(hashlib.sha256(b).digest()).decode()
assert 'All tests passed!' in Path('/private/tmp/address-315-flutter-tests.log').read_text()
assert 'ℹ fail 0' in Path('/private/tmp/address-315-backend-tests.log').read_text()
rows=json.loads((R/'docs/region-consumers-publication-313.json').read_text())['functions'];previous=next(r for r in rows if r['name']==NAME)
f=aws('lambda','get-function-configuration','--function-name',NAME);assert f['CodeSha256']==previous['hash'],'LIVE_DRIFT'
base=Path('/private/tmp/region-consumers-313')/(NAME+'.candidate.zip');assert digest(base.read_bytes())==f['CodeSha256']
changes={name:(R/'backend/src'/name).read_bytes()for name in ['functions/create-address/index.js','functions/create-address/idempotency-315.js']};out=P/'create-address.zip'
with zipfile.ZipFile(base)as z,zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED)as w:
 for info in z.infolist():w.writestr(copy.copy(info),changes.get(info.filename,z.read(info.filename)))
 for name,data in changes.items():
  if name not in z.namelist():w.writestr(name,data)
with zipfile.ZipFile(base)as z,zipfile.ZipFile(out)as w:assert all(z.read(i)==w.read(i)for i in z.namelist()if i not in changes)
key='region-consumers/315/'+hashlib.sha256(out.read_bytes()).hexdigest()+'.zip';bucket='wizz-regions-artifacts-staging-699561669180'
subprocess.check_call(B+['s3','cp',str(out),'s3://'+bucket+'/'+key,'--only-show-errors']);aws('lambda','update-function-code','--function-name',NAME,'--revision-id',f['RevisionId'],'--s3-bucket',bucket,'--s3-key',key);subprocess.check_call(B+['lambda','wait','function-updated-v2','--function-name',NAME]);after=aws('lambda','get-function-configuration','--function-name',NAME);assert after['CodeSha256']==digest(out.read_bytes());assert after['Environment']==f['Environment'] and after['Role']==f['Role']
url='https://4jut6787c8.execute-api.us-east-1.amazonaws.com/staging/users/address-auth-check/addresses'
try:response=urllib.request.urlopen(urllib.request.Request(url,data=b'{}',headers={'Content-Type':'application/json'},method='POST'),timeout=20);status=response.status
except urllib.error.HTTPError as e:status=e.code
assert status==401,'AUTH_GUARD_CHANGED '+str(status)
record={'status':'PUBLISHED_VERIFIED','name':NAME,'beforeHash':f['CodeSha256'],'hash':after['CodeSha256'],'changedFiles':list(changes),'otherEntriesPreserved':True,'iamUnchanged':True,'environmentUnchanged':True,'unauthenticatedStatus':status,'businessDataMutated':False,'existingAddressesDeleted':False}
(R/'docs/address-save-publication-315.json').write_text(json.dumps(record,indent=2)+'\n');print('Published verified address idempotency; authentication preserved; no user addresses changed.',flush=True)
