const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const {digest}=require('./challenge-policy');
const oldPhone='+9647831367435',newPhone='+9647801234567';
function app({claims={},record,active,users=[],phoneLock,failLive=false,legacy=false,phoneProfile=false,profileOverride={},failFinal=false,aliasFailure=false}={}){
 const time=Math.floor(Date.now()/1000),calls=[];
 const attrs={sub:'customer-sub',phone_number:oldPhone,phone_number_verified:'true',...(legacy?{email:'owner@example.test',email_verified:'true'}:{})};
 const profile={userId:legacy?'legacy-id':'customer-sub',cognitoSub:'customer-sub',cognitoUsername:'existing-user',phone:oldPhone,isActive:true,...profileOverride};
 const user={Username:'existing-user',get UserAttributes(){return Object.entries(attrs).map(([Name,Value])=>({Name,Value}));}};
 const token='a.'+Buffer.from(JSON.stringify({sub:'customer-sub',iss:'https://cognito-idp.us-east-1.amazonaws.com/pool',client_id:'client',token_use:'access',auth_time:time,...claims})).toString('base64url')+'.b';
 const rows=new Map();if(record)rows.set(record.id,{...record});if(active)rows.set('ACTIVE#customer-sub',active);if(phoneLock)rows.set('PHONE#'+newPhone,phoneLock);
 let fail=failFinal;
 const classes={};for(const name of ['GetUserCommand','ListUsersCommand','AdminUpdateUserAttributesCommand','GetCommand','QueryCommand','UpdateCommand','TransactWriteCommand','GetSecretValueCommand'])classes[name]=class{constructor(input){this.input=input;this.kind=name;}};
 function apply(i){
  if(i.TableName==='users'){
   if(i.UpdateExpression.includes('REMOVE phoneChangePending')){if(i.ExpressionAttributeValues[':phone'])profile.phone=i.ExpressionAttributeValues[':phone'];delete profile.phoneChangePending;}
   else profile.phoneChangePending=i.ExpressionAttributeValues[':id'];
  }else if(i.UpdateExpression?.includes('#state')){
   const r=rows.get(i.Key.id);r.state=i.ExpressionAttributeValues[':done']||i.ExpressionAttributeValues[':failed']||i.ExpressionAttributeValues[':applying'];r.used=true;
  }
 }
 const send=async cmd=>{cmd.kind??=cmd.constructor.name;calls.push(cmd);const i=cmd.input;
  if(cmd.kind==='GetUserCommand'){if(failLive)throw Object.assign(Error(),{name:'NotAuthorizedException'});return user;}
  if(cmd.kind==='QueryCommand')return {Items:(i.IndexName==='email-index'&&legacy)||(phoneProfile&&i.ExpressionAttributeValues[':value']===oldPhone)?[profile]:[]};
  if(cmd.kind==='ListUsersCommand')return {Users:users};
  if(cmd.kind==='GetSecretValueCommand')return {SecretString:JSON.stringify({apiKey:'fake',hmacKey:'key'})};
  if(cmd.kind==='GetCommand')return {Item:i.TableName==='users'?(i.Key.userId===profile.userId?profile:undefined):i.TableName==='staging-AccountDeletion'?undefined:rows.get(i.Key.id)};
  if(cmd.kind==='AdminUpdateUserAttributesCommand'){if(aliasFailure)throw Object.assign(Error(),{name:'AliasExistsException'});for(const a of i.UserAttributes)attrs[a.Name]=a.Value;return {};}
  if(cmd.kind==='TransactWriteCommand'){
   if(fail && i.TransactItems.some(x=>x.Update?.UpdateExpression.includes('REMOVE phoneChangePending'))){fail=false;throw Error('Injected final failure');}
   for(const x of i.TransactItems){if(x.Update)apply(x.Update);if(x.Put)rows.set(x.Put.Item.id,x.Put.Item);}
  }
  return {};
 };
 class Client{send(cmd){return send(cmd);}}
 const context={Buffer,console,process:{env:{ENVIRONMENT:'staging',USERS_TABLE:'users',OTP_TABLE:'table',DELETION_TABLE:'staging-AccountDeletion',USER_POOL_ID:'pool',CLIENT_ID:'client'}},fetch:async()=>({ok:true}),AbortSignal};
 function load(file){const mod={exports:{}};vm.runInNewContext(fs.readFileSync(__dirname+'/'+file,'utf8'),{...context,module:mod,exports:mod.exports,require:n=>n.startsWith('@aws-sdk/')?{...classes,CognitoIdentityProviderClient:Client,DynamoDBClient:Client,SecretsManagerClient:Client,DynamoDBDocumentClient:{from:()=>new Client()}}:n==='./profile-link-451'?load('profile-link-451.js'):require(n.startsWith('./')?__dirname+'/'+n:n)});return mod.exports;}
 const handler=load('index.js').handler;
 return {calls,profile,rows,attrs,run:(path,body={},method='POST')=>handler({httpMethod:method,path,headers:{Authorization:'Bearer '+token},body:JSON.stringify(body)})};
}
function valid(){const time=Math.floor(Date.now()/1000);return {id:'session',purpose:'phone-change-451',profileId:'customer-sub',previousPhone:oldPhone,previousIdentityPhone:oldPhone,sub:'customer-sub',username:'customer-sub',phone:newPhone,used:false,attempts:0,expiresAt:time+300,digest:digest('key','session','customer-sub','123456')};}
const verify=a=>a.run('/phone/verify',{sessionId:'session',code:'123456'});
test('status accepts a valid old session without writing or requiring recent login',async()=>{const a=app({claims:{auth_time:1}}),r=await a.run('/phone/status',{},'GET');assert.equal(r.statusCode,200);assert.equal(JSON.parse(r.body).requiresReauthentication,true);assert.ok(!a.calls.some(c=>['UpdateCommand','TransactWriteCommand','AdminUpdateUserAttributesCommand'].includes(c.kind)));});
test('stale session cannot start a phone change',async()=>{const a=app({claims:{auth_time:1}});assert.equal((await a.run('/phone/send',{phone:newPhone})).statusCode,403);});
test('wrong app issuer revoked session and wrong subject denied',async()=>{for(const opts of [{claims:{client_id:'other'}},{claims:{iss:'other'}},{claims:{sub:'other'}},{failLive:true}]){const a=app(opts);assert.equal((await a.run('/phone/status',{},'GET')).statusCode,401);}});
test('modern phone account updates profile and existing identity only',async()=>{const a=app({record:valid(),active:{sessionId:'session'}});assert.equal((await verify(a)).statusCode,200);assert.equal(a.profile.phone,newPhone);assert.equal(a.attrs.phone_number,newPhone);assert.equal(a.profile.userId,'customer-sub');assert.equal(a.profile.phoneChangePending,undefined);assert.ok(!a.calls.some(c=>/CreateUser/.test(c.kind)));});
test('legacy email account keeps original profile id',async()=>{const a=app({legacy:true,record:{...valid(),profileId:'legacy-id'},active:{sessionId:'session'}});assert.equal((await verify(a)).statusCode,200);assert.equal(a.profile.userId,'legacy-id');assert.equal(a.profile.phone,newPhone);});
test('wrong owner or legacy old challenge rejected before mutation',async()=>{for(const r of [{...valid(),sub:'other'},{...valid(),purpose:'phone-link'}]){const a=app({record:r,active:{sessionId:'session'}});assert.equal((await verify(a)).statusCode,400);assert.ok(!a.calls.some(c=>c.kind==='AdminUpdateUserAttributesCommand'));}});
test('wrong OTP consumes attempt without changing identity',async()=>{const a=app({record:valid(),active:{sessionId:'session'}});assert.equal((await a.run('/phone/verify',{sessionId:'session',code:'000000'})).statusCode,400);assert.ok(a.calls.some(c=>c.kind==='UpdateCommand'));assert.equal(a.attrs.phone_number,oldPhone);});
test('expired exhausted superseded or consumed uncommitted OTP denied',async()=>{for(const change of [{expiresAt:0},{attempts:5},{used:true},{}]){const a=app({record:{...valid(),...change},active:{sessionId:Object.keys(change).length?'session':'new'}});assert.equal((await verify(a)).statusCode,400);assert.equal(a.attrs.phone_number,oldPhone);}});
test('another account phone cannot be taken over',async()=>{const a=app({users:[{Attributes:[{Name:'sub',Value:'other'}]}]});assert.equal((await a.run('/phone/send',{phone:newPhone})).statusCode,409);assert.ok(!a.calls.some(c=>c.kind==='TransactWriteCommand'));});
test('reservation owned by another account rejected',async()=>{const a=app({phoneLock:{sub:'other'}});assert.equal((await a.run('/phone/send',{phone:newPhone})).statusCode,409);});
test('disabled deletion-marked or wrong profile cannot start change',async()=>{for(const profileOverride of [{isActive:false},{deletionRequestId:'d'},{userId:'other'}]){const a=app({profileOverride});assert.equal((await a.run('/phone/send',{phone:newPhone})).statusCode,409);}});
test('profile and challenge writes fence lifecycle, original phone, active attempt and pending operation',async()=>{const a=app({record:valid(),active:{sessionId:'session'}});await verify(a);const tx=a.calls.filter(c=>c.kind==='TransactWriteCommand');assert.equal(tx.length,2);assert.ok(tx.every(c=>c.input.TransactItems[0].ConditionCheck.TableName==='staging-AccountDeletion'));const claim=tx[0].input.TransactItems.find(x=>x.Update?.TableName==='users').Update;assert.match(claim.ConditionExpression,/attribute_not_exists\(phoneChangePending\)/);assert.match(claim.ConditionExpression,/phone = :old/);assert.equal(claim.ExpressionAttributeValues[':old'],oldPhone);const finish=tx[1].input.TransactItems.find(x=>x.Update?.TableName==='users').Update;assert.match(finish.ConditionExpression,/phoneChangePending = :id/);});
test('interrupted profile finalization resumes bound operation without another OTP or identity mutation',async()=>{const a=app({record:valid(),active:{sessionId:'session'},failFinal:true});assert.equal((await verify(a)).statusCode,503);assert.equal(a.attrs.phone_number,newPhone);assert.equal(a.profile.phone,oldPhone);assert.equal(a.profile.phoneChangePending,'session');const status=JSON.parse((await a.run('/phone/status',{},'GET')).body);assert.equal(status.pendingSessionId,'session');assert.equal((await a.run('/phone/verify',{sessionId:'session'})).statusCode,200);assert.equal(a.profile.phone,newPhone);assert.equal(a.calls.filter(c=>c.kind==='AdminUpdateUserAttributesCommand').length,1);});
test('completed retry is idempotent',async()=>{const a=app({record:valid(),active:{sessionId:'session'}});assert.equal((await verify(a)).statusCode,200);assert.equal((await verify(a)).statusCode,200);assert.equal(a.calls.filter(c=>c.kind==='AdminUpdateUserAttributesCommand').length,1);});
test('resuming cannot select a different phone or account',async()=>{const a=app({record:{...valid(),used:true,state:'APPLYING'},profileOverride:{phoneChangePending:'other'}});assert.equal((await a.run('/phone/verify',{sessionId:'session',phone:'+9647501234567'})).statusCode,409);assert.equal(a.attrs.phone_number,oldPhone);});

