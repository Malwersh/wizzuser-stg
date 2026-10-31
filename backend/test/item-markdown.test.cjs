'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const e=require('../src/functions/shared/discount-engine'),contract=require('../src/functions/shared/discount-contract');
const raw={discountId:'item-deal',businessId:'b',status:'active',type:'percentage',value:20,applicability:'specificItems',applicable_item_ids:['p','q'],calculationMode:'perItem',minimum_order_amount:0,usage_count:0};
const normalized=()=>e.normalizeDiscount(raw);
test('unit savings remain identical at every quantity and do not affect other products',()=>{
 for(const q of [1,2,3,20]) {
  const lines=[{itemId:'p',price:3500000,quantity:q},{itemId:'other',price:8000000,quantity:1}];
  assert.equal(e.calculateCheckoutDiscountAmount(normalized(),3500000*q+8000000,lines,0),500000*q);
 }
 assert.equal(e.calculateCheckoutDiscountAmount(e.normalizeDiscount({...raw,type:'fixedAmount',value:1000}),10000000,[{itemId:'p',price:5000000,quantity:2}],0),2000000);
});
test('legacy fixed discount still applies once, and caps/minimum/audiences cannot be disguised as unit markdowns',()=>{
 assert.equal(e.calculateCheckoutDiscountAmount(e.normalizeDiscount({...raw,calculationMode:'order',type:'fixedAmount',value:1000}),10000000,[{itemId:'p',price:5000000,quantity:2}],0),1000000);
 for(const patch of [{minimum_order_amount:1000},{maxDiscountAmount:1000},{perCustomerLimit:1},{firstOrderOnly:true},{customerSegments:['new']},{applicability:'allItems'},{calculationMode:'invalid'},{type:'freeDelivery'}]) assert.equal(contract.supported({...raw,...patch}),false,JSON.stringify(patch));
});
test('zero and cheap units never produce a negative price',()=>{
 for(const price of [1,100000,250000,500000]) {
  const saving=e.calculateCheckoutDiscountAmount(e.normalizeDiscount({...raw,type:'fixedAmount',value:2000}),price,[{itemId:'p',price,quantity:1}],0);
  assert.ok(saving>=0&&saving<=price);
 }
});
test('preview and commit allocate exact unit savings by line and reserve the observed terms',async()=>{
 class GetCommand{constructor(input){this.input=input;}}
 const module={exports:{}};vm.runInNewContext(fs.readFileSync(require.resolve('../src/functions/shared/discount-reservation'),'utf8'),{module,Buffer,process:{env:{}},require:n=>({'@aws-sdk/lib-dynamodb':{GetCommand},'./discount-engine':e,'./campaign-version':require('../src/functions/shared/campaign-version'),'./offer-eligibility':{eligibility:async()=>({})}}[n])});
 const request={db:{send:async()=>({Item:raw})},branchId:'b',discountId:'item-deal',subtotal:12000000,items:[{itemId:'p',price:3500000,quantity:2},{itemId:'q',price:5000000,quantity:1}],deliveryFee:0};
 for(const preview of [true,false]){
  const result=await module.exports.resolveDiscount({...request,preview});
  assert.equal(result.amount,2000000);assert.deepEqual(JSON.parse(JSON.stringify(result.lines.map(l=>l.savingsFils))),[1000000,1000000]);
  assert.equal(result.lines.reduce((s,l)=>s+l.netFils,0),10000000);
  assert.ok(Object.values(result.operations[0].Update.ExpressionAttributeNames).includes('calculationMode'));
 }
});

test('unit menu projections use canonical catalog price and a read-only SDK bridge',async()=>{
 const module={exports:{}},sdk={GetCommand:class GetCommand {constructor(input){this.input=input;}}};let requests=0;
 const db={async send(command){assert.equal(command.constructor,sdk.GetCommand);requests++;return {};}};
 vm.runInNewContext(fs.readFileSync(require.resolve('../src/functions/shared/menu-item-prices'),'utf8'),{exports:module.exports,Date,require:n=>{
  if(n==='./discount-engine')return e;
  if(n==='crypto')return require('crypto');
  if(n==='../create-order/quote-runtime/orderGoodsPricing')return {createStagingOrderGoodsPricing:({db})=>({price:async input=>{
   assert.equal(input.branchId,'b');assert.equal(input.items[0].quantity,1);assert.equal(input.items[0].price,undefined);
   await db.send(new sdk.GetCommand({TableName:'catalog',Key:{productId:input.items[0].productId}}));
   if(input.items[0].productId==='q')throw Object.assign(Error('hidden'),{code:'GOODS_UNAVAILABLE'});
   return {lines:[{unitPrice:{minorAmount:3500000}}]};
  }})};throw Error(n);
 }});
 const rows=[{...normalized()}];await module.exports.enrich(db,'b',rows,['p','q','foreign'],sdk);
 assert.equal(requests,2);assert.equal(rows[0].itemPrices.length,1);assert.equal(rows[0].itemPrices[0].netUnitFils,3000000);
 assert.ok(rows[0].pricingRevision.match(/^[a-f0-9]{64}$/));assert.ok(Date.parse(rows[0].itemPricesValidUntil)>Date.now());
});
