const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const {digest}=require('./challenge-policy');
const time=()=>Math.floor(Date.now()/1000);
const phone='+9647831367435';
function app({verified=true,enabled=true,used=false,expired=false,wrongProfile=false,noUser=false,canonical=false}={}){
 const calls=[],classes={};for(const kind of ['GetCommand','PutCommand','QueryCommand','UpdateCommand','TransactWriteCommand','GetSecretValueCommand','ListUsersCommand','AdminCreateUserCommand','AdminSetUserPasswordCommand','AdminInitiateAuthCommand','AdminRespondToAuthChallengeCommand'])classes[kind]=class{constructor(input){this.kind=kind;this.input=input;}};
 const user={Username:'cognito-original',Enabled:enabled,UserStatus:'CONFIRMED',Attributes:[{Name:'sub',Value:'original-sub'},{Name:'phone_number',Value:phone},{Name:'phone_number_verified',Value:String(verified)},{Name:'email',Value:'owner@test.invalid'},{Name:'email_verified',Value:'true'}]};
 const profile={userId:canonical?'original-sub':'legacy-user-id',cognitoUsername:wrongProfile?'different-user':'owner@test.invalid',email:'owner@test.invalid',name:'غيث',phone,isActive:true};
 let provisionRecord;
 const send=async c=>{calls.push(c);const i=c.input;
  if(c.kind==='GetSecretValueCommand')return {SecretString:JSON.stringify({hmacKey:'test-key',apiKey:'test-only'})};
  if(c.kind==='GetCommand'){
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
 const sandbox={exports:{},require:n=>modules[n]||require(n.startsWith('./')?__dirname+'/'+n:n),process:{env:{ENVIRONMENT:'staging',OTP_TABLE:'otp',USERS_TABLE:'profiles',WALLETS_TABLE:'wallets',USER_POOL_ID:'pool',CLIENT_ID:'client'}},console:{error(){}},fetch:async()=>({ok:true}),AbortSignal,Buffer};
 vm.runInNewContext(fs.readFileSync(__dirname+'/index.js','utf8'),sandbox);
 return {calls,run:(body={code:'123456'})=>sandbox.exports.handler({path:'/auth/phone/verify',body:JSON.stringify({phone,sessionId:'session',...body})})};
}
test('verified legacy phone authenticates original Cognito username and profile ID',async()=>{
 const a=app(),r=await a.run();assert.equal(r.statusCode,200);assert.equal(JSON.parse(r.body).user.userId,'legacy-user-id');
 assert.equal(a.calls.find(c=>c.kind==='AdminInitiateAuthCommand').input.AuthParameters.USERNAME,'cognito-original');assert.ok(!a.calls.some(c=>c.kind==='AdminCreateUserCommand'||c.kind==='AdminSetUserPasswordCommand'));
 const w=a.calls.find(c=>c.kind==='PutCommand'&&c.input.TableName==='wallets');assert.equal(w.input.Item.walletId,'WALLET#CUSTOMER#original-sub');assert.equal(w.input.ConditionExpression,'attribute_not_exists(walletId)');assert.ok(!a.calls.some(c=>c.kind==='UpdateCommand'&&c.input.TableName==='wallets'));
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

test('new phone creates a confirmed identity, matching profile and zero wallet only after OTP and consent',async()=>{const a=app({noUser:true}),r=await a.run({code:'123456',name:'مستخدم جديد',termsAccepted:true,privacyAccepted:true});assert.equal(r.statusCode,200);assert.equal(JSON.parse(r.body).user.userId,'new-sub');const create=a.calls.findIndex(c=>c.kind==='AdminCreateUserCommand');assert.ok(create>a.calls.findIndex(c=>c.kind==='TransactWriteCommand'));const profile=a.calls.find(c=>c.kind==='PutCommand'&&c.input.TableName==='profiles');assert.equal(profile.input.Item.cognitoSub,'new-sub');assert.equal(profile.input.ConditionExpression,'attribute_not_exists(userId)');const w=a.calls.find(c=>c.kind==='PutCommand'&&c.input.TableName==='wallets');assert.equal(w.input.Item.walletId,'WALLET#CUSTOMER#new-sub');assert.equal(w.input.Item.availableBalance,0);assert.equal(a.calls.find(c=>c.kind==='AdminSetUserPasswordCommand').input.Permanent,true);});
