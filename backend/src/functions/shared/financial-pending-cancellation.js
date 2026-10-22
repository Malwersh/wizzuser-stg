'use strict';
const {GetCommand}=require('@aws-sdk/lib-dynamodb');
const {offerContext}=require('./offer-context');
const {createFinanceRollout}=require('../create-order/quote-runtime/financeRollout');
const {createMerchantPendingResponse}=require('../create-order/quote-runtime/merchantPendingResponse');
const fail=(code,statusCode)=>{throw Object.assign(Error(code),{code,statusCode});};

// Host-only adapter: never accepts customer/merchant identity or funding from the body.
async function cancelFinancialPending({db,event,order,reason,env=process.env}) {
 if(env.FINANCIAL_CUSTOMER_CANCELLATION_MODE!=='REQUIRED')fail('FINANCIAL_ORDER_WORKFLOW_REQUIRED',409);
 if(env.ENVIRONMENT!=='staging'||env.AWS_REGION!=='us-east-1')fail('FINANCIAL_CANCELLATION_NOT_CONFIGURED',503);
 if(typeof reason!=='string'||!reason.trim()||reason.length>500)fail('INVALID_CANCELLATION_REASON',400);
 async function authenticate(){
  const context=await offerContext(db,event,{userId:order.userId});
  if(!context.identity?.sub||context.identity.sub!==order.userSub||context.identity.userId!==order.userId||!context.guarded?.condition)
   fail('CANCELLATION_NOT_AUTHORIZED',403);
  const branch=(await db.send(new GetCommand({TableName:'WhizzMerchants_Businesses',Key:{businessId:order.storeId},ConsistentRead:true}))).Item;
  if(!branch?.ownerId||branch.ownerId!==branch.cognitoUserId)fail('CANCELLATION_STATE_CHANGED',409);
  return {kind:'CUSTOMER',subjectId:context.identity.sub,customerId:context.identity.userId,
   businessId:order.storeId,ownerId:branch.ownerId,guards:[context.guarded.condition]};
 }
 // Verify live ownership before any financial planning or scope reads.
 await authenticate();
 const rollout=createFinanceRollout({db,env});
 const engine=createMerchantPendingResponse({db:rollout.db,authenticate,
  enableFullCash:env.FINANCIAL_SETTLEMENT_MODEL==='FULL_CASH_AT_DELIVERY_V1',
  enableDeliveryFunding:env.FINANCIAL_DELIVERY_FUNDING_MODE==='REQUIRED'});
 try {
  return await engine.run(order.orderId,'CUSTOMER_CANCEL',reason.trim());
 }catch(error){
  if(error.statusCode)throw error;
  if(error.name==='TransactionCanceledException')fail('CANCELLATION_STATE_CHANGED',409);
  if(error.code==='MERCHANT_RESPONSE_UNAUTHORIZED')fail('CANCELLATION_NOT_AUTHORIZED',403);
  if(error.code==='INVALID_MERCHANT_RESPONSE')fail('INVALID_CANCELLATION_REASON',400);
  if(error.code)fail(error.code,409);
  fail('FINANCIAL_CANCELLATION_UNAVAILABLE',503);
 }
}
module.exports={cancelFinancialPending};
