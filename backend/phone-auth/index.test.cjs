const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const {digest}=require('./challenge-policy');
const time=()=>Math.floor(Date.now()/1000);
const phone='+9647831367435';
const legal=require('./customer-legal-contract-344');
const legalRow={pk:legal.PK,sk:'CURRENT',status:'PUBLISHED',version:1,publishedAt:'2026-10-28T00:00:00.000Z',values:legal.DEFAULTS};
legalRow.digest=legal.hash({schemaVersion:1,revision:1,publishedAt:legalRow.publishedAt,...legalRow.values});
const legalPin=legal.pin(legal.readPublished(legalRow));
function app({verified=true,enabled=true,used=false,expired=false,wrongProfile=false,noUser=false,canonical=false,closing=false,legalUnavailable=false}={}){
 const calls=[],classes={};for(const kind of ['GetCommand','PutCommand','QueryCommand','UpdateCommand','TransactWriteCommand','GetSecretValueCommand','ListUsersCommand','AdminCreateUserCommand','AdminSetUserPasswordCommand','AdminInitiateAuthCommand','AdminRespondToAuthChallengeCommand'])classes[kind]=class{constructor(input){this.kind=kind;this.input=input;}};
 const user={Username:'cognito-original',Enabled:enabled,UserStatus:'CONFIRMED',Attributes:[{Name:'sub',Value:'original-sub'},{Name:'phone_number',Value:phone},{Name:'phone_number_verified',Value:String(verified)},{Name:'email',Value:'owner@test.invalid'},{Name:'email_verified',Value:'true'}]};
 const profile={userId:canonical?'original-sub':'legacy-user-id',cognitoUsername:wrongProfile?'different-user':'owner@test.invalid',email:'owner@test.invalid',name:'غيث',phone,isActive:true};
 let provisionRecord;
 const send=async c=>{calls.push(c);const i=c.input;
  if(c.kind==='GetSecretValueCommand')return {SecretString:JSON.stringify({hmacKey:'test-key',apiKey:'test-only'})};
  if(c.kind==='GetCommand'){
   if(i.TableName==='legal')return {Item:legalUnavailable?undefined:structuredClone(legalRow)};
   if(i.TableName==='staging-AccountDeletion')return {Item:closing?{state:'CLOSING'}:undefined};
   if(i.Key.id==='session')return {Item:{id:'session',phone,username:phone,purpose:'customer-phone-otp',expiresAt:expired?time()-1:time()+300,attempts:0,used,digest:digest('test-key','session',phone,'123456')}};
   if(i.Key.id===`ACTIVE#${phone}`)return {Item:{sessionId:'session'}};
   if(i.Key.id===`PROVISION#${phone}`)return {Item:provisionRecord};
   if(i.TableName==='profiles'&&canonical)return {Item:profile};return {};
  }
  if(c.kind==='PutCommand'&&i.Item?.id===`PROVISION#${phone}`)provisionRecord=i.Item;
  if(c.kind==='AdminCreateUserCommand')return {User:{Username:'new-cognito',Enabled:true,UserStatus:'FORCE_CHANGE_PASSWORD',Attributes:[{Name:'sub',Value:'new-sub'},{Name:'phone_number',Value:phone},{Name:'phone_number_verified',Value:'true'}]}};
  if(c.kind==='ListUsersCommand')return {Users:noUser?[]:[user]};
  if(c.kind==='QueryCommand')return {Items:!noUser&&i.IndexName==='email-index'?[profile]:[]};
  if(c.kind==='AdminInitiateAuthCommand')return {ChallengeName:'CUSTOM_CHALLENGE',Session:'trusted-cognito-session'};
  if(c.kind==='AdminRespondToAuthChallengeCommand')return {AuthenticationResult:{AccessToken:'access',IdToken:'id',RefreshToken:'refresh'}};
  if(c.kind==='PutCommand'&&i.TableName==='wallets')throw Object.assign(Error(),{name:'ConditionalCheckFailedException'});
  return {};
 };
 const modules={};for(const [name,client]of [['@aws-sdk/client-dynamodb','DynamoDBClient'],['@aws-sdk/client-secrets-manager','SecretsManagerClient'],['@aws-sdk/client-cognito-identity-provider','CognitoIdentityProviderClient']])modules[name]={[client]:class{send=send},...classes};
 modules['@aws-sdk/lib-dynamodb']={DynamoDBDocumentClient:{from:()=>({send})},...classes};
 const sandbox={exports:{},require:n=>modules[n]||require(n.startsWith('./')?__dirname+'/'+n:n),process:{env:{ENVIRONMENT:'staging',LEGAL_SETTINGS_TABLE:'legal',OTP_TABLE:'otp',USERS_TABLE:'profiles',WALLETS_TABLE:'wallets',DELETION_TABLE:'staging-AccountDeletion',USER_POOL_ID:'pool',CLIENT_ID:'client'}},console:{error(){}},fetch:async()=>({ok:true}),AbortSignal,Buffer};
 vm.runInNewContext(fs.readFileSync(__dirname+'/index.js','utf8'),sandbox);
 return {calls,legalGet:()=>sandbox.exports.handler({httpMethod:'GET',path:'/legal'}),run:(body={code:'123456'})=>sandbox.exports.handler({path:'/auth/phone/verify',body:JSON.stringify({phone,sessionId:'session',...body})})};
}
test('verified legacy phone authenticates original Cognito username and profile ID',async()=>{
 const a=app(),r=await a.run();assert.equal(r.statusCode,200);assert.equal(JSON.parse(r.body).user.userId,'legacy-user-id');
 assert.equal(a.calls.find(c=>c.kind==='AdminInitiateAuthCommand').input.AuthParameters.USERNAME,'cognito-original');assert.ok(!a.calls.some(c=>c.kind==='AdminCreateUserCommand'||c.kind==='AdminSetUserPasswordCommand'));
 const w=a.calls.filter(c=>c.kind==='TransactWriteCommand').flatMap(c=>c.input.TransactItems).find(x=>x.Put?.TableName==='wallets').Put;assert.equal(w.Item.walletId,'WALLET#CUSTOMER#original-sub');assert.equal(w.ConditionExpression,'attribute_not_exists(walletId)');assert.ok(!a.calls.some(c=>c.kind==='UpdateCommand'&&c.input.TableName==='wallets'));
});
test('canonical phone profile is reused',async()=>{const a=app({canonical:true});assert.equal(JSON.parse((await a.run()).body).user.userId,'original-sub');});
for(const [label,opts]of [['unverified existing phone',{verified:false}],['disabled Cognito user',{enabled:false}],['unrelated email profile',{wrongProfile:true}]])test(label+' cannot obtain tokens',async()=>{const a=app(opts);assert.equal((await a.run()).statusCode,409);assert.ok(!a.calls.some(c=>c.kind==='AdminInitiateAuthCommand'||c.kind==='AdminCreateUserCommand'));});
for(const [label,opts]of [['expired OTP',{expired:true}],['used OTP',{used:true}]])test(label+' is rejected before identity lookup',async()=>{const a=app(opts);assert.equal((await a.run()).statusCode,400);assert.ok(!a.calls.some(c=>c.kind==='ListUsersCommand'));});
test('wrong OTP increments attempts and cannot create or log into accounts',async()=>{const a=app();assert.equal((await a.run({code:'654321'})).statusCode,400);assert.ok(a.calls.some(c=>c.kind==='UpdateCommand'));assert.ok(!a.calls.some(c=>c.kind==='ListUsersCommand'));});
test('new phone requests name and consent after valid OTP without consuming it',async()=>{const a=app({noUser:true}),r=await a.run();assert.equal(r.statusCode,200);assert.equal(JSON.parse(r.body).needsName,true);assert.ok(!a.calls.some(c=>c.kind==='TransactWriteCommand'||c.kind==='AdminCreateUserCommand'));});
const {eligible,belongs,publicProfile}=require('./profile-policy');
test('email identity requires verified email and an exact existing binding',()=>{const u={Username:'cognito',Enabled:true,UserStatus:'CONFIRMED',Attributes:[{Name:'sub',Value:'sub'},{Name:'email',Value:'a@test.invalid'},{Name:'email_verified',Value:'false'},{Name:'phone_number_verified',Value:'true'}]};assert.ok(eligible(u));assert.ok(!belongs({userId:'legacy',email:'a@test.invalid',cognitoUsername:'a@test.invalid'},u));});
test('profile response excludes password and private profile fields',()=>{assert.equal(publicProfile({userId:'id',password:'secret',admin:true}).password,undefined);assert.equal(publicProfile({userId:'id',admin:true}).admin,undefined);});
test('invalid new-account name never consumes OTP or creates an account',async()=>{const a=app({noUser:true}),r=await a.run({code:'123456',name:'x',termsAccepted:true,privacyAccepted:true});assert.equal(JSON.parse(r.body).needsName,true);assert.ok(!a.calls.some(c=>c.kind==='TransactWriteCommand'||c.kind==='AdminCreateUserCommand'));});