test('phone-only legacy profile resolves by authenticated verified phone without email',async()=>{const a=app({phoneProfile:true,profileOverride:{userId:'old-id'}});assert.equal((await a.run('/phone/status',{},'GET')).statusCode,200);});

test('legacy phone-only interrupted operation resolves original profile after identity phone moves',async()=>{
 const a=app({phoneProfile:true,profileOverride:{userId:'old-id'},record:{...valid(),profileId:'old-id'},active:{sessionId:'session'},failFinal:true});
 assert.equal((await verify(a)).statusCode,503);
 assert.equal(a.attrs.phone_number,newPhone);
 const status=await a.run('/phone/status',{},'GET');assert.equal(status.statusCode,200);
 assert.equal((await a.run('/phone/verify',{sessionId:'session'})).statusCode,200);
 assert.equal(a.profile.userId,'old-id');assert.equal(a.profile.phone,newPhone);
});

test('alias collision after reservation restores old profile and clears pending marker',async()=>{
 const a=app({record:valid(),active:{sessionId:'session'},aliasFailure:true});
 assert.equal((await verify(a)).statusCode,409);assert.equal(a.profile.phone,oldPhone);
 assert.equal(a.profile.phoneChangePending,undefined);assert.equal(a.attrs.phone_number,oldPhone);
 assert.equal(a.rows.get('session').state,'FAILED');
});
test('conflicting subject in direct profile is never accepted',async()=>{
 const a=app({profileOverride:{cognitoSub:'someone-else'}});assert.equal((await a.run('/phone/status',{},'GET')).statusCode,409);
});
