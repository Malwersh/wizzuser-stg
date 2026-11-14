const {test}=require('node:test'),assert=require('node:assert/strict');
const m=require('../src/functions/shared/branch-minimum-order');
test('legacy branch read is consistent and canonical minimum is optional',async()=>{
 let input;const b=await m.read({send:async c=>{input=c.input;return {Item:{businessId:'b',minimum_order:1500}};}},'b');assert.equal(input.ConsistentRead,true);assert.equal(m.minimumOrderIqd(b),1500);
 assert.throws(()=>m.assertMinimumOrder(b,1499000),e=>e.code==='MINIMUM_ORDER_NOT_MET');m.assertMinimumOrder(b,1500000);
 for(const value of [null,0])assert.equal(m.minimumOrderIqd({minimum_order:value}),null);
});
test('legacy existing branch transaction guard pins missing, null, zero and configured minimum without a duplicate branch item',()=>{
 for(const value of [undefined,null,0,1500]){const c={ConditionExpression:'attribute_exists(businessId)',ExpressionAttributeNames:{'#status':'status'},ExpressionAttributeValues:{':ok':true}};assert.equal(m.guard(c,{minimum_order:value}),c);assert.equal(c.ExpressionAttributeNames['#minimum173'],'minimum_order');if(value===undefined)assert.ok(c.ConditionExpression.includes('attribute_not_exists(#minimum173)'));else assert.equal(c.ExpressionAttributeValues[':minimum173'],value);}
});
test('invalid or foreign branch minimum is never treated as unset',async()=>{
 for(const value of [-1,1.5,'1500'])assert.throws(()=>m.minimumOrderIqd({minimum_order:value}));
 await assert.rejects(m.read({send:async()=>({Item:{businessId:'other'}})},'b'));
});