test('new phone creates a confirmed identity, matching profile and zero wallet only after OTP and consent',async()=>{const a=app({noUser:true}),r=await a.run({code:'123456',name:'مستخدم جديد',termsAccepted:true,privacyAccepted:true,usageAccepted:true,legalAcceptance:legalPin});assert.equal(r.statusCode,200);assert.equal(JSON.parse(r.body).user.userId,'new-sub');const create=a.calls.findIndex(c=>c.kind==='AdminCreateUserCommand');assert.ok(create>a.calls.findIndex(c=>c.kind==='TransactWriteCommand'));const puts=a.calls.filter(c=>c.kind==='TransactWriteCommand').flatMap(c=>c.input.TransactItems).filter(x=>x.Put).map(x=>x.Put);const profile=puts.find(x=>x.TableName==='profiles');assert.equal(profile.Item.cognitoSub,'new-sub');assert.equal(profile.ConditionExpression,'attribute_not_exists(userId)');const w=puts.find(x=>x.TableName==='wallets');assert.equal(w.Item.walletId,'WALLET#CUSTOMER#new-sub');assert.equal(w.Item.availableBalance,0);assert.equal(a.calls.find(c=>c.kind==='AdminSetUserPasswordCommand').input.Permanent,true);});

test('durable deletion marker prevents wallet recreation and token issuance',async()=>{const a=app({closing:true});assert.equal((await a.run()).statusCode,409);assert.ok(!a.calls.some(c=>c.kind==='AdminInitiateAuthCommand'));assert.ok(!a.calls.filter(c=>c.kind==='TransactWriteCommand').some(c=>c.input.TransactItems.some(x=>x.Put?.TableName==='wallets')));});

