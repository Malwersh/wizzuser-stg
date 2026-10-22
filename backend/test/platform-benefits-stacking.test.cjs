'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {previewStacking}=require('../src/functions/shared/platform-benefits');
const selected=allow=>({deliveryBenefit:true,campaign:{benefit:{allowGoodsStacking:allow}}});
test('delivery preview rejects merchant and manual code discounts before checkout',async()=>{
 for(const body of [{existingDiscountId:'merchant'},{existingPromoCode:'CODE'}])await assert.rejects(previewStacking({},selected(true),body),/STACKING_DENIED/);
});
test('goods and delivery stacking requires explicit permission from both benefits',async()=>{
 for(const goods of [false,true])for(const delivery of [false,true]){
  const db={send:async()=>({Item:{benefit:{kind:'GOODS_AMOUNT',allowGoodsStacking:goods}}})};
  const result=previewStacking(db,selected(delivery),{existingPlatformDiscountId:'goods'});
  if(goods&&delivery)await result;else await assert.rejects(result,/STACKING_DENIED/);
 }
});
test('ordinary goods promotion cannot stack with a selected delivery benefit',async()=>{
 await assert.rejects(previewStacking({}, {campaign:{}},{deliveryBenefitId:'delivery'}),/STACKING_DENIED/);
});
