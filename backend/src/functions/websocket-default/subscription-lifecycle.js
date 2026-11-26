'use strict';
const {GetCommand,TransactWriteCommand}=require('@aws-sdk/lib-dynamodb');
const {CognitoIdentityProviderClient,AdminGetUserCommand}=require('@aws-sdk/client-cognito-identity-provider');
function connectionScopedClient(raw,{connectionId,connectionsTable='WizzUser_websocket_connections_staging',subscriptionsTable='WizzUser_websocket_subscriptions_staging',cognito=new CognitoIdentityProviderClient({region:'us-east-1'})}){
 if(connectionsTable!=='WizzUser_websocket_connections_staging'||subscriptionsTable!=='WizzUser_websocket_subscriptions_staging')throw Error('INVALID_STAGING_TABLE');
 return {send:async command=>{
  if(!['PutCommand','UpdateCommand'].includes(command.constructor.name)||![connectionsTable,subscriptionsTable].includes(command.input.TableName))return raw.send(command);
  const {Item:c}=await raw.send(new GetCommand({TableName:connectionsTable,Key:{connectionId},ConsistentRead:true}));
  if(!c||!c.userId||c.isActive===false)throw Error('CONNECTION_UNAVAILABLE');
  const type=({user:'CUSTOMER',customer:'CUSTOMER',driver:'DRIVER',merchant:'MERCHANT',business:'MERCHANT',guest:'CUSTOMER'})[String(c.userType||c.role||c.entityType||'').toLowerCase()];
  if(!type)throw Error('CONNECTION_IDENTITY_UNAVAILABLE');
  const sub=c.cognitoSub||c.userId;
  if(c.authenticated){const pool=({CUSTOMER:'us-east-1_TpyyrVkEE',DRIVER:'us-east-1_RGTqUXF5C',MERCHANT:'us-east-1_gtCR3ndzT'})[type];const user=await cognito.send(new AdminGetUserCommand({UserPoolId:pool,Username:sub}));if(!user.Enabled||!user.UserAttributes?.some(a=>a.Name==='sub'&&a.Value===sub))throw Error('ACCOUNT_UNAVAILABLE');}
  const input={...command.input};const item=input.Item;
  if(item){
   if(item.connectionId&&item.connectionId!==connectionId)throw Error('CONNECTION_SCOPE_MISMATCH');
   const allowed=[c.userId,sub,...(type==='MERCHANT'&&c.businessId?[c.businessId]:[])];
   if(item.userId&&!allowed.includes(item.userId))throw Error('SUBSCRIPTION_SUBJECT_MISMATCH');
   input.Item={...item,userId:item.userId||c.userId,...(type==='MERCHANT'&&c.businessId&&!item.businessId?{businessId:c.businessId}:{})};
  }
  const fences=[{ConditionCheck:{TableName:'staging-AccountDeletion',Key:{pk:'ACCOUNT_LIFECYCLE#'+type+'#'+sub,sk:'META'},ConditionExpression:'attribute_not_exists(pk)'}}];
  for(const businessId of new Set([item?.businessId,c.businessId].filter(Boolean)))fences.push({ConditionCheck:{TableName:'staging-AccountDeletion',Key:{pk:'BUSINESS_LIFECYCLE#MERCHANT#'+businessId,sk:'META'},ConditionExpression:'attribute_not_exists(pk)'}});
  const binding={ConditionExpression:'userId=:lifecycleUser',ExpressionAttributeValues:{':lifecycleUser':c.userId}};
  if(input.TableName===connectionsTable){if(command.constructor.name!=='UpdateCommand'||input.Key?.connectionId!==connectionId)throw Error('CONNECTION_SCOPE_MISMATCH');input.ConditionExpression=(input.ConditionExpression?'('+input.ConditionExpression+') AND ':'')+binding.ConditionExpression;input.ExpressionAttributeValues={...input.ExpressionAttributeValues,...binding.ExpressionAttributeValues};}
  else fences.push({ConditionCheck:{TableName:connectionsTable,Key:{connectionId},...binding}});
  if(input.ReturnValues&&!['NONE','ALL_NEW'].includes(input.ReturnValues))throw Error('UNSUPPORTED_RETURN_VALUES');const returnValues=input.ReturnValues;delete input.ReturnValues;
  const kind=command.constructor.name.slice(0,-7);const result=await raw.send(new TransactWriteCommand({TransactItems:[...fences,{[kind]:input}]}));
  if(returnValues==='ALL_NEW')return {...result,Attributes:(await raw.send(new GetCommand({TableName:input.TableName,Key:input.Key,ConsistentRead:true}))).Item};return result;
 }};
}
module.exports={connectionScopedClient};