test('public legal endpoint returns only published text without secrets, OTP or customer lookup',async()=>{const a=app(),r=await a.legalGet();assert.equal(r.statusCode,200);assert.equal(JSON.parse(r.body).bundle.revision,1);assert.deepEqual(a.calls.map(c=>c.kind),['GetCommand']);assert.equal(a.calls[0].input.Key.sk,'CURRENT');});
test('unpublished policy prevents new registration before consuming OTP or creating identity',async()=>{const a=app({noUser:true,legalUnavailable:true});const r=await a.run({code:'123456',name:'مستخدم جديد',termsAccepted:true,privacyAccepted:true,usageAccepted:true,legalAcceptance:legalPin});assert.equal(r.statusCode,503);assert.ok(!a.calls.some(c=>c.kind==='TransactWriteCommand'||c.kind==='AdminCreateUserCommand'));});
test('stale policy or missing policy acknowledgement never consumes OTP or fabricates acceptance',async()=>{for(const pin of [undefined,{...legalPin,revision:2},{...legalPin,digest:'0'.repeat(64)}]){const a=app({noUser:true}),r=await a.run({code:'123456',name:'مستخدم جديد',termsAccepted:true,privacyAccepted:true,usageAccepted:true,legalAcceptance:pin});assert.equal(r.statusCode,409);assert.ok(!a.calls.some(c=>c.kind==='TransactWriteCommand'||c.kind==='AdminCreateUserCommand'));}});
test('registration consent snapshot is tied to verified subject and pinned atomically with OTP',async()=>{const a=app({noUser:true}),r=await a.run({code:'123456',name:'مستخدم جديد',termsAccepted:true,privacyAccepted:true,usageAccepted:true,legalAcceptance:legalPin});assert.equal(r.statusCode,200);const tx=a.calls.filter(c=>c.kind==='TransactWriteCommand').map(c=>c.input.TransactItems);assert.ok(tx[0].some(o=>o.ConditionCheck?.TableName==='legal'&&o.ConditionCheck.ExpressionAttributeValues[':d']===legalPin.digest));const profile=tx.flat().find(o=>o.Put?.TableName==='profiles').Put.Item;assert.equal(profile.legalAcceptance.subjectId,'new-sub');assert.equal(profile.legalAcceptance.revision,1);assert.equal(profile.legalAcceptance.documentSnapshot.documents.length,4);});
