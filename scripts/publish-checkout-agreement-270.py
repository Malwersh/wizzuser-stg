import pathlib,sys,json,hashlib,base64,zipfile,urllib.request,io,time
sys.path.insert(0,'/private/tmp/full-cash-208');from aws_session import session
r=pathlib.Path(__file__).resolve().parents[1];p=pathlib.Path('/private/tmp/checkout-270')
for name in ['bundle-tests','wallet-tests','compatibility-tests']:assert 'fail 0' in (p/(name+'.log')).read_text(),name
assert 'All tests passed!'in (p/'flutter-tests.log').read_text();assert '✓ Built'in (p/'user-ios-build.log').read_text()
preflight=json.loads((p/'preflight.log').read_text());assert preflight['status']=='PASS'and preflight['fullBundledDependencies']and preflight['allBusinessMutationsBlocked']
s=session();assert s.client('sts').get_caller_identity()['Account']=='699561669180';l=s.client('lambda');name='WizzUser-CreateOrder-staging';base=json.loads((p/'writer-config.private.json').read_text());cfg=l.get_function_configuration(FunctionName=name)
raw=(p/'writer-candidate.zip').read_bytes();expected=base64.b64encode(hashlib.sha256(raw).digest()).decode();assert cfg['CodeSha256']in [base['CodeSha256'],expected],'Live code changed; recapture before publishing'
record={'part':270,'status':'PUBLISHING','scope':'staging','function':name,'baseCodeSha256':base['CodeSha256'],'codeSha256':expected,'configurationAndIamUnchanged':True,'customerSimulatorBuild':219,'customerDesignsMerged':False,'humanCheckoutRetry':'PENDING','realOrdersOrFinancialAttestationsCreated':False};doc=r/'docs/checkout-agreement-publication-270.json'
def save():doc.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
save()
if cfg['CodeSha256']!=expected:l.update_function_code(FunctionName=name,RevisionId=cfg['RevisionId'],ZipFile=raw,Publish=False)
for _ in range(90):
 after=l.get_function_configuration(FunctionName=name)
 if after['LastUpdateStatus']!='InProgress':break
 time.sleep(2)
assert after['LastUpdateStatus']=='Successful'and after['CodeSha256']==expected
for k in ['Environment','Role','Handler','Runtime','Timeout','MemorySize','Layers','VpcConfig','Architectures']:assert base.get(k)==after.get(k),k
record['status']='DEPLOYED_VERIFYING';save();print('Writer updated; configuration preserved',flush=True)
live=l.get_function(FunctionName=name);actual=zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(live['Code']['Location'],timeout=90).read()));candidate=zipfile.ZipFile(p/'writer-candidate.zip');original=zipfile.ZipFile(p/'writer-base.zip');changed=['_discount_review/user-create-order/index.js','checkout-store-agreement-270.js','checkout-pricing-reads-270.js'];assert sorted(actual.namelist())==sorted(candidate.namelist())
for n in actual.namelist():
 assert actual.read(n)==candidate.read(n)
 if n not in changed:assert actual.read(n)==original.read(n)
record.update(allDeployedBytesVerified=True,unrelatedEntriesPreserved=True,changedFiles=changed);save()
body={'action':'preview_commercial','storeId':'smoke-branch','storeName':'smoke','storeAddress':'smoke','deliveryAddress':{'id':'smoke-address'},'paymentMethod':'cod','userId':'smoke-customer','items':[{'id':'smoke-item','quantity':1}]}
res=l.invoke(FunctionName=name,Payload=json.dumps({'httpMethod':'POST','resource':'/orders/commercial-preview','headers':{'Authorization':'Bearer invalid-negative-smoke-token'},'body':json.dumps(body)}).encode());smoke=json.loads(res['Payload'].read());assert not res.get('FunctionError')and smoke['statusCode']==401
record['negativeSmokeStatus']=401
get=lambda t,k:s.resource('dynamodb').Table(t).get_item(Key=k,ConsistentRead=True).get('Item')
oid='bb728bfe-c2c4-5c95-8492-26ce81ee1ed1';case=get('staging-Holds',{'orderId':oid,'sk':'RETURN#1'});assert case['version']==14 and case['exceptionResolution']['status']=='RESOLVED';pay=get('staging-Holds',{'orderId':oid,'sk':'MERCHANT_PAYABLE'});assert pay['status']=='PAID'and pay['amount']==6250;assert get('staging-Holds',{'orderId':oid,'sk':'HOLD'})['status']=='RELEASED';assert get('staging-Holds',{'orderId':oid,'sk':'CUSTOMER_CASH_REVIEW'})is None
record.update(status='PUBLISHED_VERIFIED',historicalCase='14 RESOLVED; merchant PAID6250; hold RELEASED; no customer cash case',preflight=preflight,tests={'wallet':1373,'bundledPricing':59,'compatibilityAndReadCache':5,'flutter':37});save();print('PASS agreement publication, exact deployed bytes, unauthorized rejection and unchanged historical settlement',flush=True)
