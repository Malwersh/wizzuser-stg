"""Read-only public base-fee preview; preserve every legacy invoice/financial handler byte."""
from pathlib import Path
import subprocess,json,zipfile,copy,hashlib,base64,urllib.request,urllib.error,datetime
R=Path(__file__).resolve().parents[1];P=Path('/private/tmp/service-fee-320');B=['aws','--profile','Wizz_stg_UserApp','--region','us-east-1'];NAME='WizzUser-DeliveryQuotes-staging'
def aws(*a):return json.loads(subprocess.check_output(B+list(a)+['--output','json'])or b'{}')
def digest(b):return base64.b64encode(hashlib.sha256(b).digest()).decode()
assert 'fail 0' in Path('/private/tmp/service-fee-320-node.log').read_text()
assert 'All tests passed!'in Path('/private/tmp/service-fee-320-flutter.log').read_text()
assert 'error •'not in Path('/private/tmp/service-fee-320-analyze.log').read_text()
c=json.loads((P/'quote.config.private.json').read_text());live=aws('lambda','get-function-configuration','--function-name',NAME)
assert live['Environment']==c['Environment'],'LIVE_ENV_DRIFT'
assert digest((P/'quote.original.zip').read_bytes())==c['CodeSha256']
changes={'index.js':(R/'backend/src/functions/delivery-quotes/point-handler-317.js').read_bytes(),'point-preview-runtime-317.js':(R/'backend/src/functions/delivery-quotes/point-preview-runtime-317.js').read_bytes()}
out=P/'quote.candidate.zip'
with zipfile.ZipFile(P/'quote.original.zip')as z,zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED)as w:
 assert 'legacy-index-317.js'in z.namelist()
 for i in z.infolist():w.writestr(copy.copy(i),changes.get(i.filename,z.read(i.filename)))
with zipfile.ZipFile(P/'quote.original.zip')as z,zipfile.ZipFile(out)as w:assert all(z.read(n)==w.read(n)for n in z.namelist()if n not in changes)
policy={'Version':'2012-10-17','Statement':[{'Effect':'Allow','Action':'dynamodb:GetItem','Resource':'arn:aws:dynamodb:us-east-1:699561669180:table/staging-PlatformStaff','Condition':{'ForAllValues:StringLike':{'dynamodb:LeadingKeys':['COMMERCIAL_AGREEMENT#*']}}}]}
aws('iam','put-role-policy','--role-name',c['Role'].split('/')[-1],'--policy-name','ServiceFeeApprovalRead320','--policy-document',json.dumps(policy))
bucket='wizz-regions-artifacts-staging-699561669180';key='region-consumers/320/'+hashlib.sha256(out.read_bytes()).hexdigest()+'.zip'
subprocess.check_call(B+['s3','cp',str(out),'s3://'+bucket+'/'+key,'--only-show-errors'])
if live['CodeSha256']!=digest(out.read_bytes()):
 assert live['CodeSha256']==c['CodeSha256'],'LIVE_CODE_DRIFT'
 aws('lambda','update-function-code','--function-name',NAME,'--revision-id',live['RevisionId'],'--s3-bucket',bucket,'--s3-key',key)
 subprocess.check_call(B+['lambda','wait','function-updated-v2','--function-name',NAME])
after=aws('lambda','get-function-configuration','--function-name',NAME);assert after['CodeSha256']==digest(out.read_bytes())and after['Environment']==c['Environment']and after['Role']==c['Role']
url='https://4jut6787c8.execute-api.us-east-1.amazonaws.com/staging/storefront-point-preview'
def request(body):
 req=urllib.request.Request(url,data=json.dumps(body).encode(),headers={'Content-Type':'application/json'},method='POST')
 try:
  r=urllib.request.urlopen(req,timeout=40);return r.status,json.load(r)
 except urllib.error.HTTPError as e:return e.code,json.load(e)
assert request({'action':'service_fee_preview','branchId':'b','addressId':'x'})[0]==400
status,body=request({'action':'service_fee_preview','branchId':'business_1791634772438_p2hlg6w5qii'})
assert status==200,(status,body)
p=body['preview'];assert p['kind']=='SERVICE_FEE_PREVIEW'and p['informationalOnly']and p['requiresFinalConfirmation']
receipt={'status':'PUBLISHED_LIVE_READ_VERIFIED','publishedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'name':NAME,'beforeHash':c['CodeSha256'],'hash':after['CodeSha256'],'legacyFinancialAndQuoteEntriesPreserved':True,'environmentUnchanged':True,'approvalReadOnlyPolicy':policy,'liveBaseFeePreview':p,'noAddressRoutingRequired':True,'businessWrites':False,'tests':{'node':35}}
(R/'docs/service-fee-preview-320.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print('Published. Real branch base fee minor:',p['baseServiceFee']['minorAmount']if p['baseServiceFee']else None,flush=True)
