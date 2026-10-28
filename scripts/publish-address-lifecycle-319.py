"""Publish isolated address handlers on staging. Does not mutate customer address data."""
from pathlib import Path
import subprocess,json,zipfile,hashlib,base64,urllib.request,urllib.error,datetime
R=Path(__file__).resolve().parents[1];P=Path('/private/tmp/address-319');B=['aws','--profile','Wizz_stg_UserApp','--region','us-east-1']
KINDS={'CreateAddress':'create-address','UpdateAddress':'update-address','DeleteAddress':'delete-address','SetDefaultAddress':'set-default-address','GetUserAddresses':'get-user-addresses','GetAddress':'get-address'}
def aws(*a):return json.loads(subprocess.check_output(B+list(a)+['--output','json'])or b'{}')
def digest(b):return base64.b64encode(hashlib.sha256(b).digest()).decode()
assert 'fail 0' in Path('/private/tmp/address-319-node-tests.log').read_text()
assert 'All tests passed!' in Path('/private/tmp/address-319-flutter-tests.log').read_text()
assert 'error •' not in Path('/private/tmp/address-319-analyze-target.log').read_text()
configs={k:json.loads((P/('WizzUser-'+k+'-staging.config.private.json')).read_text())for k in KINDS}
for k,c in configs.items():
 live=aws('lambda','get-function-configuration','--function-name',c['FunctionName'])
 assert live['CodeSha256']==c['CodeSha256'] and live['Environment']==c['Environment'],'LIVE_DRIFT '+k
 assert digest((P/(c['FunctionName']+'.original.zip')).read_bytes())==c['CodeSha256']
 assert c['Handler']=='index.handler'
# A standalone SDK v3 bundle removes old monolithic module initialization.
esbuild=R.parent/'whizzCentralPlatform-stg/node_modules/esbuild/bin/esbuild'
for k,kind in KINDS.items():
 out=P/(k+'.js')
 subprocess.check_call([str(esbuild),str(R/'backend/src/functions'/kind/'index.js'),'--bundle','--platform=node','--target=node18','--format=cjs','--minify','--outfile='+str(out)])
 with zipfile.ZipFile(P/(k+'.candidate.zip'),'w',zipfile.ZIP_DEFLATED)as z:z.writestr('index.js',out.read_bytes())
createEnv=configs['CreateAddress']['Environment']['Variables'];users=createEnv['USERS_TABLE'];addresses=createEnv['ADDRESSES_TABLE']
assert users.endswith('staging') and addresses=='WizzUser_addresses_staging'
arn=lambda t:'arn:aws:dynamodb:us-east-1:699561669180:table/'+t
rows=[]
for k,c in configs.items():
 name=c['FunctionName'];role=c['Role'].split('/')[-1]
 mutating=k in ['CreateAddress','UpdateAddress','DeleteAddress','SetDefaultAddress']
 policy={'Version':'2012-10-17','Statement':[{'Effect':'Allow','Action':['dynamodb:GetItem']+(['dynamodb:UpdateItem','dynamodb:ConditionCheckItem']if mutating else []),'Resource':arn(users)},{'Effect':'Allow','Action':['dynamodb:GetItem','dynamodb:Query']+(['dynamodb:Scan','dynamodb:PutItem','dynamodb:UpdateItem','dynamodb:DeleteItem','dynamodb:ConditionCheckItem']if mutating else []),'Resource':[arn(addresses),arn(addresses)+'/index/userId-index']}]}
 if k=='SetDefaultAddress':policy['Statement'] += [{'Effect':'Allow','Action':['dynamodb:GetItem','dynamodb:ConditionCheckItem'],'Resource':[arn(createEnv['REGIONS_TABLE']),arn(createEnv['REGIONS_DERIVED_TABLE'])]},{'Effect':'Allow','Action':['dynamodb:Query'],'Resource':arn(createEnv['REGION_INDEX_TABLE'])+'/index/h3-index'}]
 # New unique policy; retain every pre-existing inline/managed policy unchanged.
 aws('iam','put-role-policy','--role-name',role,'--policy-name','AddressLifecycle319','--policy-document',json.dumps(policy))
 env=dict(c['Environment']['Variables'])
 if k=='SetDefaultAddress':env.update({key:createEnv[key]for key in ['REGIONS_TABLE','REGIONS_DERIVED_TABLE','REGION_INDEX_TABLE','REGION_CONSUMERS_VERSION']})
 live=aws('lambda','get-function-configuration','--function-name',name);assert live['CodeSha256']==c['CodeSha256']
 aws('lambda','update-function-configuration','--function-name',name,'--revision-id',live['RevisionId'],'--memory-size','512','--environment',json.dumps({'Variables':env}))
 subprocess.check_call(B+['lambda','wait','function-updated-v2','--function-name',name])
 live=aws('lambda','get-function-configuration','--function-name',name)
 out=P/(k+'.candidate.zip');bucket='wizz-regions-artifacts-staging-699561669180';key='region-consumers/319/'+hashlib.sha256(out.read_bytes()).hexdigest()+'.zip'
 subprocess.check_call(B+['s3','cp',str(out),'s3://'+bucket+'/'+key,'--only-show-errors'])
 aws('lambda','update-function-code','--function-name',name,'--revision-id',live['RevisionId'],'--s3-bucket',bucket,'--s3-key',key)
 subprocess.check_call(B+['lambda','wait','function-updated-v2','--function-name',name])
 after=aws('lambda','get-function-configuration','--function-name',name)
 assert after['CodeSha256']==digest(out.read_bytes()) and after['MemorySize']==512 and after['Environment']['Variables']==env and after['Role']==c['Role']
 rows.append({'name':name,'beforeHash':c['CodeSha256'],'hash':after['CodeSha256'],'memoryMB':512,'bundleBytes':out.stat().st_size,'policy':policy})
 print('Published and hash verified:',name,flush=True)
statuses={}
base='https://4jut6787c8.execute-api.us-east-1.amazonaws.com/staging/users/address-auth-check/addresses'
for method,suffix in [('GET',''),('POST',''),('GET','/address-auth-check'),('PUT','/address-auth-check'),('DELETE','/address-auth-check'),('PUT','/address-auth-check/set-default')]:
 request=urllib.request.Request(base+suffix,data=b'{}'if method in ['POST','PUT']else None,headers={'Content-Type':'application/json'},method=method)
 try:status=urllib.request.urlopen(request,timeout=25).status
 except urllib.error.HTTPError as e:status=e.code
 assert status==401,(method,suffix,status);statuses[method+suffix]=status
receipt={'status':'PUBLISHED_VERIFIED','publishedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'functions':rows,'unauthenticatedStatuses':statuses,'savedAddressLimit':10,'newTable':False,'bookMetadata':'Users.addressBook319; atomic revision/default/ids with account lifecycle fence','businessDataMutated':False,'existingAddressesDeleted':False,'authenticatedDeviceRetest':'PENDING_USER','tests':{'node':23,'flutterLifecycle':8,'analyzerErrors':0}}
(R/'docs/address-lifecycle-publication-319.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print('All six handlers verified; customer data untouched.',flush=True)
