'use strict';
const {CognitoJwtVerifier}=require('aws-jwt-verify');
const cognito=new (require('aws-sdk').CognitoIdentityServiceProvider)({region:'us-east-1'});
const {GetCommand}=require('@aws-sdk/lib-dynamodb');
const POOLS=[
 {kind:'CUSTOMER',userPoolId:'us-east-1_TpyyrVkEE',clientId:'4a9e8o3em311eq2rgckp0pd2s9'},
 {kind:'DRIVER',userPoolId:'us-east-1_RGTqUXF5C',clientId:'2d26d3muq0vvcuf42lkpgmkgsr'},
 {kind:'MERCHANT',userPoolId:'us-east-1_gtCR3ndzT',clientId:'4qabvh11nmghmf9fmc6e6ludd2'},
];
const verifier=CognitoJwtVerifier.create(POOLS.map(p=>({userPoolId:p.userPoolId,clientId:p.clientId,tokenUse:null})));
async function websocketIdentity(token,db){
 const claims=await verifier.verify(token),pool=POOLS.find(p=>claims.iss==='https://cognito-idp.us-east-1.amazonaws.com/'+p.userPoolId);
 if(!pool)throw Error('UNAUTHORIZED');
 const live=await cognito.adminGetUser({UserPoolId:pool.userPoolId,Username:claims.sub}).promise();
 const attrs=Object.fromEntries((live.UserAttributes||[]).map(a=>[a.Name,a.Value]));
 if(!live.Enabled||attrs.sub!==claims.sub)throw Error('ACCOUNT_UNAVAILABLE');
 const key={pk:'ACCOUNT_LIFECYCLE#'+pool.kind+'#'+claims.sub,sk:'META'};
 const {Item}=await db.send(new GetCommand({TableName:'staging-AccountDeletion',Key:key,ConsistentRead:true}));
 if(Item)throw Error('ACCOUNT_UNAVAILABLE');
 return {...claims,email:attrs.email,email_verified:attrs.email_verified==='true',name:attrs.name,userPoolKind:pool.kind,lifecycleGuard:{ConditionCheck:{TableName:'staging-AccountDeletion',Key:key,ConditionExpression:'attribute_not_exists(pk)'}}};
}
module.exports={websocketIdentity};
