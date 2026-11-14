'use strict';
const {GetCommand}=require('@aws-sdk/lib-dynamodb');
const {accountGuard}=require('../create-order/account-guard');
const {customerState,regionAncestors,fail}=require('./offer-eligibility');
async function offerContext(db,event,body){
 let profile;const token=event.headers?.Authorization||event.headers?.authorization;
 if(token&&(!body.userId||body.userId==='guest'))fail('OFFER_ACCOUNT_REQUIRED');
 // Cognito GetUser validates the access token; native fetch avoids an unbundled SDK dependency.
 const getUser=async AccessToken=>{const response=await fetch('https://cognito-idp.us-east-1.amazonaws.com/',{method:'POST',headers:{'Content-Type':'application/x-amz-json-1.1','X-Amz-Target':'AWSCognitoIdentityProviderService.GetUser'},body:JSON.stringify({AccessToken}),signal:AbortSignal.timeout(10000)});const result=await response.json();if(!response.ok)throw Object.assign(Error('Cognito token validation failed'),{code:String(result.__type||'AuthUnavailable').split('#').pop()});return result;};
 const guarded=await accountGuard({event,userId:body.userId,pool:process.env.USER_POOL_ID||'us-east-1_TpyyrVkEE',clientId:process.env.USER_POOL_CLIENT_ID||'4a9e8o3em311eq2rgckp0pd2s9',profilesTable:process.env.USERS_TABLE||'WizzUser_users_staging',getUser,getProfile:async id=>profile=(await db.send(new GetCommand({TableName:process.env.USERS_TABLE||'WizzUser_users_staging',Key:{userId:id},ConsistentRead:true}))).Item});
 const identity=guarded.sub?{sub:guarded.sub,userId:body.userId,profile}:null;
 // Region scope is based on a saved address owned by the verified customer.
 let regionId,addressCondition;
 const addressId=body.addressId||body.deliveryAddress?.id;
 if(identity&&addressId){const a=(await db.send(new GetCommand({TableName:process.env.ADDRESSES_TABLE||'WizzUser_addresses_staging',Key:{addressId},ConsistentRead:true}))).Item;if(!a||a.userId!==identity.userId)fail('OFFER_ADDRESS_UNAVAILABLE');regionId=a.regionId||a.region_id;
 if(body.deliveryAddress&&['latitude','longitude'].some(k=>a[k]!=null&&Number(body.deliveryAddress[k])!==Number(a[k])))fail('OFFER_ADDRESS_UNAVAILABLE');
 const names={},values={},checks=[];for(const [i,k] of ['userId','regionId','region_id','latitude','longitude'].entries()){names['#a'+i]=k;if(a[k]===undefined)checks.push('attribute_not_exists(#a'+i+')');else{values[':a'+i]=a[k];checks.push('#a'+i+'=:a'+i);}}
 addressCondition={ConditionCheck:{TableName:process.env.ADDRESSES_TABLE||'WizzUser_addresses_staging',Key:{addressId},ConditionExpression:checks.join(' AND '),ExpressionAttributeNames:names,ExpressionAttributeValues:values}};}
 if(guarded.condition){const check=guarded.condition.ConditionCheck;for(const [i,k] of ['createdAt','isVip'].entries()){const n='#offerProfile'+i;check.ExpressionAttributeNames[n]=k;if(profile[k]===undefined)check.ConditionExpression+=' AND attribute_not_exists('+n+')';else{check.ExpressionAttributeValues[':offerProfile'+i]=profile[k];check.ConditionExpression+=' AND '+n+'=:offerProfile'+i;}}}
 return {addressCondition,identity,customer:await customerState(db,identity),regionIds:await regionAncestors(db,regionId),guarded};
}
module.exports={offerContext};
