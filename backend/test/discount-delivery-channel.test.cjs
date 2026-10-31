'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const engine=require('../src/functions/shared/discount-engine');
const contract=require('../src/functions/shared/discount-contract');
class GetCommand {constructor(input){this.input=input;}}
class QueryCommand {constructor(input){this.input=input;}}
class ScanCommand {constructor(input){this.input=input;}}
const delivery={discountId:'delivery',businessId:'branch',type:'freeDelivery',value:0,status:'active',usage_count:0,usage:0,currentUsage:0,code:'FREE',version:1};
function load(file,env,db,extra={}) {
 const module={exports:{}},exports=module.exports;
 const modules={
  '@aws-sdk/client-dynamodb':{DynamoDBClient:class{}},
  '@aws-sdk/lib-dynamodb':{GetCommand,QueryCommand,ScanCommand,DynamoDBDocumentClient:{from:()=>db}},
  './discount-engine':engine,'./discount-contract':contract,
  './campaign-version':require('../src/functions/shared/campaign-version'),
  './offer-eligibility':{eligibility:async()=>({}),catalogItems:()=>[]},
  './offer-context':{offerContext:async()=>({})},...extra,
 };
 vm.runInNewContext(fs.readFileSync(require.resolve('../src/functions/shared/'+file),'utf8'),{
  module,exports,Buffer,process:{env},console:{error(){}},require:n=>{assert.ok(n in modules,n);return modules[n];}
 });
 return module.exports;
}
const input={branchId:'branch',discountId:'delivery',subtotal:10000000,items:[],deliveryFee:2000000};
test('commercial preview and order reject legacy delivery coupons before redemption preparation',async()=>{
 for(const platform of [false,true])for(const preview of [false,true]) {
  let eligibility=0;const db={async send(){return {Item:delivery};}};
  const api=load('discount-reservation',{COMMERCIAL_PRICING_MODE:'REQUIRED'},db,{
   './offer-eligibility':{eligibility:async()=>{eligibility++;return {};}}
  });
  await assert.rejects(api.resolveDiscount({...input,db,preview,...(platform?{discountId:null,platformDiscountId:'delivery'}:{})}),
   e=>e.message==='OFFER_DELIVERY_POLICY_REQUIRED'&&e.statusCode===409);
  assert.equal(eligibility,0);
 }
});
test('noncommercial checkout preserves existing free-delivery redemption',async()=>{
 const db={async send(){return {Item:delivery};}};
 const r=await load('discount-reservation',{COMMERCIAL_PRICING_MODE:'OFF'},db).resolveDiscount({...input,db});
 assert.equal(r.amount,2000000);assert.equal(r.snapshot.target,'DELIVERY');
});
test('commercial listings hide delivery coupons while preserving eligible goods discounts',async()=>{
 const goods={...delivery,discountId:'goods',type:'percentage',value:10,code:'GOODS'};
 const rows=[delivery,goods];const db={async send(c){return c.input.Key?{Item:rows.find(r=>r.discountId===c.input.Key.discountId)}:{Items:rows};}};
 for(const platform of [false,true])for(const mode of ['REQUIRED','OFF']) {
  const response=await load('discount-list',{COMMERCIAL_PRICING_MODE:mode},db).list(platform)({pathParameters:{businessId:'branch'}});
  assert.equal(response.statusCode,200);
  const body=JSON.parse(response.body),offers=body[platform?'promos':'discounts'];
  assert.equal(offers.length,mode==='REQUIRED'?1:2);
  if(mode==='REQUIRED')assert.equal(offers[0].type,'percentage');
 }
});
test('public preview returns an actionable conflict instead of a successful unfunded saving',async()=>{
 const env={COMMERCIAL_PRICING_MODE:'REQUIRED'},db={async send(){return {Item:delivery};}};
 const reservation=load('discount-reservation',env,db);
 const api=load('discount-preview',env,db,{
  './discount-reservation':reservation,
  '../create-order/quote-runtime/orderGoodsPricing':{createStagingOrderGoodsPricing:()=>({price:async()=>({goodsGross:{minorAmount:10000000}})})}
 });
 const r=await api.preview(false)({body:JSON.stringify({businessId:'branch',discountId:'delivery',items:[],deliveryFee:2000})});
 assert.equal(r.statusCode,409);
 const body=JSON.parse(r.body);assert.equal(body.valid,false);assert.equal(body.message,'OFFER_DELIVERY_POLICY_REQUIRED');
 assert.equal(body.discountAmount,undefined);
});
test('both public previews reject customized items before catalog pricing or redemption',async()=>{
 for(const platform of [false,true])for(const key of ['modifiers','customizations','selectedOptions','selected_options','variantId']){
  let catalogCalls=0,redemptions=0;
  const api=load('discount-preview',{}, {},{
   './discount-reservation':{resolveDiscount:async()=>{redemptions++;}},
   '../create-order/quote-runtime/orderGoodsPricing':{createStagingOrderGoodsPricing:()=>({price:async()=>{catalogCalls++;}})}
  });
  const r=await api.preview(platform)({body:JSON.stringify({businessId:'branch',discountId:'delivery',code:'CODE',deliveryFee:0,
   items:[{id:'product',quantity:1,[key]:key==='modifiers'?[{id:'extra',price:0}]:key==='variantId'?'large':{group:[{id:'choice',price:0}]}}]})});
  assert.equal(r.statusCode,409);assert.equal(JSON.parse(r.body).message,'UNSUPPORTED_DISCOUNT_ITEMS');
  assert.equal(catalogCalls,0);assert.equal(redemptions,0);
 }
});
test('all coupon functions use the same commercial-mode condition as order confirmation',()=>{
 const template=fs.readFileSync(require.resolve('../template.yaml'),'utf8');
 for(const name of ['CreateOrder','ApplyPromoCode','GetStoreDiscounts','GetActivePromoCodes','ValidatePromoCode']) {
  const section=template.split('  '+name+'Function:\n')[1]?.split(/\n  \w+:\n/)[0];
  assert.ok(section,name);
  assert.match(section,/COMMERCIAL_PRICING_MODE: !If \[IsCommercialStaging, REQUIRED, 'OFF'\]/);
 }
});

