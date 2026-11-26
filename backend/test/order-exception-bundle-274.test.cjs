'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const p='/private/tmp/cash-review-274',candidate=fs.readFileSync(p+'/writer-candidate.js','utf8'),original=fs.readFileSync(p+'/runtime/_discount_review/user-create-order/index.js','utf8');
const inserted='\n      if(commercial.settlementModel === "FULL_CASH_AT_DELIVERY_V1") order.exceptionPolicy = require("../../order-exception-policy-274.js").createOrderExceptionPolicy(order.createdAt);';
const policy=require(p+'/order-exception-policy-274.js');
test('candidate preserves all deployed logic and changes only policy pin at creation',()=>assert.equal(candidate.replace(inserted,''),original));
for(const model of ['FULL_CASH_AT_DELIVERY_V1','LEGACY'])test('persisted policy contract for '+model,()=>{
 const begin=candidate.indexOf('    if (commercial) {\n      order.merchantId = commercial.merchantId;'),end=candidate.indexOf('\n    const receptionEnabled',begin);assert(begin>0&&end>begin);
 const order={createdAt:'2026-10-22T04:05:00.000Z',paymentMethod:'cod'},commercial={settlementModel:model,merchantId:'m1',financialSnapshot:{schemaVersion:3},funding:{},calculation:{}};
 vm.runInNewContext(candidate.slice(begin,end),{order,commercial,require:n=>{assert.equal(n,'../../order-exception-policy-274.js');return policy;}});
 if(model==='FULL_CASH_AT_DELIVERY_V1'){assert.deepEqual(policy.readOrderExceptionPolicy(order),policy.createOrderExceptionPolicy(order.createdAt));assert.equal(order.exceptionPolicy.rules.autoCustomerCashRefund,false);}else assert.equal(order.exceptionPolicy,undefined);
});
