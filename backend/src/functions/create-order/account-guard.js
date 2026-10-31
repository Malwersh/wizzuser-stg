'use strict';
const fail=(code,statusCode)=>Object.assign(new Error(code),{code,statusCode});

// GetUser validates the access token with Cognito before any claims are used.
async function accountGuard({event,userId,getUser,getProfile,pool,clientId,profilesTable}){
 const registered=!!userId&&userId!=='guest';
 const token=/^Bearer (\S+)$/.exec(event.headers?.Authorization||event.headers?.authorization||'')?.[1];
 if(!registered)return {sub:null,condition:null};
 if(!token)throw fail('AUTH_REQUIRED',401);
 let user;
 try{user=await getUser(token);}catch(e){
  if(['NotAuthorizedException','UserNotFoundException','InvalidParameterException'].includes(e.code||e.name))throw fail('AUTH_REQUIRED',401);
  throw fail('AUTH_UNAVAILABLE',503);
 }
 let claims;try{claims=JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString());}catch(_){throw fail('AUTH_REQUIRED',401);}
 const attrs=Object.fromEntries((user.UserAttributes||[]).map(a=>[a.Name,a.Value]));
 if(!attrs.sub||claims.sub!==attrs.sub||claims.iss!==`https://cognito-idp.us-east-1.amazonaws.com/${pool}`||claims.client_id!==clientId||claims.token_use!=='access')throw fail('AUTH_REQUIRED',401);
 const profile=await getProfile(userId);
 if(!profile)throw fail('ACCOUNT_UNAVAILABLE',403);
 const names={'#active':'isActive'},values={':yes':true,':subject':attrs.sub};
 let binding;
 if(profile.userId===attrs.sub)binding='userId = :binding',values[':binding']=attrs.sub;
 else if(profile.cognitoSub===attrs.sub)binding='cognitoSub = :binding',values[':binding']=attrs.sub;
 else if(profile.cognitoUsername===user.Username)binding='cognitoUsername = :binding',values[':binding']=user.Username;
 else throw fail('ACCOUNT_MISMATCH',403);
 if(profile.isActive===false||profile.deletionRequestId)throw fail('ACCOUNT_UNAVAILABLE',409);
 return {sub:attrs.sub,condition:{ConditionCheck:{TableName:profilesTable,Key:{userId},ConditionExpression:`attribute_exists(userId) AND (${binding}) AND (attribute_not_exists(cognitoSub) OR cognitoSub = :subject) AND (attribute_not_exists(#active) OR #active = :yes) AND attribute_not_exists(deletionRequestId)`,ExpressionAttributeNames:names,ExpressionAttributeValues:values}}};
}
module.exports={accountGuard};
