"""User explicitly approved staging publication and exact routing read permissions."""
from pathlib import Path
import subprocess,json,zipfile,hashlib,base64,datetime
R=Path(__file__).resolve().parents[1];P=Path('/private/tmp/point-invoice-321');B=['aws','--profile','Wizz_stg_UserApp','--region','us-east-1'];NAME='WizzUser-CreateOrder-staging'
def aws(*a):return json.loads(subprocess.check_output(B+list(a)+['--output','json'])or b'{}')
def digest(b):return base64.b64encode(hashlib.sha256(b).digest()).decode()
review=json.loads((R/'docs/point-invoice-review-321.json').read_text());out=P/'create.candidate.zip'
assert hashlib.sha256(out.read_bytes()).hexdigest()==review['deploymentCandidateSha256']
assert 'fail 0'in Path('/private/tmp/point-invoice-321-node.log').read_text()
assert 'All tests passed!'in Path('/private/tmp/point-invoice-321-flutter.log').read_text()
assert 'error •'not in Path('/private/tmp/point-invoice-321-analyze.log').read_text()
c=json.loads((P/'create.config.private.json').read_text());live=aws('lambda','get-function-configuration','--function-name',NAME)
assert live['CodeSha256']==c['CodeSha256']and live['Environment']==c['Environment'],'LIVE_DRIFT'
assert digest((P/'create.original.zip').read_bytes())==c['CodeSha256']
with zipfile.ZipFile(P/'create.original.zip')as z,zipfile.ZipFile(out)as w:
 assert all(z.read(n)==w.read(n)for n in z.namelist()if n!='functions/create-order/index.js')
 assert w.read('functions/create-order/index.js')==(P/'root-321.js').read_bytes()
quote=aws('lambda','get-function-configuration','--function-name','WizzUser-DeliveryQuotes-staging');secret=quote['Environment']['Variables']['MAPBOX_SECRET_ARN'];assert secret.startswith('arn:aws:secretsmanager:us-east-1:699561669180:secret:')
policy={'Version':'2012-10-17','Statement':[{'Effect':'Allow','Action':['secretsmanager:GetSecretValue'],'Resource':secret},{'Effect':'Allow','Action':['dynamodb:Query'],'Resource':'arn:aws:dynamodb:us-east-1:699561669180:table/WizzCentral_RegionIndex_staging/index/h3-index'}]}
role=c['Role'].split('/')[-1]
prior=aws('iam','list-role-policies','--role-name',role);assert 'PointInvoiceRouting321'not in prior['PolicyNames']
(P/'original-inline-policies.json').write_text(json.dumps(prior))
aws('iam','put-role-policy','--role-name',role,'--policy-name','PointInvoiceRouting321','--policy-document',json.dumps(policy))
env={**c['Environment']['Variables'],'POINT_INVOICE_ENABLED':'true','MAPBOX_SECRET_ARN':secret}
aws('lambda','update-function-configuration','--function-name',NAME,'--revision-id',live['RevisionId'],'--memory-size','512','--environment',json.dumps({'Variables':env}));subprocess.check_call(B+['lambda','wait','function-updated-v2','--function-name',NAME])
live=aws('lambda','get-function-configuration','--function-name',NAME);assert live['CodeSha256']==c['CodeSha256']
bucket='wizz-regions-artifacts-staging-699561669180';key='region-consumers/321/'+hashlib.sha256(out.read_bytes()).hexdigest()+'.zip';subprocess.check_call(B+['s3','cp',str(out),'s3://'+bucket+'/'+key,'--only-show-errors'])
aws('lambda','update-function-code','--function-name',NAME,'--revision-id',live['RevisionId'],'--s3-bucket',bucket,'--s3-key',key);subprocess.check_call(B+['lambda','wait','function-updated-v2','--function-name',NAME])
after=aws('lambda','get-function-configuration','--function-name',NAME);assert after['CodeSha256']==digest(out.read_bytes())and after['Environment']['Variables']==env and after['MemorySize']==512
# No valid token and no address/basket mutation. Validate the deployed private action's auth.
event={'httpMethod':'POST','resource':'/orders/commercial-preview','headers':{},'body':json.dumps({'action':'preview_commercial_point','userId':'auth-check','storeId':'b','items':[{'id':'p','quantity':1}],'pricingPoint':{'latitude':31.9,'longitude':44.4}})}
(P/'auth-probe.json').write_text(json.dumps(event));result=aws('lambda','invoke','--function-name',NAME,'--payload','fileb://'+str(P/'auth-probe.json'),str(P/'auth-response.json'));response=json.loads((P/'auth-response.json').read_text());assert response['statusCode']==401,(response,result)
receipt={'status':'PUBLISHED_AUTH_VERIFIED_HUMAN_POINT_INVOICE_PENDING','publishedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'name':NAME,'beforeHash':c['CodeSha256'],'hash':after['CodeSha256'],'legacyFinancialBundleAndAllCompanionsUnchanged':True,'memoryMB':512,'routingReadOnlyPolicy':policy,'existingEnvPreserved':True,'businessDataMutated':False,'pointAndQuotePersisted':False,'unauthenticatedDirectStatus':401,'tests':review['tests'],'userExplicitlyApproved':True}
(R/'docs/point-invoice-publication-321.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n');print('Published point invoice. Legacy finance bytes preserved; live authentication rejects with401.',flush=True)
