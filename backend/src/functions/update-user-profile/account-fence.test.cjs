const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const {accountGuard}=require('../create-order/account-guard');
function app({revoked=false,race=false}={}){
 const profile={userId:'legacy',cognitoUsername:'username',isActive:true,name:'old'};let update;
 const classes={};for(const name of ['GetCommand','UpdateCommand'])classes[name]=class{constructor(input){this.name=name;this.input=input;}};
 const db={send:async c=>{if(c.name==='GetCommand')return {Item:profile};update=c.input;if(race)throw Object.assign(Error('condition failed'),{name:'ConditionalCheckFailedException'});return {Attributes:{...profile,name:'new'}};}};
 const modules={'@aws-sdk/client-dynamodb':{DynamoDBClient:class{}},'@aws-sdk/lib-dynamodb':{...classes,DynamoDBDocumentClient:{from:()=>db}},'../create-order/account-guard':{accountGuard},'aws-sdk':{CognitoIdentityServiceProvider:class{getUser(){return {promise:async()=>{if(revoked)throw Object.assign(Error(),{code:'NotAuthorizedException'});return {Username:'username',UserAttributes:[{Name:'sub',Value:'subject'}]};}};}}}};
 const exports={};vm.runInNewContext(fs.readFileSync(__dirname+'/index.js','utf8'),{exports,require:n=>modules[n],process:{env:{USERS_TABLE:'profiles',USER_POOL_ID:'pool',USER_POOL_CLIENT_ID:'client'}},console:{log(){},error(){}}});
 const token='h.'+Buffer.from(JSON.stringify({sub:'subject',iss:'https://cognito-idp.us-east-1.amazonaws.com/pool',client_id:'client',token_use:'access'})).toString('base64url')+'.s';
 return {run:()=>exports.handler({httpMethod:'PUT',pathParameters:{user_id:'legacy'},headers:{Authorization:'Bearer '+token},body:JSON.stringify({name:'new'})}),update:()=>update};
}
test('revoked session cannot update profile',async()=>{const f=app({revoked:true});assert.equal((await f.run()).statusCode,401);assert.equal(f.update(),undefined);});
test('profile deletion racing with update returns conflict without success',async()=>{const f=app({race:true});assert.equal((await f.run()).statusCode,409);assert.match(f.update().ConditionExpression,/attribute_exists\(userId\)/);});
test('active profile update keeps ownership and lifecycle guard in atomic write',async()=>{const f=app();assert.equal((await f.run()).statusCode,200);assert.match(f.update().ConditionExpression,/attribute_not_exists\(deletionRequestId\)/);assert.equal(f.update().ExpressionAttributeValues[':binding'],'username');assert.equal(f.update().ExpressionAttributeValues[':name'],'new');});
