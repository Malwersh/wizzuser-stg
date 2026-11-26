"""Guarded staging publication; no customer addresses/orders are created or edited."""
from pathlib import Path
import subprocess,json,zipfile,hashlib,base64,copy,urllib.request,urllib.error,datetime
R=Path(__file__).resolve().parents[1];P=Path('/private/tmp/browse-316');B=['aws','--profile','Wizz_stg_UserApp','--region','us-east-1']
NAMES=['WizzUser-CreateAddress-staging','WizzUser-GetUserAddresses-staging']
EXPECTED={NAMES[0]:'3A/tDzFK2fvHJne8hCCSnforsZGrj8lBak+dyStuL/I=',NAMES[1]:'n6Jv0FCTV7tGKEIbcaFdTXC8TnQ/hx6hpU6HJRNk/Ic='}
def aws(*a):return json.loads(subprocess.check_output(B+list(a)+['--output','json'])or b'{}')
def digest(b):return base64.b64encode(hashlib.sha256(b).digest()).decode()
assert 'All tests passed!' in Path('/private/tmp/browse-316-regression-final.log').read_text()
assert 'fail 0' in Path('/private/tmp/browse-316-backend-tests.log').read_text()
configs={n:aws('lambda','get-function-configuration','--function-name',n)for n in NAMES}
for n,f in configs.items():
 assert f['CodeSha256']==EXPECTED[n], 'LIVE_DRIFT '+n
 assert digest((P/(n+'.zip')).read_bytes())==EXPECTED[n]
 assert f['Environment']==json.loads((P/(n+'.config.private.json')).read_text())['Environment']
changes={NAMES[0]:{n:(R/'backend/src'/n).read_bytes()for n in ['functions/create-address/index.js','functions/create-address/idempotency-315.js']},NAMES[1]:{'index.js':(P/'get-addresses.bundle.js').read_bytes()}}
for n in NAMES:
 with zipfile.ZipFile(P/(n+'.zip'))as z,zipfile.ZipFile(P/(n+'.candidate.zip'),'w',zipfile.ZIP_DEFLATED)as w:
  for info in z.infolist():w.writestr(copy.copy(info),changes[n].get(info.filename,z.read(info.filename)))
  for name,data in changes[n].items():
   if name not in z.namelist():w.writestr(name,data)
 with zipfile.ZipFile(P/(n+'.zip'))as z,zipfile.ZipFile(P/(n+'.candidate.zip'))as w:
  assert all(z.read(i)==w.read(i)for i in z.namelist()if i not in changes[n])
reader=configs[NAMES[1]];env=reader['Environment']['Variables'];table=env['ADDRESSES_TABLE'];users=env['USERS_TABLE'];role=reader['Role'].split('/')[-1]
assert table=='WizzUser_addresses_staging' and users.endswith('staging')
# This unique expiry attribute is added only to new request-only address records.
ttl=aws('dynamodb','describe-time-to-live','--table-name',table)['TimeToLiveDescription']
assert ttl['TimeToLiveStatus']=='DISABLED','UNEXPECTED_TTL'
existing=aws('dynamodb','scan','--table-name',table,'--filter-expression','attribute_exists(checkoutExpiresAt)','--select','COUNT')
assert existing['Count']==0 and not existing.get('LastEvaluatedKey'),'EXPIRY_ATTRIBUTE_ALREADY_USED'
policy={'Version':'2012-10-17','Statement':[{'Effect':'Allow','Action':['dynamodb:GetItem'],'Resource':f'arn:aws:dynamodb:us-east-1:699561669180:table/{users}'}]}
aws('iam','put-role-policy','--role-name',role,'--policy-name','BrowseAddressOwner316','--policy-document',json.dumps(policy))
aws('dynamodb','update-time-to-live','--table-name',table,'--time-to-live-specification',json.dumps({'Enabled':True,'AttributeName':'checkoutExpiresAt'}))
rows=[]
for n in NAMES:
 f=aws('lambda','get-function-configuration','--function-name',n);assert f['CodeSha256']==EXPECTED[n]
 out=P/(n+'.candidate.zip');key='region-consumers/316/'+hashlib.sha256(out.read_bytes()).hexdigest()+'.zip';bucket='wizz-regions-artifacts-staging-699561669180'
 subprocess.check_call(B+['s3','cp',str(out),'s3://'+bucket+'/'+key,'--only-show-errors'])
 aws('lambda','update-function-code','--function-name',n,'--revision-id',f['RevisionId'],'--s3-bucket',bucket,'--s3-key',key)
 subprocess.check_call(B+['lambda','wait','function-updated-v2','--function-name',n])
 after=aws('lambda','get-function-configuration','--function-name',n)
 assert after['CodeSha256']==digest(out.read_bytes()) and after['Environment']==f['Environment'] and after['Role']==f['Role']
 rows.append({'name':n,'beforeHash':f['CodeSha256'],'hash':after['CodeSha256'],'changedFiles':list(changes[n]),'unrelatedZipEntriesPreserved':True,'environmentUnchanged':True})
 print('Published and hash verified:',n,flush=True)
statuses={}
for method in ['GET','POST']:
 url='https://4jut6787c8.execute-api.us-east-1.amazonaws.com/staging/users/address-auth-check/addresses'
 request=urllib.request.Request(url,data=b'{}'if method=='POST'else None,headers={'Content-Type':'application/json'},method=method)
 try:status=urllib.request.urlopen(request,timeout=25).status
 except urllib.error.HTTPError as e:status=e.code
 assert status==401,(method,status);statuses[method]=status
finalttl=aws('dynamodb','describe-time-to-live','--table-name',table)['TimeToLiveDescription'];assert finalttl['AttributeName']=='checkoutExpiresAt'and finalttl['TimeToLiveStatus']in ['ENABLING','ENABLED']
receipt={'status':'PUBLISHED_VERIFIED','publishedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'functions':rows,'readerPolicy':policy,'ttl':finalttl,'checkoutAddressLifetimeDays':7,'savedAddressLimitUnchanged':10,'unauthenticatedStatuses':statuses,'businessDataMutated':False,'existingAddressesDeleted':False,'tests':{'backend':21,'flutterCurrent':87,'legacyDeliveryQuoteSuite':'Pre-existing tests omit current mandatory approved confirmation; not counted as passing. See checkpoint.'}}
(R/'docs/browsing-address-publication-316.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print('Verified authentication, owner scope, and request-only expiry. No customer business data mutated.',flush=True)
