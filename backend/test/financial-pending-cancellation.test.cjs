'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const order={orderId:'order',userId:'user',userSub:'subject',storeId:'branch',status:'pending',financialSnapshot:{}};
const env={ENVIRONMENT:'staging',AWS_REGION:'us-east-1',FINANCIAL_CUSTOMER_CANCELLATION_MODE:'REQUIRED'};
function fixture({identity,runError}={}){
 let auth=0,runs=0,rollouts=0,planned;
 class GetCommand{constructor(input){this.input=input;}}
 const db={async send(c){assert.equal(c.input.ConsistentRead,true);return {Item:{ownerId:'owner',cognitoUserId:'owner'}};}};
 const modules={
  '@aws-sdk/lib-dynamodb':{GetCommand},
  './offer-context':{offerContext:async(db,event,body)=>{
   auth++;assert.equal(body.userId,'user');
   return {identity:typeof identity==='function'?identity(auth):identity||{sub:'subject',userId:'user'},
    guarded:{condition:{ConditionCheck:{TableName:'WizzUser_users_staging',Key:{userId:'user'},ConditionExpression:'attribute_exists(userId)'}}}};
  }},
  '../create-order/quote-runtime/financeRollout':{createFinanceRollout:()=>{rollouts++;return {db};}},
  '../create-order/quote-runtime/merchantPendingResponse':{createMerchantPendingResponse:options=>{
   planned=options;return {run:async(id,mode,reason)=>{runs++;assert.equal(id,'order');assert.equal(mode,'CUSTOMER_CANCEL');assert.equal(reason,'reason');await options.authenticate();await options.authenticate();if(runError)throw runError;return {status:'cancelled',replayed:false};}};
  }},
 };
 const module={exports:{}};
 vm.runInNewContext(fs.readFileSync(require.resolve('../src/functions/shared/financial-pending-cancellation'),'utf8'),{
  module,process:{env},require:n=>{assert.ok(n in modules,n);return modules[n];}
 });
 return {call:patch=>module.exports.cancelFinancialPending({db,event:{headers:{Authorization:'Bearer test'}},order,reason:' reason ',env,...patch}),
  state:()=>({auth,runs,rollouts,planned})};
}
test('customer adapter validates saved identity and refreshes authority before financial commit',async()=>{
 const f=fixture();assert.equal((await f.call()).status,'cancelled');
 assert.equal(f.state().auth,3);assert.equal(f.state().runs,1);
 assert.equal(f.state().planned.enableDeliveryFunding,false);
});
test('disabled feature, wrong environment and invalid reasons never reach financial planning',async()=>{
 for(const patch of [{env:{...env,FINANCIAL_CUSTOMER_CANCELLATION_MODE:'OFF'}},{env:{...env,ENVIRONMENT:'prod'}},{reason:''},{reason:'x'.repeat(501)}]){
  const f=fixture();await assert.rejects(f.call(patch));assert.equal(f.state().runs,0);assert.equal(f.state().auth,0);
 }
});
test('foreign ownership and identity changes cannot invoke or complete cancellation',async()=>{
 const f=fixture({identity:{sub:'foreign',userId:'user'}});
 await assert.rejects(f.call(),{code:'CANCELLATION_NOT_AUTHORIZED'});assert.equal(f.state().runs,0);assert.equal(f.state().rollouts,0);
 const changed=fixture({identity:n=>({sub:n===1?'subject':'foreign',userId:'user'})});
 await assert.rejects(changed.call(),{code:'CANCELLATION_NOT_AUTHORIZED'});
});
test('transaction conflicts and financial errors retain actionable status codes',async()=>{
 for(const [error,code,statusCode] of [
  [{name:'TransactionCanceledException'},'CANCELLATION_STATE_CHANGED',409],
  [{code:'ORDER_ALREADY_HANDLED'},'ORDER_ALREADY_HANDLED',409],
  [{code:'MERCHANT_RESPONSE_UNAUTHORIZED'},'CANCELLATION_NOT_AUTHORIZED',403],
  [{name:'ResourceNotFoundException'},'FINANCIAL_CANCELLATION_UNAVAILABLE',503],
 ])await assert.rejects(fixture({runError:error}).call(),e=>e.code===code&&e.statusCode===statusCode);
});
