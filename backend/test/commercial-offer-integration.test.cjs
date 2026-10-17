'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {resolveDiscount}=require('../src/functions/shared/discount-reservation');
const {catalogItems}=require('../src/functions/shared/offer-eligibility');
const raw=()=>({discountId:'p1',code:'CODE',status:'active',type:'percentage',value:10,usage:0,currentUsage:0,version:1,applicability:'specificCategories',applicable_category_ids:['cat'],customerSegments:['registered'],firstOrderOnly:true,perCustomerLimit:1,targetRegionIds:['region'],fundingPolicyId:'fund',fundingPolicyVersion:1});
function input(campaign=raw(),patch={}){
 const calls=[];
 const db={async send(c){const q=c.input;calls.push(q);if(q.TableName==='WizzCentral_Platform_Discounts')return {Item:campaign};if(q.TableName==='staging-WizzOfferJourney')return {};throw Error('Unexpected read '+q.TableName);}};
 return {calls,db,branchId:'branch',platformDiscountId:'p1',subtotal:3000000,deliveryFee:1000000,
  items:[{itemId:'one',price:1000000,quantity:1,categoryId:'cat'},{itemId:'two',price:2000000,quantity:1,categoryId:'other'}],
  identity:{sub:'subject',userId:'customer',profile:{}},customer:{getCount:async()=>0,history:async()=>({uses:{}})},regionIds:['region'],...patch};
}
test('financial source reuses live per-customer and region eligibility, targeted catalog and campaign funding reference',async()=>{
 const p=input(),r=await resolveDiscount(p);
 assert.equal(r.amount,100000);assert.deepEqual(r.lines,[{itemId:'one',grossFils:1000000,savingsFils:100000,netFils:900000}]);
 assert.equal(r.campaign.fundingPolicyId,'fund');assert.equal(r.snapshot.provesFunding,false);
 assert.equal(r.operations.length,2);assert.equal(r.operations[1].Put.TableName,'staging-WizzOfferJourney');assert.equal(r.operations[1].Put.Item.sk,'OFFER#platform#p1');
 assert.ok(p.calls.every(q=>q.ConsistentRead));
});
test('wrong region, first-order mismatch and already-used promotion never downgrade to an untargeted discount',async()=>{
 for(const patch of [{regionIds:['other']},{customer:{getCount:async()=>1}},{db:{async send(c){return c.input.TableName==='WizzCentral_Platform_Discounts'?{Item:raw()}:{Item:{count:1,version:1}};}}}])
  await assert.rejects(resolveDiscount(input(raw(),patch)),e=>['OFFER_WRONG_REGION','OFFER_FIRST_ORDER_ONLY','OFFER_ALREADY_USED'].includes(e.message));
});
test('platform discount ID cannot select a campaign with a different supplied code or stack merchant discounts',async()=>{
 for(const patch of [{promoCode:'OTHER'},{discountId:'merchant'}])await assert.rejects(resolveDiscount(input(raw(),patch)),/DISCOUNT_UNAVAILABLE/);
});
test('category identity used by targeted offers comes from the fenced server catalog',()=>{
 const result=catalogItems({lines:[{productId:'one',quantity:1,unitPrice:{minorAmount:1000}}],conditions:[{ConditionCheck:{Key:{productId:'one'},ExpressionAttributeNames:{'#g1':'categoryId'},ExpressionAttributeValues:{':g1':'verified'}}}]});
 assert.equal(result[0].categoryId,'verified');assert.equal(result[0].price,1000);
});
test('campaign cap is honored without changing original campaign or claiming funded status',async()=>{
 const campaign={...raw(),maxDiscountAmount:50},r=await resolveDiscount(input(campaign));assert.equal(r.amount,50000);assert.equal(r.campaign.maxDiscountAmount,50);assert.equal(r.snapshot.provesFunding,false);
});

