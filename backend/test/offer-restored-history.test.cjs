'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {history,customerState,eligibility}=require('../src/functions/shared/offer-eligibility');
const restored={schemaVersion:1,policy:'BEFORE_MERCHANT_ACCEPTANCE',releasedAt:'2026-01-01'};
test('history excludes explicitly restored orders, retaining pending and post-acceptance cancellations',async()=>{
 const rows=[
  {createdAt:'2026-01-01',status:'cancelled',discountId:'d',offerUsageRelease:restored},
  {createdAt:'2026-01-02',status:'pending',discountId:'d'},
  {createdAt:'2026-01-03',status:'cancelled',promoCode:'CODE',offerSnapshot:{source:'PLATFORM',discountId:'p'}},
 ];
 const r=await history({send:async()=>({Items:rows})},'subject','user');
 assert.equal(r.count,2);assert.equal(r.uses['id:d'],1);assert.equal(r.uses['platform-id:p'],1);
 assert.equal(r.lastAt,Date.parse('2026-01-03'));
});
test('restored first order remains eligible even if journey counters must be rebuilt',async()=>{
 const db={async send(c){return c.constructor.name==='ScanCommand'?{Items:[{createdAt:'2026-01-01',discountId:'d',offerUsageRelease:restored}]}:{};}};
 const identity={sub:'subject',userId:'user'},customer=await customerState(db,identity);
 assert.equal(await customer.getCount(),0);
 const result=await eligibility(db,{discountId:'d',firstOrderOnly:true,customerSegments:['all']},{identity,customer,preview:true});
 assert.equal(result.redemption,null);
});
test('code-less platform offers enforce per-customer usage from immutable order snapshots',async()=>{
 const db={async send(c){return c.constructor.name==='ScanCommand'?{Items:[{createdAt:'2026-01-01',offerSnapshot:{source:'PLATFORM',discountId:'p'}}]}:{};}};
 const identity={sub:'subject',userId:'user'},customer=await customerState(db,identity);
 await assert.rejects(eligibility(db,{discountId:'p',code:'',singleUse:true},{identity,customer,preview:true}),/OFFER_ALREADY_USED/);
});
test('customer order views omit internal reservation and restoration proof',()=>{
 const {customerOrderView}=require('../src/functions/shared/customer-order-view');
 const view=customerOrderView({orderId:'o',offerUsageReservation:{userSub:'private'},offerUsageRelease:restored});
 assert.deepEqual(view,{orderId:'o'});
});
