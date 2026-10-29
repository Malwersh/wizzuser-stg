'use strict';
const {AsyncLocalStorage}=require('node:async_hooks');
const {createPublicKey,verify}=require('node:crypto');
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient,GetCommand,TransactWriteCommand}=require('@aws-sdk/lib-dynamodb');
const context=new AsyncLocalStorage();
const B='WhizzMerchants_Businesses',D='staging-AccountDeletion';
const C=()=>process.env.WEBSOCKET_CONNECTIONS_TABLE||'WizzUser_websocket_connections_staging';
const S=()=>process.env.WEBSOCKET_SUBSCRIPTIONS_TABLE||'WizzUser_websocket_subscriptions_staging';
const issuer='https://cognito-idp.us-east-1.amazonaws.com/us-east-1_gtCR3ndzT',clientId='4qabvh11nmghmf9fmc6e6ludd2';
const fail=(code,status=403)=>{throw Object.assign(Error(code),{status});};
let jwks,until=0;
async function verifyToken(token){
 try{
  const parts=String(token||'').split('.');if(parts.length!==3)fail('UNAUTHORIZED',401);
  const h=JSON.parse(Buffer.from(parts[0],'base64url')),p=JSON.parse(Buffer.from(parts[1],'base64url'));
  if(h.alg!=='RS256'||typeof h.kid!=='string'||p.iss!==issuer||!['access','id'].includes(p.token_use)||(p.token_use==='id'?p.aud:p.client_id)!==clientId||typeof p.sub!=='string'||!Number.isFinite(p.exp)||p.exp<=Date.now()/1000)fail('UNAUTHORIZED',401);
  if(!jwks||until<Date.now()){const r=await fetch(issuer+'/.well-known/jwks.json',{signal:AbortSignal.timeout(10000)});if(!r.ok)fail('AUTH_UNAVAILABLE',503);jwks=(await r.json()).keys;until=Date.now()+300000;}
  const key=jwks.find(k=>k.kid===h.kid&&k.kty==='RSA');if(!key||!verify('RSA-SHA256',Buffer.from(parts[0]+'.'+parts[1]),createPublicKey({key,format:'jwk'}),Buffer.from(parts[2],'base64url')))fail('UNAUTHORIZED',401);
  return p;
 }catch(e){if(e.status)throw e;fail('UNAUTHORIZED',401);}
}
const get=async(db,table,key)=>(await db.send(new GetCommand({TableName:table,Key:key,ConsistentRead:true}))).Item;
function branchIds(input){const ids=['businessId','business_id','merchantId','merchant_id'].filter(k=>input?.[k]!==undefined).map(k=>input[k]);if(ids.some(v=>typeof v!=='string'||!v.trim()||v.length>150)||new Set(ids).size>1)fail('BRANCH_SCOPE_CONFLICT');return ids[0];}
async function owned(db,scope){
 if(scope.expiresAt<=Date.now()/1000)fail('SESSION_EXPIRED',401);
 const branch=await get(db,B,{businessId:scope.businessId});
 if(!branch||branch.ownerId!==scope.subjectId||branch.cognitoUserId!==scope.subjectId||branch.deletionRequestId)fail('BRANCH_SCOPE_REQUIRED');
 for(const pk of ['ACCOUNT_LIFECYCLE#MERCHANT#'+scope.subjectId,'BUSINESS_LIFECYCLE#MERCHANT#'+scope.businessId])if(await get(db,D,{pk,sk:'META'}))fail('ACCOUNT_CLOSING');
}
function rawDb(){return DynamoDBDocumentClient.from(new DynamoDBClient({region:'us-east-1'}));}
function merchantQuery(q){return ['merchant','business'].includes(q?.entityType)||['merchant','business'].includes(q?.userType);}
function guardConnect(handler,{db=rawDb(),verifyIdentity=verifyToken}={}){return async e=>{
 if(!merchantQuery(e.queryStringParameters))return handler(e);
 try{
  const q=e.queryStringParameters||{},businessId=branchIds(q);if(!businessId)fail('BRANCH_SCOPE_REQUIRED');
  const token=q.token||String(e.headers?.Authorization||e.headers?.authorization||'').replace(/^Bearer\s+/i,'');const claims=await verifyIdentity(token);
  const scope={subjectId:claims.sub,businessId,expiresAt:claims.exp,connectionId:e.requestContext?.connectionId,mode:'connect'};if(!scope.connectionId)fail('CONNECTION_REQUIRED');await owned(db,scope);
  return await context.run(scope,()=>handler({...e,queryStringParameters:{...q,businessId,merchantId:businessId,userId:claims.sub,userType:'merchant',entityType:'business'}}));
 }catch(x){return {statusCode:x.status||503,body:JSON.stringify({code:x.status?x.message:'AUTH_UNAVAILABLE'})};}
};}
const merchantActions=new Set(['register_connection','subscribe_orders','update_order_status','business_busy_status_update','working_hours_update']);
const permitted=new Set(['register_connection','subscribe_orders','ping','heartbeat','connect','connection','register','subscribe_order','unsubscribe_order','subscribe_order_tracking','subscribe_business_status','unsubscribe_business_status','subscribe','unsubscribe']);
function guardDefault(handler,{db=rawDb()}={}){return async e=>{
 try{
  const message=JSON.parse(e.body||'{}'),action=String(message.action||message.type||e.requestContext?.routeKey||'').toLowerCase();
  const connectionId=e.requestContext?.connectionId;if(!connectionId)fail('CONNECTION_REQUIRED');
  const row=await get(db,C(),{connectionId});const marker=row?.merchantScope345;
  if(!marker){if(merchantActions.has(action)||(merchantQuery(message)&&!['subscribe_business_status','unsubscribe_business_status','subscribe','unsubscribe'].includes(action)))fail('MERCHANT_RECONNECT_REQUIRED',401);return handler(e);}
  const scope={...marker,connectionId,mode:'message'};await owned(db,scope);
  if(!permitted.has(action))fail('USE_AUTHORIZED_HTTP_OPERATION');
  const requested=branchIds(message);if(requested&&requested!==scope.businessId)fail('BRANCH_SCOPE_CONFLICT');
  if(['subscribe_order','unsubscribe_order','subscribe_order_tracking'].includes(action)){
   const id=message.orderId||message.order_id;if(typeof id!=='string'||!id||id.length>150)fail('ORDER_SCOPE_REQUIRED');
   const order=await get(db,'WizzOrders',{PK:'ORDER#'+id,SK:'META'});if(!order||(order.businessId||order.storeId||order.merchantId)!==scope.businessId)fail('ORDER_SCOPE_REQUIRED');
  }
  const safe={...message,businessId:scope.businessId,merchantId:scope.businessId,userId:scope.subjectId,entityType:'merchant',userType:'merchant'};
  return await context.run(scope,()=>handler({...e,body:JSON.stringify(safe)}));
 }catch(x){return {statusCode:x.status||503,body:JSON.stringify({code:x.status?x.message:'AUTH_UNAVAILABLE'})};}
};}
function guards(scope,includeConnection=true){return [
 {ConditionCheck:{TableName:B,Key:{businessId:scope.businessId},ConditionExpression:'ownerId=:sub AND cognitoUserId=:sub AND attribute_not_exists(deletionRequestId)',ExpressionAttributeValues:{':sub':scope.subjectId}}},
 ...['ACCOUNT_LIFECYCLE#MERCHANT#'+scope.subjectId,'BUSINESS_LIFECYCLE#MERCHANT#'+scope.businessId].map(pk=>({ConditionCheck:{TableName:D,Key:{pk,sk:'META'},ConditionExpression:'attribute_not_exists(pk)'}})),
 ...(includeConnection?[{ConditionCheck:{TableName:C(),Key:{connectionId:scope.connectionId},...connectionCondition(scope)}}]:[])
];}
function connectionCondition(scope){return {ConditionExpression:'#ms.#sub=:subject AND #ms.#branch=:branch AND #ms.#expires>:now',ExpressionAttributeNames:{'#ms':'merchantScope345','#sub':'subjectId','#branch':'businessId','#expires':'expiresAt'},ExpressionAttributeValues:{':subject':scope.subjectId,':branch':scope.businessId,':now':Math.floor(Date.now()/1000)}};}
function scopedClient(raw){return {send:async command=>{
 const scope=context.getStore(),name=command.constructor.name;if(!scope||!['PutCommand','UpdateCommand','DeleteCommand','TransactWriteCommand','BatchWriteCommand'].includes(name))return raw.send(command);
 const items=name==='TransactWriteCommand'?structuredClone(command.input.TransactItems):name==='BatchWriteCommand'?Object.entries(command.input.RequestItems).flatMap(([TableName,requests])=>requests.map(r=>r.PutRequest?{Put:{TableName,Item:structuredClone(r.PutRequest.Item)}}:{Delete:{TableName,Key:structuredClone(r.DeleteRequest.Key)}})):[{[name.slice(0,-7)]:structuredClone(command.input)}];let connectionWrite=false;
 for(const item of items){const op=item.Put||item.Update||item.Delete;if(!op)fail('INVALID_REALTIME_WRITE');delete op.ReturnValues;if(![C(),S()].includes(op.TableName))fail('INVALID_REALTIME_WRITE');const value=item.Put?.Item||op.Key;
  if(op.TableName===C()){
   if(connectionWrite||value.connectionId!==scope.connectionId)fail('CONNECTION_SCOPE_REQUIRED');connectionWrite=true;
   if(item.Put){item.Put.Item.merchantScope345={subjectId:scope.subjectId,businessId:scope.businessId,expiresAt:scope.expiresAt};item.Put.Item.ttl=Math.min(item.Put.Item.ttl||scope.expiresAt,scope.expiresAt);}
   if(scope.mode==='connect'){op.ConditionExpression='attribute_not_exists(connectionId)';}
   else {const fence=connectionCondition(scope);op.ConditionExpression=(op.ConditionExpression?'('+op.ConditionExpression+') AND ':'')+fence.ConditionExpression;op.ExpressionAttributeNames={...op.ExpressionAttributeNames,...fence.ExpressionAttributeNames};op.ExpressionAttributeValues={...op.ExpressionAttributeValues,...fence.ExpressionAttributeValues};}
  }else if(item.Put){if(value.connectionId!==scope.connectionId)fail('CONNECTION_SCOPE_REQUIRED');const branch=branchIds(value);if(branch&&branch!==scope.businessId)fail('BRANCH_SCOPE_CONFLICT');item.Put.Item.ttl=Math.min(value.ttl||scope.expiresAt,scope.expiresAt);if(typeof value.expiresAt==='number')item.Put.Item.expiresAt=Math.min(value.expiresAt,scope.expiresAt*1000);}
  else if(typeof value.subscriptionId!=='string'||!value.subscriptionId.startsWith(scope.connectionId+'_'))fail('SUBSCRIPTION_SCOPE_REQUIRED');
 }
 return raw.send(new TransactWriteCommand({TransactItems:[...guards(scope,scope.mode!=='connect'&&!connectionWrite),...items]}));
}};}
module.exports={guardConnect,guardDefault,scopedClient,currentScope:()=>context.getStore(),verifyToken,branchIds};