function handlerFixture({preview=false}={}){
 const vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
 const file=path.resolve(__dirname,'../src/functions/create-order/index.js'),realRequire=require('node:module').createRequire(file);
 const writes=[],customer={key:{pk:'USER#subject',sk:'ORDERS'},getCount:async()=>0,history:async()=>({uses:{}})};
 const context={identity:{sub:'subject',userId:'customer',profile:{}},customer,regionIds:['region'],
  guarded:{sub:'subject',condition:{ConditionCheck:{TableName:'WizzUser_users_staging',Key:{userId:'customer'},ConditionExpression:'attribute_exists(userId)'}}},
  addressCondition:{ConditionCheck:{TableName:'WizzUser_addresses_staging',Key:{addressId:'address'},ConditionExpression:'attribute_exists(addressId)'}}};
 const db={async send(c){const q=c.input;if(q.TransactItems)throw Error('Unquoted write');if(q.TableName==='WizzCentral_Platform_Discounts')return {Item:raw()};if(q.TableName==='staging-WizzOfferJourney')return {};if(q.TableName==='WizzOrders')return {Items:[]};if(q.TableName==='WhizzMerchants_Businesses')return {Item:{businessId:'branch',latitude:31.9,longitude:44.4,regionId:'region'}};throw Error('Unexpected '+q.TableName);}};
 const catalog={goodsGross:{minorAmount:3000000},lines:[{productId:'one',quantity:1,unitPrice:{minorAmount:1000000}},{productId:'two',quantity:1,unitPrice:{minorAmount:2000000}}],conditions:['one','two'].map((id,i)=>({ConditionCheck:{Key:{productId:id},TableName:'WhizzMerchants_Products',ExpressionAttributeNames:{'#g1':'categoryId'},ExpressionAttributeValues:{':g1':i?'other':'cat'}}}))};
 let selectedDiscount;
 const commercial={digest:'consented',expiresAt:new Date(Date.now()+60000).toISOString(),calculation:{allocationInput:{goodsGross:{minorAmount:3000000}},customerTotal:{minorAmount:3900000},serviceFee:{amount:{minorAmount:0}}},goodsLines:catalog.lines,operations:[],branchCondition:{ConditionCheck:{TableName:'WhizzMerchants_Businesses',Key:{businessId:'branch'},ConditionExpression:'attribute_exists(businessId)'}},funding:{holdId:null}};
 const quoted={orderId:'order',deliveryFeeMinor:1000000,origin:{latitude:31.9,longitude:44.4},destination:{latitude:31.91,longitude:44.41},destinationRegionId:'region',createdAt:new Date().toISOString(),expiresAt:commercial.expiresAt,
  async commit(order,operations){writes.push({order,operations});return {order,replayed:false};}};
 const sdk=realRequire('@aws-sdk/lib-dynamodb');
 const modules={'@aws-sdk/client-dynamodb':{DynamoDBClient:class{}},'@aws-sdk/lib-dynamodb':{...sdk,DynamoDBDocumentClient:{from:()=>db}},'uuid':{v4:()=> 'synthetic'},'../shared/offer-context':{offerContext:async()=>context},'./quote-runtime/orderGoodsPricing':{createStagingOrderGoodsPricing:()=>({price:async()=>catalog})},'./quote-runtime/deliveryQuoteOrder':{createStagingQuoteOrder:()=>({prepare:async()=>quoted}),QuoteOrderError:class extends Error{}},'./quote-runtime/orderCommercialSource':{createStagingCommercialSource:()=>({prepare:async input=>{selectedDiscount=input.discount;return commercial;}})}};
 const scopeEnv=require('../../../whizzCentralPlatform-stg/backend/wallet-service/test/helpers/finance-rollout-fixture.cjs').scopeEnv({orders:[{orderId:'order',branchId:'branch',customerSubjectId:'subject'}]});
 modules['./quote-runtime/financeRollout']={createFinanceRollout:o=>require('../src/functions/create-order/quote-runtime/financeRollout').createFinanceRollout({...o,env:scopeEnv})};
 const exports={};vm.runInNewContext(fs.readFileSync(file,'utf8'),{exports,require:n=>modules[n]||realRequire(n),Buffer,Date,console:{log(){},warn(){},error(){}},process:{env:{USERS_TABLE:'WizzUser_users_staging',USER_POOL_ID:'us-east-1_TpyyrVkEE',USER_POOL_CLIENT_ID:'staging-client',AWS_REGION:'us-east-1',DELIVERY_QUOTE_MODE:'REQUIRED',COMMERCIAL_PRICING_MODE:'REQUIRED'}}});
 const body={userId:'customer',storeId:'branch',storeName:'Store',storeAddress:'Address',deliveryAddress:{id:'address',latitude:31.91,longitude:44.41},paymentMethod:'cod',items:[{id:'one',price:1000,quantity:1},{id:'two',price:2000,quantity:1}],quoteId:'quote',idempotencyKey:'request',platformDiscountId:'p1',discount:100,commercialConsent:{digest:'consented',customerTotalMinor:3900000},...(preview?{action:'preview_commercial'}:{})};
 return {invoke:()=>exports.handler({httpMethod:'POST',resource:preview?'/orders/commercial-preview':'/orders',body:JSON.stringify(body)}),writes,discount:()=>selectedDiscount};
}
test('actual commercial create handler preserves audience counters, targeted campaign and offer snapshot in the quote commit',async()=>{
 const f=handlerFixture(),r=await f.invoke();assert.equal(r.statusCode,201,r.body);assert.equal(f.writes.length,1);
 const {order,operations}=f.writes[0];assert.equal(order.offerSnapshot.discountId,'p1');assert.equal(order.promoCode,'CODE');assert.equal(order.discountId,null);
 assert.equal(order.pricing.discount,100000);assert.equal(order.pricing.deliveryFee,1000000);
 assert.equal(f.discount().campaign.fundingPolicyId,'fund');
 const counters=operations.filter(x=>x.Put?.TableName==='staging-WizzOfferJourney');assert.deepEqual(Array.from(counters,x=>x.Put.Item.sk).sort(),['OFFER#platform#p1','ORDERS']);
 assert.equal(operations.filter(x=>x.ConditionCheck?.TableName==='WizzUser_users_staging').length,1);
});
test('actual commercial preview applies the same campaign eligibility without committing counters or order',async()=>{
 const f=handlerFixture({preview:true}),r=await f.invoke();assert.equal(r.statusCode,200,r.body);assert.equal(f.writes.length,0);assert.equal(f.discount().snapshot.amount,100000);
});


test('adding a region or new-customer constraint after eligibility invalidates the reserved campaign',async()=>{
 const campaign={...raw(),applicability:'allItems'};delete campaign.targetRegionIds;
 const r=await resolveDiscount(input(campaign)),op=r.operations[0].Update;
 for(const field of ['targetRegionIds','campaignType']){
  const alias=Object.keys(op.ExpressionAttributeNames).find(k=>op.ExpressionAttributeNames[k]===field);
  assert.ok(alias);assert.ok(op.ConditionExpression.includes('attribute_not_exists('+alias+')'));
 }
});
