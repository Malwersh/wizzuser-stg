const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const {accountGuard}=require('../create-order/account-guard');
function app({revoked=false,other=false,locked=false,conflictingBinding=false}={}) {
 let reads=0;
 const profile={userId:'subject',name:'Customer',...(conflictingBinding?{cognitoSub:'other'}:{}),notification_settings:{sound_enabled:false},...(locked?{deletionRequestId:'pending'}:{})};
 const modules={'../shared/customer-promotion-consent-449':require('../shared/customer-promotion-consent-449'),'@aws-sdk/client-dynamodb':{DynamoDBClient:class{}},'@aws-sdk/lib-dynamodb':{GetCommand:class{constructor(input){this.input=input;}},DynamoDBDocumentClient:{from:()=>({send:async()=>{reads++;return {Item:profile};}})}},'../create-order/account-guard':{accountGuard},'@aws-sdk/client-cognito-identity-provider':{GetUserCommand:class{},CognitoIdentityProviderClient:class{async send(){if(revoked)throw Object.assign(Error(),{code:'NotAuthorizedException'});return {Username:'username',UserAttributes:[{Name:'sub',Value:other?'other':'subject'}]};}}}};
 const exports={};vm.runInNewContext(fs.readFileSync(__dirname+'/index.js','utf8'),{exports,require:n=>modules[n],process:{env:{USER_POOL_ID:'pool',USER_POOL_CLIENT_ID:'client',USERS_TABLE:'users'}},console:{log(){},error(){}}});
 const token='h.'+Buffer.from(JSON.stringify({sub:other?'other':'subject',iss:'https://cognito-idp.us-east-1.amazonaws.com/pool',client_id:'client',token_use:'access'})).toString('base64url')+'.s';
 return {run:(authenticated=true)=>exports.handler({httpMethod:'GET',pathParameters:{user_id:'subject'},headers:authenticated?{Authorization:'Bearer '+token}:{}}),reads:()=>reads};
}
test('anonymous read denied before database read',async()=>{const f=app();assert.equal((await f.run(false)).statusCode,401);assert.equal(f.reads(),0);});
test('revoked session denied before database read',async()=>{const f=app({revoked:true});assert.equal((await f.run()).statusCode,401);assert.equal(f.reads(),0);});
test('different owner cannot receive profile',async()=>{assert.equal((await app({other:true}).run()).statusCode,403);});
test('deletion-locked account cannot receive profile',async()=>{assert.equal((await app({locked:true}).run()).statusCode,409);});
test('owner receives profile and saved preferences',async()=>{const r=await app().run();assert.equal(r.statusCode,200);assert.equal(JSON.parse(r.body).data.notification_settings.sound_enabled,false);});

test('conflicting Cognito binding cannot leak a path-matched profile',async()=>{assert.equal((await app({conflictingBinding:true}).run()).statusCode,403);});
