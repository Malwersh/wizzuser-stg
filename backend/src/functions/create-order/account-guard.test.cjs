const test=require('node:test'),assert=require('node:assert/strict');
const {accountGuard}=require('./account-guard');
const claims={sub:'subject',iss:'https://cognito-idp.us-east-1.amazonaws.com/pool',client_id:'client',token_use:'access'};
function fixture({profile={userId:'legacy',cognitoUsername:'username',isActive:true},overrides={},authError}={}){
 const token='header.'+Buffer.from(JSON.stringify({...claims,...overrides})).toString('base64url')+'.signature';
 return {event:{headers:{Authorization:'Bearer '+token}},userId:'legacy',pool:'pool',clientId:'client',profilesTable:'profiles',getUser:async()=>{if(authError)throw Object.assign(Error(),{name:authError});return {Username:'username',UserAttributes:[{Name:'sub',Value:'subject'}]};},getProfile:async()=>profile};
}
test('registered account cannot create orders without verified authentication',async()=>{const f=fixture();f.event={};await assert.rejects(accountGuard(f),/AUTH_REQUIRED/);});
test('revoked token cannot fall back to decoded claims',async()=>{await assert.rejects(accountGuard(fixture({authError:'NotAuthorizedException'})),/AUTH_REQUIRED/);});
test('driver pool token cannot create customer order',async()=>{await assert.rejects(accountGuard(fixture({overrides:{iss:'driver-pool'}})),/AUTH_REQUIRED/);});
test('valid user cannot submit another profile ID',async()=>{await assert.rejects(accountGuard(fixture({profile:{userId:'legacy',cognitoUsername:'someone-else'}})),/ACCOUNT_MISMATCH/);});
test('deletion fence blocks an otherwise valid session',async()=>{await assert.rejects(accountGuard(fixture({profile:{userId:'legacy',cognitoUsername:'username',deletionRequestId:'pending'}})),/ACCOUNT_UNAVAILABLE/);});
test('deleted profile cannot be recreated through order creation',async()=>{await assert.rejects(accountGuard(fixture({profile:null})),/ACCOUNT_UNAVAILABLE/);});
test('legacy binding produces atomic profile fence for order write',async()=>{const r=await accountGuard(fixture());assert.equal(r.sub,'subject');assert.equal(r.condition.ConditionCheck.Key.userId,'legacy');assert.match(r.condition.ConditionCheck.ConditionExpression,/attribute_not_exists\(deletionRequestId\)/);assert.equal(r.condition.ConditionCheck.ExpressionAttributeValues[':binding'],'username');});
test('explicit guest order preserves independent guest flow',async()=>{const f=fixture();f.userId=null;f.event={};f.getUser=()=>{throw Error('unexpected');};assert.deepEqual(await accountGuard(f),{sub:null,condition:null});});
