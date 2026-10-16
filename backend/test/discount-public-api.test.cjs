const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const sdk=require('@aws-sdk/lib-dynamodb');
const engine=require('../src/functions/shared/discount-engine');
function loader(file,db,extra={}){
 const exports={},modules={'@aws-sdk/client-dynamodb':{DynamoDBClient:class{}},'@aws-sdk/lib-dynamodb':{...sdk,DynamoDBDocumentClient:{from:()=>db}},'./discount-engine':engine,...extra};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../src/functions/shared',file),'utf8'),{exports,Buffer,process:{env:{}},require:n=>{if(!modules[n])throw Error(n);return modules[n];}});return exports;
}
const raw=()=>({discountId:'d1',businessId:'b1',status:'active',type:'percentage',value:10,usage_count:0,title:'عرض',internalSecret:'hidden',createdBy:'staff'});
test('merchant listing continues empty pages, reads base row consistently and exposes only public fields',async()=>{
 const calls=[],db={async send(c){calls.push(c.input);if(c.input.Key)return {Item:raw()};return c.input.ExclusiveStartKey?{Items:[{discountId:'d1'}]}:{Items:[],LastEvaluatedKey:{discountId:'previous'}};}};
 const r=await loader('discount-list.js',db).list(false)({pathParameters:{businessId:'b1'}});
 assert.equal(r.statusCode,200);const b=JSON.parse(r.body);assert.equal(b.discounts.length,1);assert.equal(b.discounts[0].internalSecret,undefined);assert.equal(b.discounts[0].createdBy,undefined);assert.equal(calls.at(-1).ConsistentRead,true);
});
test('bounded incomplete listing is unavailable, never a successful partial list',async()=>{
 let calls=0;const r=await loader('discount-list.js',{async send(){calls++;return {Items:[],LastEvaluatedKey:{discountId:String(calls)}};}}).list(true)({});
 assert.equal(r.statusCode,503);assert.equal(JSON.parse(r.body).promos,undefined);assert.equal(calls,20);
});
test('foreign merchant source row is hidden despite a stale GSI match',async()=>{
 const r=await loader('discount-list.js',{async send(c){return c.input.Key?{Item:{...raw(),businessId:'foreign'}}:{Items:[{discountId:'d1'}]};}}).list(false)({pathParameters:{businessId:'b1'}});
 assert.equal(JSON.parse(r.body).count,0);
});
test('preview ignores client prices and totals, uses server catalog selectors and marks provisional response',async()=>{
 let selectors,resolved;
 const r=await loader('discount-preview.js',{}, {
  './discount-reservation':{resolveDiscount:async p=>{resolved=p;return {snapshot:{},amount:350000};}},
  '../create-order/quote-runtime/orderGoodsPricing':{createStagingOrderGoodsPricing:()=>({price:async p=>{selectors=p;return {goodsGross:{minorAmount:3500000}};}})}
 }).preview(true)({body:JSON.stringify({storeId:'b1',code:'X',orderTotal:1,deliveryFee:0,items:[{id:'p1',price:1,categoryId:'fake',quantity:1}]})});
 assert.equal(r.statusCode,200);assert.equal(selectors.items[0].price,undefined);assert.equal(selectors.items[0].productId,'p1');assert.equal(resolved.subtotal,3500000);assert.equal(resolved.deliveryFee,0);assert.equal(JSON.parse(r.body).previewOnly,true);
});
test('preview refuses missing selectors and sanitizes infrastructure failures',async()=>{
 const api=loader('discount-preview.js',{}, {
  './discount-reservation':{},'../create-order/quote-runtime/orderGoodsPricing':{createStagingOrderGoodsPricing:()=>({price:async()=>{throw Error('secret backend detail');}})}
 }).preview(true);
 assert.equal((await api({body:'{}'})).statusCode,400);
 const r=await api({body:JSON.stringify({storeId:'b1',code:'X',items:[],deliveryFee:1})});assert.equal(r.statusCode,503);assert.ok(!r.body.includes('secret'));
});
