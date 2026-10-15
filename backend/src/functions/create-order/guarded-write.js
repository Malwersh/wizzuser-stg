'use strict';
const {GetCommand,TransactWriteCommand,UpdateCommand}=require('@aws-sdk/lib-dynamodb');
const {accountGuard}=require('./account-guard');
const cognito=new (require('aws-sdk').CognitoIdentityServiceProvider)();

// A per-request context, never a mutable global: warm Lambda invocations cannot
// accidentally reuse another customer's identity or lifecycle fence.
async function writeContext(db,event,userId){
 const result=await accountGuard({event,userId,pool:process.env.USER_POOL_ID,clientId:process.env.USER_POOL_CLIENT_ID,profilesTable:process.env.USERS_TABLE,
  getUser:token=>cognito.getUser({AccessToken:token}).promise(),
  getProfile:async id=>(await db.send(new GetCommand({TableName:process.env.USERS_TABLE,Key:{userId:id},ConsistentRead:true}))).Item});
 if(!result.condition)throw Object.assign(Error('AUTH_REQUIRED'),{statusCode:401});
 const write=guardedWriter(db,result.condition.ConditionCheck);
 write.fence=result.condition;
 return write;
}
function guardedWriter(db,fence){
 return async(kind,input)=>{
  if(!['Put','Update','Delete'].includes(kind))throw Error('INVALID_WRITE');
  // DynamoDB forbids two operations on the same item in one transaction.
  if(input.TableName===fence.TableName){
   if(kind!=='Update'||JSON.stringify(input.Key)!==JSON.stringify(fence.Key))throw Error('INVALID_PROFILE_WRITE');
   const merge=(a,b)=>{for(const k of Object.keys(b))if(k in a&&a[k]!==b[k])throw Error('EXPRESSION_CONFLICT');return {...a,...b};};
   return db.send(new UpdateCommand({...input,ConditionExpression:input.ConditionExpression?`(${input.ConditionExpression}) AND (${fence.ConditionExpression})`:fence.ConditionExpression,
    ExpressionAttributeNames:merge(input.ExpressionAttributeNames||{},fence.ExpressionAttributeNames||{}),ExpressionAttributeValues:merge(input.ExpressionAttributeValues||{},fence.ExpressionAttributeValues||{})}));
  }
  if(input.ReturnValues&&!['NONE','ALL_NEW'].includes(input.ReturnValues))throw Error('TRANSACTION_RETURN_VALUES_NOT_SUPPORTED');
  if(input.ReturnValues==='ALL_NEW'&&kind!=='Update')throw Error('INVALID_RETURN_VALUES');
  const write={...input};delete write.ReturnValues;
  await db.send(new TransactWriteCommand({TransactItems:[{ConditionCheck:fence},{[kind]:write}]}));
  if(input.ReturnValues==='ALL_NEW'){
   const {Item}=await db.send(new GetCommand({TableName:input.TableName,Key:input.Key,ConsistentRead:true}));
   if(!Item)throw Object.assign(Error('STATE_CHANGED'),{statusCode:409});
   return {Attributes:Item};
  }
  return {};
 };
}
module.exports={writeContext,guardedWriter};
