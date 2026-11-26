from pathlib import Path
import subprocess,json,hashlib,base64,zipfile,copy,urllib.request,time,datetime
R=Path(__file__).resolve().parents[1];C=R.parent/'whizzCentralPlatform-stg';M=R.parent/'whizzMerchants-stg';P=Path('/private/tmp/region-consumers-313');B=['aws','--profile','Wizz_stg_UserApp','--region','us-east-1'];ACCOUNT='699561669180';BUCKET='wizz-regions-artifacts-staging-699561669180'
def aws(*args):return json.loads(subprocess.check_output(B+list(args)+['--output','json']) or b'{}')
def sha(data):return hashlib.sha256(data).hexdigest()
def codehash(data):return base64.b64encode(hashlib.sha256(data).digest()).decode()
assert aws('sts','get-caller-identity')['Account']==ACCOUNT
assert 'All tests passed!' in Path('/private/tmp/regions-313-flutter-tests.log').read_text()
for f in ['customer','merchant']:assert 'ℹ fail 0' in Path('/private/tmp/regions-313-'+f+'-tests.log').read_text()
shared={f'utils/{n}':(R/'backend/src/utils'/n).read_bytes()for n in ['customer-regions-313.js','region-coverage-runtime-312.js']}
plans=[]
for name,entry in [('WizzUser-FindRegionByCoordinates-staging','lambdas/find-region-by-coordinates.js'),('WizzUser-CreateAddress-staging','functions/create-address/index.js'),('WizzUser-UpdateAddress-staging','functions/update-address/index.js'),('WizzUser-GetBusinessesByRegion-staging','lambdas/get-businesses-by-region.js'),('WizzUser-GetNearbyBusinesses-staging','lambdas/get-nearby-businesses.js')]:
 config=aws('lambda','get-function-configuration','--function-name',name)
 base=P/(name+'.zip')
 if not base.exists():
  # Prior deployment receipt pins this exact immutable reader artifact.
  known=C/'backend/.tmp/regions-312/reader-candidate.zip';assert codehash(known.read_bytes())==config['CodeSha256'];base.write_bytes(known.read_bytes())
 assert codehash(base.read_bytes())==config['CodeSha256'],'LIVE_DRIFT '+name
 changes={**shared,entry:(R/'backend/src'/entry).read_bytes()};plans.append((name,config,base,changes))
for name in ['order-receiver-regional-staging-unified-auth-v4-sam','order-receiver-regional-staging-location-settings-v1-sam']:
 config=aws('lambda','get-function-configuration','--function-name',name);base=P/(name+'.zip');assert codehash(base.read_bytes())==config['CodeSha256'],'LIVE_DRIFT '+name
 changes={n:(M/'backend/functions/auth'/n).read_bytes()for n in ['onboarding_regions.js','customer-regions-313.js','region-coverage-runtime-312.js']};plans.append((name,config,base,changes))
# Prepare every artifact first; preserve all unrelated ZIP entries.
for name,config,base,changes in plans:
 out=P/(name+'.candidate.zip')
 with zipfile.ZipFile(base)as before,zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED)as after:
  for info in before.infolist():after.writestr(copy.copy(info),changes.get(info.filename,before.read(info.filename)))
  for f,b in changes.items():
   if f not in before.namelist():after.writestr(f,b)
 with zipfile.ZipFile(base)as before,zipfile.ZipFile(out)as after:assert all(before.read(f)==after.read(f)for f in before.namelist()if f not in changes)
# Read grants only; condition checks are included for atomic address/merchant saves.
roles={config['Role'].split('/')[-1]for _,config,_,_ in plans}
policy={'Version':'2012-10-17','Statement':[{'Effect':'Allow','Action':['dynamodb:GetItem','dynamodb:ConditionCheckItem'],'Resource':[f'arn:aws:dynamodb:us-east-1:{ACCOUNT}:table/'+t for t in ['WizzCentral_Regions','WizzCentral_RegionsDerived_staging']]},{'Effect':'Allow','Action':['dynamodb:Query'],'Resource':f'arn:aws:dynamodb:us-east-1:{ACCOUNT}:table/WizzCentral_RegionIndex_staging/index/h3-index'}]}
for role in roles:
 own=json.loads(json.dumps(policy))
 if any('FindRegion' in name and config['Role'].endswith('/'+role)for name,config,_,_ in plans):own['Statement'].append({'Effect':'Allow','Action':['dynamodb:Scan'],'Resource':[f'arn:aws:dynamodb:us-east-1:{ACCOUNT}:table/'+t for t in ['WizzCentral_Regions','WizzCentral_RegionsDerived_staging']]})
 path=P/(role+'.policy.json');path.write_text(json.dumps(own));aws('iam','put-role-policy','--role-name',role,'--policy-name','RegionConsumers313','--policy-document','file://'+str(path))
 print('Added scoped region read grant',role,flush=True)
receipt={'status':'DEPLOYING','businessDataMutated':False,'functions':[],'roles':sorted(roles),'publishedAt':datetime.datetime.now(datetime.timezone.utc).isoformat()}
dest=R/'docs/region-consumers-publication-313.json'
for name,config,base,changes in plans:
 # Verify no concurrent code change immediately before updating.
 latest=aws('lambda','get-function-configuration','--function-name',name);assert latest['CodeSha256']==config['CodeSha256']
 env=dict(latest.get('Environment',{}).get('Variables',{}))
 if name.startswith('WizzUser-'):env.update(REGIONS_TABLE='WizzCentral_Regions',REGIONS_DERIVED_TABLE='WizzCentral_RegionsDerived_staging',REGION_INDEX_TABLE='WizzCentral_RegionIndex_staging')
 env['REGION_CONSUMERS_VERSION']='313';ep=P/(name+'.environment.private.json');ep.write_text(json.dumps({'Variables':env}));aws('lambda','update-function-configuration','--function-name',name,'--revision-id',latest['RevisionId'],'--environment','file://'+str(ep));subprocess.check_call(B+['lambda','wait','function-updated-v2','--function-name',name])
 out=P/(name+'.candidate.zip');key='region-consumers/313/'+name+'/'+sha(out.read_bytes())+'.zip';subprocess.check_call(B+['s3','cp',str(out),'s3://'+BUCKET+'/'+key,'--only-show-errors'])
 latest=aws('lambda','get-function-configuration','--function-name',name);aws('lambda','update-function-code','--function-name',name,'--revision-id',latest['RevisionId'],'--s3-bucket',BUCKET,'--s3-key',key);subprocess.check_call(B+['lambda','wait','function-updated-v2','--function-name',name]);after=aws('lambda','get-function-configuration','--function-name',name);assert after['CodeSha256']==codehash(out.read_bytes());assert after['Role']==config['Role'];assert all(after['Environment']['Variables'].get(k)==v for k,v in latest['Environment']['Variables'].items())
 receipt['functions'].append({'name':name,'beforeHash':config['CodeSha256'],'hash':after['CodeSha256'],'changedFiles':list(changes),'otherEntriesPreserved':True,'rolePreserved':True});dest.write_text(json.dumps(receipt,indent=2)+'\n');print('Published and verified',name,flush=True)
receipt['status']='PUBLISHED_CODE_VERIFIED';dest.write_text(json.dumps(receipt,indent=2)+'\n')
print('All region consumer functions published; proceed to read-only HTTP smoke checks',flush=True)
