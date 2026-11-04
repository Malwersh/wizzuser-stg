'use strict';
const {AsyncLocalStorage}=require('node:async_hooks');
const {createPublicKey,verify}=require('node:crypto');
const {DynamoDBClient}=require('@aws-sdk/client-dynamodb');
const {DynamoDBDocumentClient,GetCommand,TransactWriteCommand}=require('@aws-sdk/lib-dynamodb');
const {CognitoIdentityProviderClient,AdminGetUserCommand}=require('@aws-sdk/client-cognito-identity-provider');
const {ApiGatewayManagementApiClient,PostToConnectionCommand}=require('@aws-sdk/client-apigatewaymanagementapi');
const C='WizzUser_websocket_connections_staging',S='WizzUser_websocket_subscriptions_staging',D='staging-AccountDeletion',P='WhizzDrivers_staging',L='WizzDriverLiveState_staging',U='WizzUser_users_staging',O='WizzOrders';
const roles={CUSTOMER:{pool:'us-east-1_TpyyrVkEE',client:'4a9e8o3em311eq2rgckp0pd2s9'},DRIVER:{pool:'us-east-1_RGTqUXF5C',client:'2d26d3muq0vvcuf42lkpgmkgsr'}};
const context=new AsyncLocalStorage(),keyCache=new Map();
const fail=(code,status=403)=>{throw Object.assign(Error(code),{status});};
const valid=v=>typeof v==='string'&&/^[A-Za-z0-9][A-Za-z0-9_:#.\-]{0,149}$/.test(v);
const dbClient=()=>DynamoDBDocumentClient.from(new DynamoDBClient({region:'us-east-1'}),{marshallOptions:{removeUndefinedValues:true}});
const get=async(db,TableName,Key)=>(await db.send(new GetCommand({TableName,Key,ConsistentRead:true}))).Item;
const ckey=id=>({connectionId:id});
async function verifyToken(token){
 try{
  const parts=String(token||'').split('.');if(parts.length!==3)fail('UNAUTHORIZED',401);
  const header=JSON.parse(Buffer.from(parts[0],'base64url')),claims=JSON.parse(Buffer.from(parts[1],'base64url'));
  const role=Object.keys(roles).find(r=>claims.iss===`https://cognito-idp.us-east-1.amazonaws.com/${roles[r].pool}`),cfg=roles[role];
  if(!cfg||header.alg!=='RS256'||typeof header.kid!=='string'||!['id','access'].includes(claims.token_use)||(claims.token_use==='id'?claims.aud:claims.client_id)!==cfg.client||!valid(claims.sub)||!Number.isFinite(claims.exp)||claims.exp<=Date.now()/1000||claims.nbf!=null&&claims.nbf>Date.now()/1000+30)fail('UNAUTHORIZED',401);
  let keys=keyCache.get(claims.iss);
  for(let attempt=0;attempt<2;attempt++){
   if(!keys||keys.until<Date.now()||attempt){const r=await fetch(claims.iss+'/.well-known/jwks.json',{signal:AbortSignal.timeout(10000)});if(!r.ok)fail('AUTH_UNAVAILABLE',503);keys={values:(await r.json()).keys,until:Date.now()+300000};keyCache.set(claims.iss,keys);}
   const key=keys.values?.find(k=>k.kid===header.kid&&k.kty==='RSA');if(!key)continue;
   if(!verify('RSA-SHA256',Buffer.from(parts[0]+'.'+parts[1]),createPublicKey({key,format:'jwk'}),Buffer.from(parts[2],'base64url')))fail('UNAUTHORIZED',401);
   return {role,claims};
  }
  fail('UNAUTHORIZED',401);
 }catch(e){if(e.status)throw e;fail('UNAUTHORIZED',401);}
}
function isMerchant(q){return ['merchant','business'].includes(q?.userType)||['merchant','business'].includes(q?.entityType)||(!q?.userType&&!q?.entityType&&(q?.businessId||q?.merchantId));}
function requestedRole(q){const types=[q?.userType,q?.entityType].filter(Boolean);if(types.some(t=>!['driver','customer','user','guest'].includes(t)))fail('IDENTITY_ROLE_MISMATCH');const role=types.includes('driver')?'DRIVER':types.includes('guest')?'GUEST':'CUSTOMER';if(types.includes('driver')&&types.some(t=>t!=='driver'))fail('IDENTITY_ROLE_MISMATCH');return role;}
async function live(db,cognito,scope){
 if(scope.expiresAt<=Date.now()/1000)fail('SESSION_EXPIRED',401);
 if(scope.role==='GUEST')return;
 const user=await cognito.send(new AdminGetUserCommand({UserPoolId:roles[scope.role].pool,Username:scope.subjectId}));
 const attrs=Object.fromEntries((user.UserAttributes||[]).map(a=>[a.Name,a.Value]));if(!user.Enabled||attrs.sub!==scope.subjectId)fail('ACCOUNT_UNAVAILABLE',401);
 scope.username=user.Username;scope.verifiedEmail=attrs.email_verified==='true'?attrs.email:null;
 for(const id of new Set([scope.subjectId,scope.role==='DRIVER'?scope.driverId:null].filter(Boolean)))if(await get(db,D,{pk:'ACCOUNT_LIFECYCLE#'+scope.role+'#'+id,sk:'META'}))fail('ACCOUNT_CLOSING');
 if(scope.role==='DRIVER'){
  const profile=await get(db,P,{driverId:scope.driverId});
  if(!profile||profile.driverId!==scope.driverId||(profile.driverId!==scope.subjectId&&(profile.cognitoSub??profile.cognitoUserId)!==scope.subjectId)||profile.deletionRequestId||profile.deletedAt||profile.isDeleted===true)fail('DRIVER_IDENTITY_UNAVAILABLE');
  scope.profile=profile;
 }
}
function marker(scope){return {version:1,role:scope.role,subjectId:scope.subjectId,expiresAt:scope.expiresAt,...(scope.driverId?{driverId:scope.driverId}:{})};}
function accountFences(scope){return scope.role==='GUEST'?[]:[...new Set([scope.subjectId,scope.driverId].filter(Boolean))].map(id=>({ConditionCheck:{TableName:D,Key:{pk:'ACCOUNT_LIFECYCLE#'+scope.role+'#'+id,sk:'META'},ConditionExpression:'attribute_not_exists(pk)'}}));}
function connectionCondition(scope){return {ConditionExpression:'#scope.#sub=:sub AND #scope.#role=:role AND #scope.#expires>:now',ExpressionAttributeNames:{'#scope':'identityScope346','#sub':'subjectId','#role':'role','#expires':'expiresAt'},ExpressionAttributeValues:{':sub':scope.subjectId,':role':scope.role,':now':Math.floor(Date.now()/1000)}};}
function profileFence(scope){return scope.role==='DRIVER'?{ConditionCheck:{TableName:P,Key:{driverId:scope.driverId},ConditionExpression:'driverId=:id AND attribute_not_exists(deletionRequestId)'+(scope.driverId===scope.subjectId?'':' AND #owner=:sub'),...(scope.driverId===scope.subjectId?{}:{ExpressionAttributeNames:{'#owner':scope.profile.cognitoSub!==undefined?'cognitoSub':'cognitoUserId'}}),ExpressionAttributeValues:{':id':scope.driverId,...(scope.driverId===scope.subjectId?{}:{':sub':scope.subjectId})}}}:null;}
function fences(scope,withConnection=true){return [...accountFences(scope),...(profileFence(scope)?[profileFence(scope)]:[]),...(withConnection?[{ConditionCheck:{TableName:C,Key:ckey(scope.connectionId),...connectionCondition(scope)}}]:[])];}
async function write(db,scope,items,extra=[]){return db.send(new TransactWriteCommand({TransactItems:[...fences(scope),...extra,...items]}));}
async function customerIdentity(db,scope,id){
 if(!valid(id))fail('CUSTOMER_SCOPE_REQUIRED');
 if(id===scope.subjectId)return [];
 const p=await get(db,U,{userId:id});
 if(!p||p.deletionRequestId||p.isActive===false)fail('CUSTOMER_SCOPE_REQUIRED');
 let field,value;
 if(p.cognitoSub===scope.subjectId){field='cognitoSub';value=scope.subjectId;}
 else if(p.cognitoUsername===scope.username&&scope.username){field='cognitoUsername';value=scope.username;}
 else if(scope.verifiedEmail&&p.email===scope.verifiedEmail&&p.cognitoUsername===scope.verifiedEmail){field='cognitoUsername';value=scope.verifiedEmail;}
 else fail('CUSTOMER_SCOPE_REQUIRED');
 return [{ConditionCheck:{TableName:U,Key:{userId:id},ConditionExpression:'#owner=:owner AND attribute_not_exists(deletionRequestId)',ExpressionAttributeNames:{'#owner':field},ExpressionAttributeValues:{':owner':value}}}];
}
async function authorizeOrder(db,scope,id){
 if(!valid(id))fail('ORDER_SCOPE_REQUIRED');
 const row=await get(db,O,{PK:'ORDER#'+id,SK:'META'});if(!row)fail('ORDER_SCOPE_REQUIRED');
 if(scope.role==='CUSTOMER'){
  const owner=row.userSub||row.customerSubjectId||row.userId||row.customerId;if(!owner)fail('AUTHENTICATED_ORDER_REQUIRED');const alias=await customerIdentity(db,scope,owner);const field=row.userSub?'userSub':row.customerSubjectId?'customerSubjectId':row.userId?'userId':'customerId';
  return [...alias,{ConditionCheck:{TableName:O,Key:{PK:'ORDER#'+id,SK:'META'},ConditionExpression:'#owner=:owner',ExpressionAttributeNames:{'#owner':field},ExpressionAttributeValues:{':owner':owner}}}];
 }
 if(scope.role==='DRIVER'){
  if(![scope.driverId,scope.subjectId].includes(row.driverId))fail('ORDER_SCOPE_REQUIRED');
  return [{ConditionCheck:{TableName:O,Key:{PK:'ORDER#'+id,SK:'META'},ConditionExpression:'driverId=:driver',ExpressionAttributeValues:{':driver':row.driverId}}}];
 }
 fail('AUTHENTICATED_ORDER_REQUIRED');
}
function guardConnect(handler,{db=dbClient(),cognito=new CognitoIdentityProviderClient({region:'us-east-1'}),verifyIdentity=verifyToken}={}){return async e=>{
 const q=e.queryStringParameters||{};if(isMerchant(q))return handler(e);
 try{
  const connectionId=e.requestContext?.connectionId;if(!connectionId)fail('CONNECTION_REQUIRED');
  const token=q.token||String(e.headers?.Authorization||e.headers?.authorization||'').replace(/^Bearer\s+/i,'');
  let scope;
  if(token){
   const identity=await verifyIdentity(token),request=requestedRole(q);if(request!=='CUSTOMER'&&request!==identity.role||identity.role==='DRIVER'&&request!=='DRIVER')fail('IDENTITY_ROLE_MISMATCH');
   scope={role:identity.role,subjectId:identity.claims.sub,expiresAt:identity.claims.exp,connectionId,mode:'connect'};
   if(scope.role==='DRIVER'){
    const ids=[identity.claims.sub,identity.claims.username,identity.claims['cognito:username']].filter(valid);let profile;
    for(const id of [...new Set(ids)]){const p=await get(db,P,{driverId:id});if(p&&(p.driverId===scope.subjectId||(p.cognitoSub??p.cognitoUserId)===scope.subjectId)){profile=p;break;}}
    if(!profile)fail('DRIVER_IDENTITY_UNAVAILABLE');scope.driverId=profile.driverId;
    for(const id of [q.driverId,q.userId].filter(Boolean))if(![scope.driverId,scope.subjectId].includes(id))fail('DRIVER_SCOPE_REQUIRED');
   }else if(q.userId&&!String(q.userId).startsWith('GUEST#')&&q.userId!==scope.subjectId){/* User aliases are verified at subscription time; never authority here. */}
   await live(db,cognito,scope);
  }else{
   if(requestedRole(q)==='DRIVER'||q.driverId)fail('UNAUTHORIZED',401);
   scope={role:'GUEST',subjectId:'GUEST#'+connectionId,expiresAt:Math.floor(Date.now()/1000)+7200,connectionId,mode:'connect'};
  }
  const normalized={...q,userId:scope.subjectId,userType:scope.role==='DRIVER'?'driver':scope.role==='GUEST'?'guest':'customer',entityType:scope.role==='DRIVER'?'driver':scope.role==='GUEST'?'guest':'customer',...(scope.driverId?{driverId:scope.driverId}:{})};
  if(scope.role!=='DRIVER')delete normalized.driverId;
  delete normalized.orderId;delete normalized.guestToken;
  return await context.run(scope,()=>handler({...e,queryStringParameters:normalized}));
 }catch(error){return {statusCode:error.status||503,body:JSON.stringify({code:error.status?error.message:'AUTH_UNAVAILABLE'})};}
};}
async function send(event,payload){const api=event.requestContext?.apiId,stage=event.requestContext?.stage;if(!api||!stage)fail('REALTIME_CONFIGURATION',503);const client=new ApiGatewayManagementApiClient({region:'us-east-1',endpoint:`https://${api}.execute-api.us-east-1.amazonaws.com/${stage}`});await client.send(new PostToConnectionCommand({ConnectionId:event.requestContext.connectionId,Data:Buffer.from(JSON.stringify(payload))}));}
function guardDefault(handler,{db=dbClient(),cognito=new CognitoIdentityProviderClient({region:'us-east-1'}),post=send,verifyIdentity=verifyToken}={}){return async e=>{
 let scope;
 try{
  const connectionId=e.requestContext?.connectionId;if(!connectionId)fail('CONNECTION_REQUIRED');
  const row=await get(db,C,ckey(connectionId));if(row?.merchantScope345)return handler(e);
  const m=JSON.parse(e.body||'{}');if(!m||Array.isArray(m)||typeof m!=='object')fail('INVALID_MESSAGE',400);
  const action=String(m.action||m.type||e.requestContext?.routeKey||'').toLowerCase();
  if(!row?.identityScope346 || row.identityScope346.version!==1)fail('REALTIME_RECONNECT_REQUIRED',401);
  if(row.isActive===false || row.status==='disconnected')fail('SESSION_EXPIRED',401);
  scope={...row.identityScope346,connectionId,mode:'message'};if(!['CUSTOMER','DRIVER','GUEST'].includes(scope.role))fail('UNAUTHORIZED',401);
  await live(db,cognito,scope);
  const now=new Date().toISOString();
  const ack=async type=>{await post(e,{type,action,...(scope.role==='DRIVER'?{driverId:scope.subjectId,userType:'driver'}:{}),timestamp:now});return {statusCode:200,body:'OK'};};
  if(['heartbeat','ping','connection','connect'].includes(action))return ack(action==='ping'?'pong':'heartbeat_ack');
  if(['subscribe','subscribe_business_status','unsubscribe','unsubscribe_business_status'].includes(action)){
   const id=m.business_id||m.businessId||m.id;if(id!=null&&!valid(id))fail('PUBLIC_SCOPE_REQUIRED');const subscriptionId=connectionId+'_'+(id||'general');
   if(action.startsWith('un'))await write(db,scope,[{Delete:{TableName:S,Key:{subscriptionId},ConditionExpression:'connectionId=:id',ExpressionAttributeValues:{':id':connectionId}}}]);
   else await write(db,scope,[{Put:{TableName:S,Item:{subscriptionId,connectionId,businessId:id||null,subscriptionType:id?'business_status':'general',userId:scope.subjectId,ttl:scope.expiresAt,timestamp:now}}}]);
   return ack('subscription_ack');
  }
  if(scope.role==='GUEST')fail('AUTHENTICATED_ORDER_REQUIRED',401);
  if(['subscribe_order','subscribe_order_tracking','unsubscribe_order'].includes(action)){
   const id=m.order_id||m.orderId,extra=await authorizeOrder(db,scope,id),subscriptionId=connectionId+'_'+id;
   if(action==='unsubscribe_order')await write(db,scope,[{Delete:{TableName:S,Key:{subscriptionId},ConditionExpression:'connectionId=:id',ExpressionAttributeValues:{':id':connectionId}}}],extra);
   else await write(db,scope,[{Put:{TableName:S,Item:{subscriptionId,connectionId,orderId:id,userId:scope.subjectId,subscriptionType:'order_tracking',ttl:scope.expiresAt,timestamp:now}}}],extra);
   await post(e,{type:'subscription_ack',action,orderId:id,timestamp:now});return {statusCode:200,body:'OK'};
  }
  if(scope.role==='CUSTOMER'&&['subscribe_user_orders','unsubscribe_user_orders'].includes(action)){
   const id=m.user_id||m.userId||scope.subjectId,extra=await customerIdentity(db,scope,id),subscriptionId=connectionId+'_user_orders_'+id;
   if(action.startsWith('un'))await write(db,scope,[{Delete:{TableName:S,Key:{subscriptionId},ConditionExpression:'connectionId=:id',ExpressionAttributeValues:{':id':connectionId}}}],extra);
   else await write(db,scope,[{Put:{TableName:S,Item:{subscriptionId,connectionId,userId:id,subscriptionType:'user_orders',ttl:scope.expiresAt,timestamp:now}}}],extra);
   await post(e,{type:'subscription_ack',action,userId:id,timestamp:now});return {statusCode:200,body:'OK'};
  }
  if(scope.role==='DRIVER'){
   for(const id of [m.driverId,m.userId].filter(Boolean))if(![scope.driverId,scope.subjectId].includes(id))fail('DRIVER_SCOPE_REQUIRED');
   if(['authenticate','register','subscribe_driver_offers','driver_status','driver_online','driveronline','start_searching','driver_searching','stop_searching','driver_stop_searching','driver_offline','driver_available','driver_unavailable'].includes(action)){
    if(m.token){const identity=await verifyIdentity(m.token);if(identity.role!=='DRIVER'||identity.claims.sub!==scope.subjectId)fail('DRIVER_SCOPE_REQUIRED');}
    // The REST search/vehicle/region service remains the sole availability writer.
    if(action==='authenticate'||action==='register'){
     await write(db,scope,[{Update:{TableName:L,Key:{driverId:scope.driverId},UpdateExpression:'SET connectionId=:id, connectionStatus=:status, lastConnected=:at',ExpressionAttributeValues:{':id':connectionId,':status':'connected',':at':now}}}]);
     return ack('auth_success');
    }
    return ack('driver_status_response');
   }
  }
  fail('UNSUPPORTED_SCOPED_ACTION');
 }catch(error){
  const code=error.status?error.message:'AUTH_UNAVAILABLE';try{await post(e,{type:error.status===401?'auth_error':'error',code,message:'تعذر تنفيذ طلب التحديث الفوري. أعد الاتصال أو سجّل الدخول.'});}catch(_){}
  return {statusCode:error.status||503,body:JSON.stringify({code})};
 }
};}
function scopedClient(raw){return {send:async command=>{
 const scope=context.getStore(),name=command.constructor.name;if(!scope||!['PutCommand','UpdateCommand','DeleteCommand','BatchWriteCommand','TransactWriteCommand'].includes(name))return raw.send(command);
 let items=name==='TransactWriteCommand'?structuredClone(command.input.TransactItems):name==='BatchWriteCommand'?Object.entries(command.input.RequestItems).flatMap(([TableName,requests])=>requests.map(r=>r.PutRequest?{Put:{TableName,Item:structuredClone(r.PutRequest.Item)}}:{Delete:{TableName,Key:structuredClone(r.DeleteRequest.Key)}})):[{[name.slice(0,-7)]:structuredClone(command.input)}];
 items=items.filter(item=>!(item.ConditionCheck?.TableName===D&&accountFences(scope).some(f=>f.ConditionCheck.Key.pk===item.ConditionCheck.Key.pk)&&item.ConditionCheck.ConditionExpression==='attribute_not_exists(pk)')&&!(item.ConditionCheck?.TableName===C&&item.ConditionCheck.Key.connectionId===scope.connectionId));
 let connectionWrite=false;
 for(const item of items){const op=item.Put||item.Update||item.Delete;if(!op)fail('INVALID_REALTIME_WRITE');delete op.ReturnValues;const value=item.Put?.Item||op.Key;
  if(op.TableName===C){
   if(connectionWrite||value.connectionId!==scope.connectionId)fail('CONNECTION_SCOPE_REQUIRED');connectionWrite=true;
   if(item.Put){Object.assign(item.Put.Item,{identityScope346:marker(scope),userId:scope.subjectId,authenticated:scope.role!=='GUEST',ttl:Math.min(value.ttl||scope.expiresAt,scope.expiresAt),...(scope.role==='DRIVER'?{driverId:scope.driverId,cognitoSub:scope.subjectId,entityType:'driver',userType:'driver'}:{})});if(scope.role==='GUEST')delete item.Put.Item.cognitoSub;}
   if(scope.mode==='connect')op.ConditionExpression='attribute_not_exists(connectionId)';
   else{const fence=connectionCondition(scope);op.ConditionExpression=(op.ConditionExpression?'('+op.ConditionExpression+') AND ':'')+fence.ConditionExpression;op.ExpressionAttributeNames={...op.ExpressionAttributeNames,...fence.ExpressionAttributeNames};op.ExpressionAttributeValues={...op.ExpressionAttributeValues,...fence.ExpressionAttributeValues};}
  }else if(op.TableName===L&&scope.role==='DRIVER'&&item.Update){
   if(value.driverId!==scope.driverId)fail('DRIVER_SCOPE_REQUIRED');item.Update={TableName:L,Key:{driverId:scope.driverId},UpdateExpression:'SET connectionId=:id, connectionStatus=:status, lastConnected=:at',ExpressionAttributeValues:{':id':scope.connectionId,':status':'connected',':at':new Date().toISOString()}};
  }else if(op.TableName===S){
   if(scope.role==='GUEST')fail('AUTHENTICATED_ORDER_REQUIRED');
   if(item.Put){if(value.connectionId!==scope.connectionId||value.userId&&![scope.subjectId,scope.driverId].includes(value.userId))fail('SUBSCRIPTION_SCOPE_REQUIRED');item.Put.Item.ttl=Math.min(value.ttl||scope.expiresAt,scope.expiresAt);}
   else if(!String(value.subscriptionId||'').startsWith(scope.connectionId+'_'))fail('SUBSCRIPTION_SCOPE_REQUIRED');
  }else fail('INVALID_REALTIME_WRITE');
 }
 return raw.send(new TransactWriteCommand({TransactItems:[...fences(scope,!connectionWrite),...items]}));
}};}
async function authorizePrivateRecipient(db,cognito,connectionId,orderId){
 const row=await get(db,C,ckey(connectionId)),m=row?.identityScope346;
 if(!m||m.version!==1||!['CUSTOMER','DRIVER'].includes(m.role)||row.isActive===false||row.status==='disconnected')fail('PRIVATE_RECIPIENT_SCOPE_REQUIRED');
 const scope={...m,connectionId,mode:'delivery'};await live(db,cognito,scope);
 const orderFences=await authorizeOrder(db,scope,orderId);
 await db.send(new TransactWriteCommand({TransactItems:[...fences(scope),...orderFences]}));
 return scope;
}
module.exports={authorizePrivateRecipient,guardConnect,guardDefault,scopedClient,currentScope:()=>context.getStore(),verifyToken,authorizeOrder,customerIdentity};
