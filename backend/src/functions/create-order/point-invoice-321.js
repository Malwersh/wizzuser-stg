'use strict';
const {randomUUID,createHash}=require('crypto');
const fail=code=>{throw Object.assign(Error(code),{code,statusCode:400});};
/** Per-request point/quote view: never persist an address, quote or financial
 * mutation. Existing ConditionCheck-only transactions still verify real rows;
 * ephemeral point and quote checks are validated against private immutable data. */
function pointView321(base,{address,userId}){
 const point=structuredClone(address);let capture=true;const quotes=new Map();
 const tag=k=>JSON.stringify([k.pk,k.sk]);
 function virtualCheck(check){
  if(check.TableName==='WizzUser_addresses_staging'&&check.Key?.addressId===point.addressId)return true;
  if(check.TableName==='staging-DeliveryQuotes'&&check.Key?.pk==='CUSTOMER#'+userId){
   const row=quotes.get(tag(check.Key)),expected=check.ExpressionAttributeValues?.[':digest'];
   if(!row||row.consumption!==undefined||(expected!==undefined&&expected!==row.digest))fail('POINT_PREVIEW_QUOTE_CHANGED');
   return true;
  }
  return false;
 }
 return {seal(){capture=false;},db:{async send(c){
  const name=c.constructor.name.replace(/\d+$/,''),q=c.input;
  if(name==='GetCommand'&&q.TableName==='WizzUser_addresses_staging'&&q.Key.addressId===point.addressId)return{Item:structuredClone(point)};
  if(name==='GetCommand'&&q.TableName==='staging-DeliveryQuotes'&&q.Key.pk==='CUSTOMER#'+userId)return{Item:structuredClone(quotes.get(tag(q.Key)))};
  if(name==='TransactWriteCommand'){
   const ops=q.TransactItems;
   if(!Array.isArray(ops)||ops.length===0||ops.some(o=>Object.keys(o).length!==1||(!o.ConditionCheck&&!o.Put)))fail('POINT_PREVIEW_WRITE_FORBIDDEN');
   const puts=ops.filter(o=>o.Put);
   if(puts.length>0&&(!capture||puts.length!==1||puts[0].Put.TableName!=='staging-DeliveryQuotes'||puts[0].Put.Item.pk!=='CUSTOMER#'+userId))fail('POINT_PREVIEW_WRITE_FORBIDDEN');
   const row=puts[0]?.Put.Item;
   if(row&&quotes.has(tag(row)))fail('POINT_PREVIEW_QUOTE_CHANGED');
   const realChecks=ops.filter(o=>o.ConditionCheck&&!virtualCheck(o.ConditionCheck));
   // Only ConditionChecks reach DynamoDB. No Put, Update or Delete can escape.
   if(realChecks.length)await base.send(new c.constructor({...q,TransactItems:realChecks}));
   if(row)quotes.set(tag(row),structuredClone(row));
   return{};
  }
  if(!['GetCommand','QueryCommand','BatchGetCommand','ScanCommand'].includes(name))fail('POINT_PREVIEW_WRITE_FORBIDDEN');
  return base.send(c);
 }}};
}
async function prepare321({event,body,base,run,env=process.env,runtime}){
 if(event.resource!=='/orders/commercial-preview'||body.action!=='preview_commercial_point'||body.commercialConsent!==undefined||body.quoteId!==undefined||body.deliveryAddress!==undefined)fail('INVALID_POINT_INVOICE');
 if(env.POINT_INVOICE_ENABLED!=='true'||env.ENVIRONMENT!=='staging'||env.USERS_TABLE!=='WizzUser_users_staging'||env.AWS_REGION!=='us-east-1')fail('POINT_INVOICE_NOT_CONFIGURED');
 const p=body.pricingPoint;
 if(!p||Object.keys(p).sort().join(',')!=='latitude,longitude'||typeof p.latitude!=='number'||typeof p.longitude!=='number'||!Number.isFinite(p.latitude)||!Number.isFinite(p.longitude)||Math.abs(p.latitude)>90||Math.abs(p.longitude)>180||typeof body.userId!=='string'||body.userId==='guest'||!Array.isArray(body.items)||body.items.length<1||body.items.length>50)fail('INVALID_POINT_INVOICE');
 const {accountGuard}=require('./account-guard');
 const cognito=new runtime.CognitoIdentityProviderClient({});
 const authenticate=async()=>{const guard=await accountGuard({event,userId:body.userId,pool:env.USER_POOL_ID,clientId:env.USER_POOL_CLIENT_ID,profilesTable:env.USERS_TABLE,getUser:t=>cognito.send(new runtime.GetUserCommand({AccessToken:t})),getProfile:async id=>(await base.send(new runtime.GetCommand({TableName:env.USERS_TABLE,Key:{userId:id},ConsistentRead:true}))).Item});if(!guard.condition)fail('AUTH_REQUIRED');return{userId:body.userId,subjectId:guard.sub,condition:guard.condition};};
 await authenticate();
 const addressId='POINT_INVOICE_'+createHash('sha256').update(JSON.stringify([body.userId,p.latitude,p.longitude])).digest('hex').slice(0,48);
 const address={addressId,userId:body.userId,latitude:p.latitude,longitude:p.longitude};
 const view=pointView321(base,{address,userId:body.userId});
 const secrets=new runtime.SecretsManagerClient({});
 const service=runtime.createStagingDeliveryQuotes({db:view.db,authenticateCustomer:authenticate,createRouter:db=>runtime.createStagingSecretDeliveryRouting({db,secrets,secretArn:env.MAPBOX_SECRET_ARN,profile:'driving',ttlSeconds:120,timeoutMs:8000,credentialTimeoutMs:2000})});
 const quote=await service.create({branchId:body.storeId,addressId,requestId:randomUUID()});
 view.seal();
 const {pricingPoint,action,...content}=body;
 const request={...content,action:'preview_commercial',quoteId:quote.quoteId,idempotencyKey:randomUUID(),deliveryFee:quote.customerDeliveryFee.minorAmount/1000,deliveryAddress:{id:addressId,latitude:p.latitude,longitude:p.longitude,fullAddress:'نقطة التوصيل المؤكدة'}};
 const response=await run({...event,body:JSON.stringify(request)},view.db);
 if(response.statusCode!==200){
  let details;try{details=JSON.parse(response.body);}catch(_){}
  const code=details?.code||details?.error;
  console.warn('POINT_INVOICE_CALCULATION_REJECTED',{status:response.statusCode,code:typeof code==='string'&&/^[A-Z0-9_]{2,80}$/.test(code)?code:'INVOICE_CALCULATION_FAILED'});
  return response;
 }
 const result=JSON.parse(response.body),invoice=result.commercial;
 if(!invoice)fail('POINT_INVOICE_UNAVAILABLE');
 const {quoteId,requestId,digest,...amounts}=invoice;
 console.info('POINT_INVOICE_READY',{branchId:body.storeId,totalMinor:amounts.customerTotal?.minorAmount});
 return{...response,body:JSON.stringify({success:true,pointInvoice:{...amounts,kind:'POINT_INVOICE',informationalOnly:true,requiresFinalConfirmation:true,point:p,branchId:body.storeId}})};
}
function readOnlyInvoiceDb323(base){return{async send(c){
 const name=c.constructor.name.replace(/\d+$/,'');
 if(['GetCommand','QueryCommand','BatchGetCommand','ScanCommand'].includes(name))return base.send(c);
 if(name==='TransactWriteCommand'&&Array.isArray(c.input.TransactItems)&&c.input.TransactItems.length>0&&c.input.TransactItems.every(o=>Object.keys(o).length===1&&o.ConditionCheck))return base.send(c);
 fail('INVOICE_PREVIEW_WRITE_FORBIDDEN');
}};}
module.exports={pointView321,prepare321,readOnlyInvoiceDb323};
