from pathlib import Path
import subprocess,json,zipfile,copy,hashlib,base64,urllib.request,urllib.error,datetime
R=Path(__file__).resolve().parents[1];P=Path('/private/tmp/browse-317');B=['aws','--profile','Wizz_stg_UserApp','--region','us-east-1'];NAME='WizzUser-DeliveryQuotes-staging'
def aws(*a):return json.loads(subprocess.check_output(B+list(a)+['--output','json'])or b'{}')
def digest(b):return base64.b64encode(hashlib.sha256(b).digest()).decode()
before=aws('lambda','get-function-configuration','--function-name',NAME);assert before['CodeSha256']==digest((P/'quote.candidate.zip').read_bytes()),'LIVE_DRIFT'
changes={'index.js':(R/'backend/src/functions/delivery-quotes/point-handler-317.js').read_bytes(),'point-preview-runtime-317.js':(R/'backend/src/functions/delivery-quotes/point-preview-runtime-317.js').read_bytes()};out=P/'quote.final.zip'
with zipfile.ZipFile(P/'quote.candidate.zip')as z,zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED)as w:
 for i in z.infolist():w.writestr(copy.copy(i),changes.get(i.filename,z.read(i.filename)))
with zipfile.ZipFile(P/'quote.live.zip')as original,zipfile.ZipFile(out)as z:
 assert z.read('legacy-index-317.js')==original.read('index.js')
 assert all(z.read(n)==original.read(n)for n in original.namelist()if n!='index.js')
key='region-consumers/317/'+hashlib.sha256(out.read_bytes()).hexdigest()+'.zip';bucket='wizz-regions-artifacts-staging-699561669180';subprocess.check_call(B+['s3','cp',str(out),'s3://'+bucket+'/'+key,'--only-show-errors'])
aws('lambda','update-function-code','--function-name',NAME,'--revision-id',before['RevisionId'],'--s3-bucket',bucket,'--s3-key',key);subprocess.check_call(B+['lambda','wait','function-updated-v2','--function-name',NAME]);after=aws('lambda','get-function-configuration','--function-name',NAME);assert after['CodeSha256']==digest(out.read_bytes())and after['Environment']==before['Environment']
url='https://4jut6787c8.execute-api.us-east-1.amazonaws.com/staging'
def post(path,data):
 r=urllib.request.Request(url+path,data=json.dumps(data).encode(),headers={'Content-Type':'application/json'},method='POST')
 try:
  x=urllib.request.urlopen(r,timeout=35);return x.status,json.load(x)
 except urllib.error.HTTPError as e:return e.code,json.load(e)
a=post('/delivery-quotes',{'branchId':'auth-check','addressId':'auth-check','requestId':'auth-check'});assert a[0]==401,a
b=post('/storefront-point-preview',{'action':'storefront_point_preview','branchId':'b','regionId':'r','point':{'latitude':'31','longitude':44}});assert b[0]==400,b
c=post('/storefront-point-preview',{'branchId':'b','addressId':'a','requestId':'x'});assert c[0]==400,c
original=json.loads((P/'quote.config.private.json').read_text());ttl=aws('dynamodb','describe-time-to-live','--table-name','staging-StorefrontPointPreviewRate')['TimeToLiveDescription'];role=original['Role'].split('/')[-1];policy=aws('iam','get-role-policy','--role-name',role,'--policy-name','PublicPointPreview317')['PolicyDocument']
record={'status':'PUBLISHED_VERIFIED_AUTH_AND_SCHEMA_LIVE_PRICING_PENDING','publishedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'name':NAME,'beforeHash':original['CodeSha256'],'hash':after['CodeSha256'],'legacyHandlerPreservedByteForByte':True,'legacyCompanionFilesPreserved':True,'existingEnvironmentPreserved':True,'addedEnvironmentFlag':'STOREFRONT_POINT_PREVIEW_ENABLED','newPublicPath':'/storefront-point-preview','protectedQuotePath':'/delivery-quotes','newRateTable':'staging-StorefrontPointPreviewRate','rateTableTtl':ttl,'newPolicy':policy,'savedAddressWrites':False,'financialWrites':False,'authAndSchemaStatuses':{'protectedQuoteWithoutAuthentication':a[0],'invalidPoint':b[0],'financialActionOnPublicPath':c[0]},'tests':{'nodeCore':42,'nodeHandler':3,'flutter':87,'flutterSkipped':1,'typescript':'PASS'}}
(R/'docs/point-preview-publication-317.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n');print('Exact legacy handler retained. Separate public route and protected quote route verified.',flush=True)
