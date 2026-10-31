'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const engine=require('../src/functions/shared/discount-engine');
const merchant={discountId:'d1',businessId:'branch',status:'active',type:'percentage',value:12.5,usage_count:0,version:1};
const normalize=r=>engine.normalizeDiscount(r);
function resolver(row) {
 class GetCommand {constructor(input){this.input=input;}}
 const module={exports:{}};
 const modules={
  '@aws-sdk/lib-dynamodb':{GetCommand},
  './discount-engine':engine,
  './campaign-version':require('../src/functions/shared/campaign-version'),
  './offer-eligibility':{eligibility:async()=>({})},
 };
 vm.runInNewContext(fs.readFileSync(require.resolve('../src/functions/shared/discount-reservation'),'utf8'),{
  module,Buffer,process:{env:{}},require:n=>{assert.ok(n in modules,n);return modules[n];}
 });
 return options=>module.exports.resolveDiscount({db:{async send(){return {Item:row};}},branchId:'branch',
  discountId:'d1',subtotal:10007000,items:[{itemId:'p1',price:10007000,quantity:1}],deliveryFee:0,...options});
}

test('checkout rounds down while the internal calculator preserves fils',()=>{
 const d=normalize(merchant);
 assert.equal(engine.calculateDiscountAmount(d,10007000,[],0),1250875);
 assert.equal(engine.calculateCheckoutDiscountAmount(d,10007000,[],0),1250000);
 const fractional=normalize({...merchant,value:33.333});
 assert.equal(engine.calculateDiscountAmount(fractional,1001,[],0),334);
 assert.equal(engine.calculateCheckoutDiscountAmount(fractional,1001,[],0),0);
});
test('caps and eligible goods are applied before rounding down',()=>{
 const d=normalize({...merchant,maxDiscountAmount:100.999});
 assert.equal(engine.calculateCheckoutDiscountAmount(d,10007000,[],0),0);
 const scoped=normalize({...merchant,type:'fixedAmount',value:5000.999,applicability:'specificItems',applicable_item_ids:['p1']});
 assert.equal(engine.calculateCheckoutDiscountAmount(scoped,10007000,[
  {itemId:'p1',price:1500999,quantity:1},{itemId:'other',price:8506001,quantity:1}
 ],0),1500000);
});
test('fixed discounts, delivery savings and exact whole amounts use the same quantum',()=>{
 for(const [patch,fee,want] of [
  [{type:'fixedAmount',value:1250.875},0,1250000],
  [{type:'fixedAmount',value:1250},0,1250000],
  [{type:'freeDelivery',value:0},1250875,1250000],
  [{type:'freeDelivery',value:0},0,0],
 ])assert.equal(engine.calculateCheckoutDiscountAmount(normalize({...merchant,...patch}),10007000,[],fee),want);
});
test('preview and commit reserve identical 250-IQD snapshots and allocate their exact total',async()=>{
 for(const source of ['MERCHANT','PLATFORM']) {
  const row=source==='MERCHANT'?merchant:{...merchant,usage:0,currentUsage:0};
  const resolve=resolver(row),options=source==='PLATFORM'?{discountId:null,platformDiscountId:'d1'}:{};
  const preview=await resolve({...options,preview:true}),commit=await resolve(options);
  assert.equal(preview.amount,1250000);
  assert.equal(commit.amount,preview.amount);
  assert.equal(commit.snapshot.amount,preview.amount);
  assert.equal(commit.snapshot.source,source);
  assert.equal(commit.amount%250000,0);
  assert.equal(commit.lines.reduce((sum,l)=>sum+l.savingsFils,0),commit.amount);
  assert.equal(commit.lines[0].netFils,8757000);
  assert.equal(commit.operations[0].Update.ExpressionAttributeValues[':next'],1);
 }
});
test('rounding remains bounded and idempotent across percentage and cap boundaries',()=>{
 for(const value of [0.001,12.5,33.333,100])for(const total of [0,1,999,1000,1001,10007000])for(const cap of [undefined,0,0.999,1.001,1250.875]) {
  const d=normalize({...merchant,value,maxDiscountAmount:cap});
  const precise=engine.calculateDiscountAmount(d,total,[],0),rounded=engine.calculateCheckoutDiscountAmount(d,total,[],0);
  assert.ok(rounded>=0&&rounded<=precise&&rounded<=total);
  assert.equal(rounded%250000,0);
  assert.equal(Number(BigInt(rounded)/250000n*250000n),rounded);
 }
});

test('fractional fils never round checkout savings up across an IQD boundary',()=>{
 const d=normalize({...merchant,value:99.999});
 // 99.999% of 1000.01 IQD is exactly 999.9999999 IQD.
 assert.equal(engine.calculateDiscountAmount(d,1000010,[],0),1000000);
 assert.equal(engine.calculateCheckoutDiscountAmount(d,1000010,[],0),750000);
 const scoped=normalize({...merchant,value:99.999,applicability:'specificItems',applicable_item_ids:['p1']});
 assert.equal(engine.calculateCheckoutDiscountAmount(scoped,2000010,[{itemId:'p1',price:1000010,quantity:1},{itemId:'other',price:1000000,quantity:1}],0),750000);
});
test('checkout percentage savings match exact rational arithmetic near 250-IQD boundaries',()=>{
 for(const value of [0.001,12.499,33.333,99.999,100])for(const total of [999999,1000000,1000001,1000010,3000001])for(const cap of [undefined,999.999,1000]){
  const d=normalize({...merchant,value,maxDiscountAmount:cap});
  const numerator=BigInt(total)*BigInt(engine.decimalThousand(value));
  const eligible=numerator/100000n;
  const bounded=cap==null?eligible:eligible<BigInt(engine.decimalThousand(cap))?eligible:BigInt(engine.decimalThousand(cap));
  assert.equal(engine.calculateCheckoutDiscountAmount(d,total,[],0),Number(bounded/250000n*250000n));
 }
});

test('cash denomination examples round down to 250 IQD without exceeding savings',()=>{
 for(const [value,want] of [[1250.875,1250000],[1100,1000000],[249,0],[250,250000],[499.999,250000],[500,500000]]){
  const d=normalize({...merchant,type:'fixedAmount',value});
  assert.equal(engine.calculateCheckoutDiscountAmount(d,10000000,[],0),want);
  assert.equal(engine.calculateDiscountAmount(d,10000000,[],0),engine.decimalThousand(value));
 }
});

test('discount allocation retains configuration identity and conserves total savings',async()=>{
 const r=await resolver(merchant)({subtotal:10007000,items:[{itemId:'p1',lineId:'CONFIG#salad',price:5000000,quantity:1},{itemId:'p1',lineId:'CONFIG#rice',price:5007000,quantity:1}]});
 assert.deepEqual(Array.from(r.lines,l=>l.lineId),['CONFIG#salad','CONFIG#rice']);
 assert.equal(r.lines.reduce((sum,l)=>sum+l.savingsFils,0),r.amount);
});
