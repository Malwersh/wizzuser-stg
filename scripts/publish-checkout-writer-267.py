import pathlib,sys,json,hashlib,base64,zipfile,urllib.request,io,time
sys.path.insert(0,'/private/tmp/full-cash-208');from aws_session import session
r=pathlib.Path(__file__).resolve().parents[1];p=pathlib.Path('/private/tmp/checkout-267');assert 'fail 0' in (p/'writer-tests.log').read_text();assert json.loads((p/'preflight.log').read_text())['status']=='PASS'
s=session();assert s.client('sts').get_caller_identity()['Account']=='699561669180';l=s.client('lambda');name='WizzUser-CreateOrder-staging';base=json.loads((p/'writer-config.private.json').read_text());cfg=l.get_function_configuration(FunctionName=name)
raw=(p/'writer-candidate.zip').read_bytes();expected=base64.b64encode(hashlib.sha256(raw).digest()).decode();assert cfg['CodeSha256'] in [base['CodeSha256'],expected]
if cfg['CodeSha256']!=expected:l.update_function_code(FunctionName=name,RevisionId=cfg['RevisionId'],ZipFile=raw,Publish=False)
for _ in range(80):
 after=l.get_function_configuration(FunctionName=name)
 if after['LastUpdateStatus']!='InProgress':break
 time.sleep(2)
assert after['LastUpdateStatus']=='Successful';assert after['CodeSha256']==base64.b64encode(hashlib.sha256(raw).digest()).decode()
for k in ['Environment','Role','Handler','Runtime','Timeout','MemorySize','Layers','VpcConfig','Architectures']:assert base.get(k)==after.get(k),k
live=l.get_function(FunctionName=name);actual=zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(live['Code']['Location'],timeout=90).read()));candidate=zipfile.ZipFile(p/'writer-candidate.zip');original=zipfile.ZipFile(p/'writer-base.zip');changed=json.loads((p/'patch.json').read_text())['changedFile'];assert actual.namelist()==candidate.namelist()
for n in actual.namelist():
 assert actual.read(n)==candidate.read(n)
 if n!=changed:assert actual.read(n)==original.read(n)
# Reject an unauthenticated preview without creating a quote, order, consent or reservation.
smoke_body={'action':'preview_commercial','storeId':'smoke-branch','storeName':'smoke','storeAddress':'smoke','deliveryAddress':{'id':'smoke-address'},'paymentMethod':'cod','userId':'smoke-customer','items':[{'id':'smoke-item','quantity':1}]}
res=l.invoke(FunctionName=name,Payload=json.dumps({'httpMethod':'POST','resource':'/orders/commercial-preview','headers':{'Authorization':'Bearer invalid-negative-smoke-token'},'body':json.dumps(smoke_body)}).encode());smoke=json.loads(res['Payload'].read());assert not res.get('FunctionError');assert smoke['statusCode']in [401,403], {'status':smoke['statusCode'],'body':smoke.get('body')}
(r/'docs').mkdir(exist_ok=True);record={'part':267,'status':'PUBLISHED_VERIFIED','scope':'staging','function':name,'changedFile':changed,'allDeployedBytesVerified':True,'unrelatedEntriesPreserved':True,'codeSha256':after['CodeSha256'],'configurationAndIamUnchanged':True,'negativeSmokeStatus':smoke['statusCode'],'candidateReaderTests':9,'realPolicyPreflight':json.loads((p/'preflight.log').read_text()),'realOrdersOrFinancialAttestationsCreated':False,'humanCheckoutRetry':'PENDING'};(r/'docs/checkout-repair-publication-267.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n');print('PASS bounded writer publication and deployed bytes; permissions/configuration preserved; no order created',flush=True)
