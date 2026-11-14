from pathlib import Path
import subprocess,json,zipfile,hashlib,base64,copy,urllib.request
R=Path(__file__).resolve().parents[1];P=Path('/private/tmp/region-boundary-314');P.mkdir(exist_ok=True);B=['aws','--profile','Wizz_stg_UserApp','--region','us-east-1'];NAME='WizzUser-FindRegionByCoordinates-staging'
def aws(*a):return json.loads(subprocess.check_output(B+list(a)+['--output','json'])or b'{}')
def digest(b):return base64.b64encode(hashlib.sha256(b).digest()).decode()
assert 'All tests passed!' in Path('/private/tmp/regions-314-flutter-tests.log').read_text()
assert 'ℹ fail 0' in Path('/private/tmp/regions-314-backend-tests.log').read_text()
receipt=json.loads((R/'docs/region-consumers-publication-313.json').read_text());before=next(r for r in receipt['functions']if r['name']==NAME)
f=aws('lambda','get-function-configuration','--function-name',NAME);assert f['CodeSha256']==before['hash'],'LIVE_DRIFT'
base=Path('/private/tmp/region-consumers-313')/(NAME+'.candidate.zip');assert digest(base.read_bytes())==f['CodeSha256']
entry='lambdas/find-region-by-coordinates.js';out=P/'reader.zip'
with zipfile.ZipFile(base)as z,zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED)as w:
 for info in z.infolist():w.writestr(copy.copy(info),(R/'backend/src'/entry).read_bytes()if info.filename==entry else z.read(info.filename))
with zipfile.ZipFile(base)as z,zipfile.ZipFile(out)as w:assert all(z.read(i)==w.read(i)for i in z.namelist()if i!=entry)
key='region-consumers/314/'+hashlib.sha256(out.read_bytes()).hexdigest()+'.zip';bucket='wizz-regions-artifacts-staging-699561669180'
subprocess.check_call(B+['s3','cp',str(out),'s3://'+bucket+'/'+key,'--only-show-errors']);aws('lambda','update-function-code','--function-name',NAME,'--revision-id',f['RevisionId'],'--s3-bucket',bucket,'--s3-key',key);subprocess.check_call(B+['lambda','wait','function-updated-v2','--function-name',NAME]);after=aws('lambda','get-function-configuration','--function-name',NAME);assert after['CodeSha256']==digest(out.read_bytes());assert after['Environment']==f['Environment'] and after['Role']==f['Role']
u='https://4jut6787c8.execute-api.us-east-1.amazonaws.com/staging/api/regions/find-by-coordinates?view=boundary&region_id=Rmhvcpnn3iy5f1'
r=urllib.request.urlopen(u,timeout=30);d=json.loads(r.read());assert r.status==200 and d['data']['geometry']['type']in ['Polygon','MultiPolygon']
record={'status':'PUBLISHED_VERIFIED','name':NAME,'beforeHash':f['CodeSha256'],'hash':after['CodeSha256'],'changedFiles':[entry],'otherEntriesPreserved':True,'iamUnchanged':True,'environmentUnchanged':True,'boundarySmoke':{'status':r.status,'regionId':d['data']['regionId'],'geometryType':d['data']['geometry']['type']},'businessDataMutated':False}
(R/'docs/region-boundary-publication-314.json').write_text(json.dumps(record,indent=2)+'\n');print('Published boundary endpoint; exact code verified and actual region outline returned.',flush=True)