test('customer listings expose complete redemption terms without internal accounting fields',async()=>{
 const row={...delivery,type:'percentage',value:12.5,applicability:'specificCategories',applicable_category_ids:['category'],
  maxDiscount:2500.75,firstOrderOnly:true,perCustomerLimit:2,customerSegments:['new'],
  fundingPolicyId:'private',customerIds:['private-customer'],createdBy:'private-staff',
  validFrom:'2020-01-01T00:00:00Z',validTo:'2090-01-01T00:00:00Z'};
 const db={async send(c){return c.input.Key?{Item:row}:{Items:[row]};}};
 for(const platform of [false,true]) {
  const r=await load('discount-list',{},db).list(platform)({headers:{Authorization:'Bearer test'},
   queryStringParameters:{userId:'user'},pathParameters:{businessId:'branch'}});
  assert.equal(r.statusCode,200);
  const offer=JSON.parse(r.body)[platform?'promos':'discounts'][0];
  assert.equal(offer.maxDiscountAmount,2500.75);
  assert.equal(offer.firstOrderOnly,true);
  assert.equal(offer.perCustomerLimit,2);
  assert.deepEqual(offer.customerSegments,['new']);
  assert.deepEqual(offer.applicable_category_ids,['category']);
  for(const field of ['fundingPolicyId','customerIds','createdBy'])assert.equal(offer[field],undefined);
 }
});

test('both public preview routes expose zero-saving rejection without a discount amount',async()=>{
 for(const platform of [false,true]){
  const row={...delivery,type:'percentage',value:0.001},db={async send(){return {Item:row};}};
  const reservation=load('discount-reservation',{},db);
  const api=load('discount-preview',{},db,{'./discount-reservation':reservation,
   '../create-order/quote-runtime/orderGoodsPricing':{createStagingOrderGoodsPricing:()=>({price:async()=>({goodsGross:{minorAmount:1000}})})}});
  const response=await api.preview(platform)({body:JSON.stringify({businessId:'branch',discountId:'delivery',platformDiscountId:'delivery',items:[],deliveryFee:0})});
  assert.equal(response.statusCode,409,response.body);const body=JSON.parse(response.body);
  assert.equal(body.message,'OFFER_NO_SAVINGS');assert.equal(body.valid,false);assert.equal(body.discountAmount,undefined);
 }
});
