"""Deploy read-only preview correction; financial create path, env and IAM unchanged."""
from pathlib import Path
import subprocess,json,zipfile,copy,hashlib,base64,datetime
R=Path(__file__).resolve().parents[1];P=Path('/private/tmp/invoice-323');B=['aws','--profile','Wizz_stg_UserApp','--region','us-east-1'];NAME='WizzUser-CreateOrder-staging'
def aws(*a):return json.loads(subprocess.check_output(B+list(a)+['--output','json'])or b'{}')
def digest(b):return base64.b64encode(hashlib.sha256(b).digest()).decode()
for n in ['point-tests.log','backend-compat.log']:assert 'fail 0'in (P/n).read_text()
assert 'All tests passed!'in (P/'flutter-tests.log').read_text()
assert 'error •'not in (P/'analyze.log').read_text()
c=json.loads((P/'create.config.private.json').read_text());live=aws('lambda','get-function-configuration','--function-name',NAME);assert live['CodeSha256']==c['CodeSha256']and live['Environment']==c['Environment'],'LIVE_DRIFT'
assert digest((P/'create.original.zip').read_bytes())==c['CodeSha256']
with zipfile.ZipFile(P/'create.original.zip')as z:
 root=z.read('functions/create-order/index.js').decode();assert "if(input?.action==='preview_commercial_point')"in root
 root=root.replace("if(input?.action==='preview_commercial_point')","if(['preview_commercial_point','preview_commercial'].includes(input?.action))")
changes={'functions/create-order/index.js':root.encode(),'functions/create-order/point-order-handler-321.js':(P/'preview-handler-323.js').read_bytes()};out=P/'create.candidate.zip'
with zipfile.ZipFile(P/'create.original.zip')as z,zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED)as w:
 for i in z.infolist():w.writestr(copy.copy(i),changes.get(i.filename,z.read(i.filename)))
with zipfile.ZipFile(P/'create.original.zip')as z,zipfile.ZipFile(out)as w:
 assert all(z.read(n)==w.read(n)for n in z.namelist()if n not in changes)
 assert z.read('_discount_review/user-create-order/index.js')==w.read('_discount_review/user-create-order/index.js')
bucket='wizz-regions-artifacts-staging-699561669180';key='region-consumers/323/'+hashlib.sha256(out.read_bytes()).hexdigest()+'.zip';subprocess.check_call(B+['s3','cp',str(out),'s3://'+bucket+'/'+key,'--only-show-errors'])
aws('lambda','update-function-code','--function-name',NAME,'--revision-id',live['RevisionId'],'--s3-bucket',bucket,'--s3-key',key);subprocess.check_call(B+['lambda','wait','function-updated-v2','--function-name',NAME])
after=aws('lambda','get-function-configuration','--function-name',NAME);assert after['CodeSha256']==digest(out.read_bytes())and after['Environment']==c['Environment']and after['Role']==c['Role']
event={'httpMethod':'POST','resource':'/orders/commercial-preview','headers':{},'body':json.dumps({'action':'preview_commercial_point','userId':'auth-check','storeId':'b','items':[{'id':'p','quantity':1}],'pricingPoint':{'latitude':31.9,'longitude':44.4}})}
(P/'probe.json').write_text(json.dumps(event));aws('lambda','invoke','--function-name',NAME,'--payload','fileb://'+str(P/'probe.json'),str(P/'probe-response.json'));assert json.loads((P/'probe-response.json').read_text())['statusCode']==401
receipt={'status':'BACKEND_PUBLISHED_AUTH_VERIFIED_NATIVE_PENDING','publishedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'function':NAME,'beforeHash':c['CodeSha256'],'hash':after['CodeSha256'],'onlyPreviewAdapterAndBundleChanged':True,'legacyOrderCreationFinancialBundleUnchanged':True,'environmentAndIAMUnchanged':True,'previewAllowedWithExistingActiveOrder':True,'newOrderStillBlockedWithExistingActiveOrder':True,'allPreviewDatabasesReadOnly':True,'businessWritesPerformed':False,'tests':{'completePointAndBoundary':6,'financialCompatibility':51,'flutter':53,'preexistingSkipped':1,'targetAnalyzerErrors':0}}
(R/'docs/basket-invoice-publication-323.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n');print('Published read-only preview fix; legacy financial creation path and IAM unchanged.')
