import pathlib,sys,json,hashlib,base64,zipfile,urllib.request,io,time,copy
sys.path.insert(0,'/private/tmp/full-cash-208')
from aws_session import session
r=pathlib.Path(__file__).resolve().parents[1];p=pathlib.Path('/private/tmp/cash-review-274')
for f in ['bundle-tests.log','regression-tests.log']:assert 'fail 0' in (p/f).read_text(),f
s=session();assert s.client('sts').get_caller_identity()['Account']=='699561669180'
l=s.client('lambda');name='WizzUser-CreateOrder-staging';live=l.get_function(FunctionName=name);cfg=live['Configuration'];assert cfg['CodeSha256']=='93eYb7gxelc8k8jip4ekcp8Aks26PIu0HamMftBPztY=','Live code changed; inspect before publishing'
raw=urllib.request.urlopen(live['Code']['Location'],timeout=90).read();(p/'base.zip').write_bytes(raw);z=zipfile.ZipFile(io.BytesIO(raw));target='_discount_review/user-create-order/index.js';assert z.read(target)==(p/'runtime'/target).read_bytes()
new=p/'candidate.zip'
with zipfile.ZipFile(new,'w',zipfile.ZIP_DEFLATED) as out:
 for info in z.infolist():out.writestr(copy.copy(info),(p/'writer-candidate.js').read_bytes() if info.filename==target else z.read(info.filename))
 out.writestr('order-exception-policy-274.js',(p/'order-exception-policy-274.js').read_bytes())
payload=new.read_bytes();sha=base64.b64encode(hashlib.sha256(payload).digest()).decode()
record={'part':274,'status':'PUBLISHING','function':name,'baseCodeSha256':cfg['CodeSha256'],'candidateCodeSha256':sha,'change':'Pin existing exception policy at FULL_CASH order creation','tests':48,'existingOrdersModified':False,'realFinancialAttestationsCreated':False};doc=r/'docs/order-exception-publication-274.json';doc.write_text(json.dumps(record,indent=2)+'\n')
l.update_function_code(FunctionName=name,RevisionId=cfg['RevisionId'],ZipFile=payload,Publish=False)
for _ in range(60):
 after=l.get_function_configuration(FunctionName=name)
 if after['LastUpdateStatus']!='InProgress':break
 time.sleep(2)
assert after['LastUpdateStatus']=='Successful' and after['CodeSha256']==sha
for k in ['Environment','Role','Handler','Runtime','Timeout','MemorySize','Layers','VpcConfig','Architectures']:assert cfg.get(k)==after.get(k),k
actual=l.get_function(FunctionName=name);a=zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(actual['Code']['Location'],timeout=90).read()));expected=zipfile.ZipFile(new)
assert sorted(a.namelist())==sorted(expected.namelist())
for n in a.namelist():
 assert a.read(n)==expected.read(n),n
 if n not in [target,'order-exception-policy-274.js']:assert a.read(n)==z.read(n),n
res=l.invoke(FunctionName=name,Payload=json.dumps({'httpMethod':'POST','headers':{'Authorization':'Bearer invalid-smoke-token'},'resource':'/orders/commercial-preview','body':json.dumps({'action':'preview_commercial','storeId':'smoke-branch','storeName':'smoke','storeAddress':'smoke','deliveryAddress':{'id':'smoke-address'},'paymentMethod':'cod','userId':'smoke-customer','items':[{'id':'smoke-item','quantity':1}]})}).encode());response=json.loads(res['Payload'].read());assert not res.get('FunctionError') and response['statusCode']==401
record.update(status='PUBLISHED_VERIFIED',configurationAndIamUnchanged=True,allDeployedBytesVerified=True,unrelatedEntriesPreserved=True,negativeSmokeStatus=401,humanNewOrderTest='PENDING');doc.write_text(json.dumps(record,indent=2)+'\n');print('PASS: bounded creation-policy patch published and exact deployed bytes verified; no order or financial record modified.',flush=True)
