"""Guarded staging publication: isolated public read-only preview; preserve exact legacy handler."""
from pathlib import Path
import subprocess,json,zipfile,hashlib,base64,copy,urllib.request,urllib.error,datetime
R=Path(__file__).resolve().parents[1];P=Path('/private/tmp/browse-317');B=['aws','--profile','Wizz_stg_UserApp','--region','us-east-1'];NAME='WizzUser-DeliveryQuotes-staging'
def aws(*a):return json.loads(subprocess.check_output(B+list(a)+['--output','json'])or b'{}')
def digest(b):return base64.b64encode(hashlib.sha256(b).digest()).decode()
assert 'All tests passed!' in Path('/private/tmp/browse-317-regression-final.log').read_text()
for p in ['browse-317-node-tests.log','browse-317-handler-tests.log']:assert 'fail 0'in Path('/private/tmp/'+p).read_text()
assert not Path('/private/tmp/browse-317-tsc.log').read_text().strip()
original=json.loads((P/'quote.config.private.json').read_text());before=aws('lambda','get-function-configuration','--function-name',NAME)
assert before['CodeSha256']==original['CodeSha256'] and before['Environment']==original['Environment'],'LIVE_DRIFT'
assert digest((P/'quote.live.zip').read_bytes())==before['CodeSha256']
role=before['Role'].split('/')[-1]
resources=aws('apigateway','get-resources','--rest-api-id','4jut6787c8')['items'];root=next(r['id']for r in resources if r['path']=='/')
subprocess.check_call(B+['cloudformation','deploy','--stack-name','staging-storefront-point-preview-317','--template-file',str(R/'backend/infra/storefront-point-preview-317.yaml'),'--parameter-overrides','QuoteRoleName='+role,'ParentResourceId='+root,'--capabilities','CAPABILITY_NAMED_IAM','--no-fail-on-empty-changeset'])
aws('apigateway','create-deployment','--rest-api-id','4jut6787c8','--stage-name','staging','--description','317 isolated read-only point preview')
ttl=aws('dynamodb','describe-time-to-live','--table-name','staging-StorefrontPointPreviewRate')['TimeToLiveDescription'];assert ttl.get('AttributeName')=='expiresAtEpoch'and ttl['TimeToLiveStatus']in ['ENABLED','ENABLING']
policy=aws('iam','get-role-policy','--role-name',role,'--policy-name','PublicPointPreview317')['PolicyDocument']
changes={'index.js':(R/'backend/src/functions/delivery-quotes/point-handler-317.js').read_bytes(),'point-preview-runtime-317.js':(R/'backend/src/functions/delivery-quotes/point-preview-runtime-317.js').read_bytes()};out=P/'quote.candidate.zip'
with zipfile.ZipFile(P/'quote.live.zip')as z,zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED)as w:
 assert 'legacy-index-317.js'not in z.namelist()
 for i in z.infolist():w.writestr(copy.copy(i),changes.get(i.filename,z.read(i.filename)))
 w.writestr('legacy-index-317.js',z.read('index.js'))
 for n,data in changes.items():
  if n not in z.namelist():w.writestr(n,data)
with zipfile.ZipFile(P/'quote.live.zip')as z,zipfile.ZipFile(out)as w:
 assert z.read('index.js')==w.read('legacy-index-317.js')
 assert all(z.read(n)==w.read(n)for n in z.namelist()if n!='index.js')
key='region-consumers/317/'+hashlib.sha256(out.read_bytes()).hexdigest()+'.zip';bucket='wizz-regions-artifacts-staging-699561669180'
subprocess.check_call(B+['s3','cp',str(out),'s3://'+bucket+'/'+key,'--only-show-errors'])
current=aws('lambda','get-function-configuration','--function-name',NAME);assert current['CodeSha256']==before['CodeSha256']
aws('lambda','update-function-code','--function-name',NAME,'--revision-id',current['RevisionId'],'--s3-bucket',bucket,'--s3-key',key);subprocess.check_call(B+['lambda','wait','function-updated-v2','--function-name',NAME])
current=aws('lambda','get-function-configuration','--function-name',NAME);assert current['CodeSha256']==digest(out.read_bytes())
env={**before['Environment']['Variables'],'STOREFRONT_POINT_PREVIEW_ENABLED':'true'}
aws('lambda','update-function-configuration','--function-name',NAME,'--revision-id',current['RevisionId'],'--environment',json.dumps({'Variables':env}));subprocess.check_call(B+['lambda','wait','function-updated-v2','--function-name',NAME])
after=aws('lambda','get-function-configuration','--function-name',NAME);assert after['Environment']['Variables']==env and after['Role']==before['Role']
url='https://4jut6787c8.execute-api.us-east-1.amazonaws.com/staging/delivery-quotes'
def post(data,point=False):
 request=urllib.request.Request(url.replace('/delivery-quotes','/storefront-point-preview')if point else url,data=json.dumps(data).encode(),headers={'Content-Type':'application/json'},method='POST')
 try:
  response=urllib.request.urlopen(request,timeout=35);return response.status,json.load(response)
 except urllib.error.HTTPError as e:return e.code,json.load(e)
assert post({'branchId':'auth-check','addressId':'auth-check','requestId':'auth-check'})[0]==401
assert post({'action':'storefront_point_preview','branchId':'b','regionId':'r','point':{'latitude':'31','longitude':44}},point=True)[0]==400
record={'status':'PUBLISHED_VERIFIED_AUTH_AND_SCHEMA_LIVE_PRICING_PENDING','publishedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'name':NAME,'beforeHash':before['CodeSha256'],'hash':after['CodeSha256'],'legacyHandlerPreservedByteForByte':True,'legacyCompanionFilesPreserved':True,'existingEnvironmentPreserved':True,'addedEnvironmentFlag':'STOREFRONT_POINT_PREVIEW_ENABLED','newRateTable':'staging-StorefrontPointPreviewRate','rateTableTtl':ttl,'newPolicy':policy,'savedAddressWrites':False,'financialWrites':False,'tests':{'nodeCore':42,'nodeHandler':2,'flutter':87,'flutterSkipped':1,'typescript':'PASS'}}
(R/'docs/point-preview-publication-317.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print('Published point preview; exact legacy handler and schema/authentication verified; rate table TTL active.',flush=True)
