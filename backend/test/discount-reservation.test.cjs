const {test}=require('node:test'),assert=require('node:assert/strict');
const {resolveDiscount,readPromo,reserve}=require('../src/functions/shared/discount-reservation');
const {normalizeDiscount,validateDiscount,calculateDiscountAmount,normalizePlatformPromo,validatePlatformPromo}=require('../src/functions/shared/discount-engine');
const row=()=>({discountId:'d1',businessId:'b1',status:'active',type:'percentage',value:10,applicability:'allItems',usage_count:0,usage_limit:1});
const input=(raw=row())=>({db:{async send(c){assert.equal(c.input.ConsistentRead,true);return {Item:structuredClone(raw)};}},branchId:'b1',discountId:'d1',subtotal:3500000,items:[],deliveryFee:0});
const reject=p=>assert.rejects(p,e=>['DISCOUNT_UNAVAILABLE','OFFER_LOGIN_REQUIRED','OFFER_CUSTOMER_LIMIT_UNSUPPORTED','OFFER_NOT_ELIGIBLE'].includes(e.message));
test('reservation pins campaign and increments usage in a transaction operation without writing',async()=>{
 const r=await resolveDiscount(input());assert.equal(r.amount,350000);assert.equal(r.operations.length,1);
 const u=r.operations[0].Update;assert.equal(u.TableName,'WhizzMerchants_Discounts');assert.equal(u.ExpressionAttributeValues[':next'],1);
 assert.ok(Object.values(u.ExpressionAttributeNames).includes('status'));assert.ok(Object.values(u.ExpressionAttributeNames).includes('usage_limit'));
 assert.equal(r.snapshot.provesFunding,false);assert.equal(r.snapshot.target,'GOODS');
});
test('two concurrent reservations for last use pin the same count; after first commits the second fails',async()=>{
 const raw=row(),a=await resolveDiscount(input(raw)),b=await resolveDiscount(input(raw));
 function commit(op){const u=op.Update;for(const clause of u.ConditionExpression.split(' AND ')){
  const absent=/^attribute_not_exists\((#r\d+)\)$/.exec(clause);
  if(absent){assert.equal(raw[u.ExpressionAttributeNames[absent[1]]],undefined);continue;}
  const [n,v]=clause.split(' = ');assert.deepEqual(raw[u.ExpressionAttributeNames[n]],u.ExpressionAttributeValues[v]);
 }raw.usage_count=u.ExpressionAttributeValues[':next'];}
 commit(a.operations[0]);assert.throws(()=>commit(b.operations[0]));assert.equal(raw.usage_count,1);
 await reject(resolveDiscount(input(raw)));
});
test('concurrent campaign edit and deletion invalidate reservation even with same timestamp',async()=>{
 const raw=row(),r=await resolveDiscount(input(raw)),u=r.operations[0].Update;
 const alias=Object.keys(u.ExpressionAttributeNames).find(k=>u.ExpressionAttributeNames[k]==='value');
 const field=u.ConditionExpression.split(' AND ').find(x=>x.startsWith(alias+' = ')).split(' = ')[1];
 assert.equal(u.ExpressionAttributeValues[field],10);raw.value=20;assert.notEqual(raw.value,u.ExpressionAttributeValues[field]);
 const id=Object.keys(u.ExpressionAttributeNames).find(k=>u.ExpressionAttributeNames[k]==='discountId');assert.ok(u.ConditionExpression.includes(id+' = '));
});
test('branch isolation, stacking, exhausted campaign and advanced targeting fail closed',async()=>{
 await reject(resolveDiscount({...input(),branchId:'other'}));await reject(resolveDiscount({...input(),promoCode:'X'}));
 for(const extra of [{usage_count:1},{status:'inactive'},{applicability:'specificCategories'},{type:'conditional'},{maxDiscount:-1},{perCustomerLimit:1},
  {usageCount:9},{valid_to:'2020-01-01T00:00:00.000Z'},{valid_from:'invalid'}])await reject(resolveDiscount(input({...row(),...extra})));
});
test('free delivery applies the actual fee including zero and is never treated as a goods discount',async()=>{
 const p=input({...row(),type:'freeDelivery',value:0});assert.equal((await resolveDiscount(p)).amount,0);
 const r=await resolveDiscount({...p,deliveryFee:1234000});assert.equal(r.amount,1234000);assert.equal(r.snapshot.target,'DELIVERY');
});
test('promo GSI discovery is followed by strong source read; duplicate/changed code is rejected',async()=>{
 const calls=[],db={async send(c){calls.push(c.input);return c.input.IndexName?{Items:[{discountId:'p1'}]}:{Item:{discountId:'p1',code:'CODE'}};}};
 assert.equal((await readPromo(db,' CODE ')).discountId,'p1');assert.equal(calls[1].ConsistentRead,true);
 await reject(readPromo({async send(){return {Items:[{discountId:'p1'},{discountId:'p2'}]};}},'CODE'));
 await reject(readPromo({async send(c){return c.input.IndexName?{Items:[{discountId:'p1'}]}:{Item:{discountId:'p1',code:'OTHER'}};}},'CODE'));
});
test('platform counter aliases are synchronized and conflicting counters/segmentation rejected',async()=>{
 const raw={discountId:'p1',code:'CODE',status:'active',type:'fixed',value:100,usage:0,currentUsage:0,usageLimit:2,customerSegments:['all']};
 const make=r=>({...input(),discountId:null,promoCode:'CODE',db:{async send(c){return c.input.IndexName?{Items:[r]}:{Item:r};}}});
 const r=await resolveDiscount(make(raw));assert.equal(r.amount,100000);assert.equal(r.operations[0].Update.UpdateExpression,'SET #u0=:next, #u1=:next');
 await reject(resolveDiscount(make({...raw,currentUsage:1})));await reject(resolveDiscount(make({...raw,customerSegments:['new']})));
});
test('zero legacy usage limit explicitly means unlimited; malformed and unsafe money is rejected',()=>{
 const d=normalizeDiscount({...row(),usage_limit:0});assert.equal(validateDiscount(d,1).valid,true);
 for(const value of [NaN,Infinity,-1,101,0.0001,'10'])assert.equal(validateDiscount({...d,value},100).valid,false);
 assert.equal(validateDiscount({...d,validFrom:'nonsense'},100).valid,false);
 assert.equal(validatePlatformPromo(normalizePlatformPromo({type:'percentage',value:10}),100).valid,false);
});
test('discount integer rounding retains fractional IQD and has no binary float accumulation',()=>{
 const d=normalizeDiscount({...row(),value:33.333});assert.equal(calculateDiscountAmount(d,1001,[],0),334);
 assert.equal(calculateDiscountAmount({...d,type:'fixedAmount',value:0.001},1001,[],0),1);
});
test('customer view removes internal funding and agreement snapshot without changing the saved order',()=>{
 const {customerOrderView:view}=require('../src/functions/shared/customer-order-view');
 const saved={orderId:'o1',pricing:{total:1000},financialSnapshot:{secret:'internal'},commercialPricing:{commission:500}};
 const visible=view(saved);assert.equal(visible.financialSnapshot,undefined);assert.equal(visible.commercialPricing,undefined);
 assert.equal(visible.pricing.total,1000);assert.equal(saved.financialSnapshot.secret,'internal');
});

test('reservation pins funding fields even when absent and rejects malformed campaign versions',()=>{const {reserve}=require('../src/functions/shared/discount-reservation');const raw=row(),op=reserve(raw,'WhizzMerchants_Discounts',false).Update;assert(Object.values(op.ExpressionAttributeNames).includes('fundingPolicyId'));assert(Object.values(op.ExpressionAttributeNames).includes('fundingPolicyVersion'));assert.throws(()=>reserve({...raw,version:0},'WhizzMerchants_Discounts',false),/VERSION_INVALID/);});
