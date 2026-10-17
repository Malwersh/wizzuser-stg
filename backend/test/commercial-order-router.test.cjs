'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {createCommercialOrderRouter,publicOrderResponse}=require('../src/functions/create-order/commercial-order-router');
const response=()=>({statusCode:201,headers:{existing:'preserved'},body:JSON.stringify({success:true,order:{orderId:'one',pricing:{total:0},financialSnapshot:{private:1},commercialPricing:{private:2},financialAcceptance:{allocation:{private:3}},codFinancialEvidence:{private:4}}})});
test('closed modes preserve the original request, result status and legacy invocation without loading financial code',async()=>{
 const event={httpMethod:'POST',body:'{"items":[1],"deliveryFee":0}'};let calls=0;
 const handler=createCommercialOrderRouter({env:{},legacy:async(e,c)=>{assert.equal(e,event);assert.equal(c,'context');calls++;return response();},loadCommercial:()=>{throw Error('must stay unloaded');}});
 const r=await handler(event,'context');assert.equal(calls,1);assert.equal(r.statusCode,201);assert.equal(r.headers.existing,'preserved');assert.deepEqual(JSON.parse(r.body).order,{orderId:'one',pricing:{total:0}});
});
test('closed modes reject preview, quoted requests and consent without invoking any writer',async()=>{
 const handler=createCommercialOrderRouter({env:{},legacy:()=>assert.fail('legacy write'),loadCommercial:()=>assert.fail('financial load')});
 for(const body of [{quoteId:null},{commercialConsent:{}},{action:'preview_commercial'}])assert.equal((await handler({httpMethod:'POST',body:JSON.stringify(body)})).statusCode,409);
 assert.equal((await handler({httpMethod:'POST',resource:'/orders/commercial-preview',body:'{}'})).statusCode,409);
});
test('partial/invalid activation fails closed and full activation delegates only to canonical financial handler',async()=>{
 for(const env of [{DELIVERY_QUOTE_MODE:'REQUIRED'},{COMMERCIAL_PRICING_MODE:'REQUIRED'},{DELIVERY_QUOTE_MODE:'typo',COMMERCIAL_PRICING_MODE:'typo'}]){
  const h=createCommercialOrderRouter({env,legacy:()=>assert.fail('legacy write'),loadCommercial:()=>assert.fail('financial load')});assert.equal((await h({httpMethod:'POST',body:'{}'})).statusCode,503);
 }
 let calls=0;const h=createCommercialOrderRouter({env:{DELIVERY_QUOTE_MODE:'REQUIRED',COMMERCIAL_PRICING_MODE:'REQUIRED'},legacy:()=>assert.fail('legacy write'),loadCommercial:()=>async()=>{calls++;return response();}});
 assert.equal((await h({httpMethod:'POST',body:'{}'})).statusCode,201);assert.equal(calls,1);
});
test('public response projection covers lists and leaves stored records, errors and transport bodies unchanged',()=>{
 const original=JSON.parse(response().body).order;const r=publicOrderResponse({statusCode:200,body:JSON.stringify({orders:[original]})});
 assert.equal(JSON.parse(r.body).orders[0].financialAcceptance,undefined);assert.equal(original.financialAcceptance.allocation.private,3);
 for(const body of ['invalid','[]','null','']){const r={statusCode:400,body};assert.equal(publicOrderResponse(r),r);}
 const base64={isBase64Encoded:true,body:'AA=='};assert.equal(publicOrderResponse(base64),base64);
});
test('preflight retains existing transport behavior with no financial load even during incomplete configuration',async()=>{
 const r={statusCode:204,body:''};const h=createCommercialOrderRouter({env:{COMMERCIAL_PRICING_MODE:'REQUIRED'},legacy:async()=>r,loadCommercial:()=>assert.fail('financial load')});assert.equal(await h({httpMethod:'OPTIONS'}),r);
});

test('an unquoted caller outside the cohort keeps its legacy path after the canonical guard denies it',async()=>{
 let legacy=0,financial=0;const h=createCommercialOrderRouter({env:{DELIVERY_QUOTE_MODE:'REQUIRED',COMMERCIAL_PRICING_MODE:'REQUIRED'},legacy:async()=>{legacy++;return response();},loadCommercial:()=>async()=>{financial++;return {statusCode:403,body:JSON.stringify({code:'FINANCE_ROLLOUT_OUT_OF_SCOPE'})};}});
 assert.equal((await h({httpMethod:'POST',body:'{"items":[1]}'})).statusCode,201);assert.equal(legacy,1);assert.equal(financial,1);
});
test('quoted, consent and preview requests never silently fall back to client-priced legacy creation',async()=>{
 const h=createCommercialOrderRouter({env:{DELIVERY_QUOTE_MODE:'REQUIRED',COMMERCIAL_PRICING_MODE:'REQUIRED'},legacy:()=>assert.fail('fallback would drop financial contract'),loadCommercial:()=>async()=>({statusCode:403,body:JSON.stringify({code:'FINANCE_ROLLOUT_OUT_OF_SCOPE'})})});
 for(const body of [{quoteId:'q'},{commercialConsent:{}},{action:'preview_commercial'}])assert.equal((await h({httpMethod:'POST',body:JSON.stringify(body)})).statusCode,403);
 assert.equal((await h({httpMethod:'POST',resource:'/orders/commercial-preview',body:'{}'})).statusCode,403);
});
test('closed admission or missing cohort configuration never reopen a legacy path for the cohort',async()=>{
 for(const code of ['FINANCE_ROLLOUT_ADMISSION_CLOSED','FINANCE_ROLLOUT_NOT_CONFIGURED']){
 const h=createCommercialOrderRouter({env:{DELIVERY_QUOTE_MODE:'REQUIRED',COMMERCIAL_PRICING_MODE:'REQUIRED'},legacy:()=>assert.fail('cohort reopened'),loadCommercial:()=>async()=>({statusCode:403,body:JSON.stringify({code})})});assert.equal((await h({httpMethod:'POST',body:'{}'})).statusCode,403);}
});
test('internal cohort pins are removed by the shared public response projection',()=>{
 const r=publicOrderResponse({statusCode:200,body:JSON.stringify({order:{orderId:'o',financeRollout:{scopeId:'PRIVATE'},pricing:{total:1000}}})});assert.equal(JSON.parse(r.body).order.financeRollout,undefined);
});
