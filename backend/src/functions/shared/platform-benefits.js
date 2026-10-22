'use strict';
const {GetCommand,ScanCommand}=require('@aws-sdk/lib-dynamodb');
const {preparePlatformBenefit,platformBenefitBalance,platformBenefitEligibility}=require('./platform-benefits-runtime');
const {fence}=require('./campaign-version');
const TABLE='WizzCentral_Platform_Discounts';
const fail=code=>{throw Object.assign(Error(code),{statusCode:409});};
async function facts(context,branchId,goodsMinor,roadMeters){
 if(!context.identity?.sub||context.guarded?.sub!==context.identity.sub||!context.guarded.condition)fail('BENEFIT_LOGIN_REQUIRED');
 const count=await context.customer.getCount(),joined=Date.parse(context.identity.profile?.createdAt),last=context.customer.stored?.historyRequired?(await context.customer.history()).lastAt:context.customer.stored?.lastAt??(count?(await context.customer.history()).lastAt:0);
 return {sub:context.identity.sub,branchId,regionIds:context.regionIds||[],goodsMinor,roadMeters,firstOrder:count===0,newCustomer:Number.isFinite(joined)&&Date.now()>=joined&&Date.now()-joined<7*86400000,vip:context.identity.profile?.isVip===true,inactive:count>0&&last>0&&Date.now()-last>=30*86400000};
}
async function resolve(db,campaign,context,{branchId,subtotal,items,deliveryFee,preview=false,orderId}){
 if(process.env.COMMERCIAL_PRICING_MODE!=='REQUIRED')fail('BENEFIT_COMMERCIAL_CHECKOUT_REQUIRED');
 const trusted=await facts(context,branchId,subtotal);
 if(campaign.benefit.kind!=='GOODS_AMOUNT'){const check=preview?await preparePlatformBenefit(db,{campaign,facts:trusted,referenceDeliveryMinor:deliveryFee,preview:true}):null;return {amount:0,operations:[],snapshot:null,campaign,platformDeliveryBenefit:{campaign,context},deliveryBenefit:true,deliveryBenefitSavingAmount:(check?.amountMinor||0)/1000};}
 const result=await preparePlatformBenefit(db,{campaign,facts:trusted,orderId,preview,now:Date.now()});
 let rest=result.amountMinor;const lines=items.map((i,n)=>{const gross=i.price*i.quantity,saving=n===items.length-1?rest:Number(BigInt(result.amountMinor)*BigInt(gross)/BigInt(subtotal));rest-=saving;return {itemId:i.itemId||i.id,...(i.lineId?{lineId:i.lineId}:{}),grossFils:gross,savingsFils:saving,netFils:gross-saving};});
 return {amount:result.amountMinor,lines,campaign,expiresAt:Date.parse(campaign.endDate),operations:[{ConditionCheck:{TableName:TABLE,Key:{discountId:campaign.discountId},...fence(campaign)}},...result.operations],benefitReceipt:result.receipt,snapshot:{discountId:campaign.discountId,source:'PLATFORM',type:'fixedAmount',target:'GOODS',amount:result.amountMinor,version:campaign.version,updatedAt:campaign.updatedAt,provesFunding:false}};
}
function deliverySelection(db,selected,pricingRequest,previewOnly){
 return {async prepare(input){
  const result=await preparePlatformBenefit(db,{campaign:selected.campaign,facts:await facts(selected.context,input.branchId,input.goodsGross.minorAmount,pricingRequest.deliveryRoute.distanceMeters),orderId:input.orderId,referenceDeliveryMinor:input.referenceFee.minorAmount,hasGoodsDiscount:input.hasGoodsDiscount,preview:previewOnly});
  return {applied:true,deliveryFunding:result.deliveryFunding,customerFee:result.customerFee,validUntil:result.validUntil,operations:[{ConditionCheck:{TableName:TABLE,Key:{discountId:selected.campaign.discountId},...fence(selected.campaign)}},...result.operations],customerRule:selected.campaign.benefit.kind==='FREE_DELIVERIES'?'FREE':'AMOUNT_OFF',benefitReceipt:result.receipt};
 }};
}
async function list(db,event){
 const q=event.queryStringParameters||{},context=await require('./offer-context').offerContext(db,event,{userId:q.userId,addressId:q.addressId});const trusted=await facts(context,q.businessId),items=[];let cursor;
 for(let page=0;page<20;page++){
  const response=await db.send(new ScanCommand({TableName:TABLE,ConsistentRead:true,Limit:50,ExclusiveStartKey:cursor}));
  for(const campaign of response.Items||[]){if(!campaign.benefit||campaign.isDeleted||campaign.deletedAt||!['active','paused'].includes(campaign.status))continue;
   const balance=await platformBenefitBalance(db,campaign,trusted.sub);if(!balance.granted||balance.revoked)continue;
   const reason=platformBenefitEligibility(campaign,trusted)||(balance.remaining<1?'BENEFIT_EXHAUSTED':null);
   // Never disclose a directly-targeted entitlement to another customer.
   if(['BENEFIT_NOT_ELIGIBLE','BENEFIT_WRONG_REGION','BENEFIT_WRONG_BRANCH'].includes(reason))continue;
   const b=campaign.benefit;items.push({schemaVersion:1,id:campaign.discountId,title:campaign.title,description:campaign.description,kind:b.kind,amountIqd:b.amountIqd,maximumPerOrderIqd:b.maximumPerOrderIqd,minimumGoodsIqd:b.minimumGoodsIqd,maximumRoadMeters:b.maximumRoadMeters,branchIds:b.branchIds,regionIds:b.regionIds,startAt:campaign.startDate,endAt:campaign.endDate,granted:balance.granted,reserved:balance.reserved,used:balance.used,remaining:balance.remaining,eligible:!reason,reason,allowGoodsStacking:b.allowGoodsStacking});
  }
  cursor=response.LastEvaluatedKey;if(!cursor)return {success:true,benefits:items};
 }fail('BENEFIT_LIST_LIMIT');
}
async function loadDelivery(db,discountId,context){
 if(typeof discountId!=='string'||!/^[A-Za-z0-9_-]{1,100}$/.test(discountId))fail('BENEFIT_INVALID');
 const campaign=(await db.send(new GetCommand({TableName:TABLE,Key:{discountId},ConsistentRead:true}))).Item;
 if(!campaign?.benefit||campaign.benefit.kind==='GOODS_AMOUNT')fail('BENEFIT_NOT_ELIGIBLE');
 return {campaign,context};
}
function assertStacking(goods,delivery){if(goods&&delivery&&(!goods.benefit?.allowGoodsStacking||!delivery.benefit?.allowGoodsStacking))fail('BENEFIT_STACKING_DENIED');}
async function previewStacking(db,result,body){
 if(!result.campaign?.benefit){if(body.deliveryBenefitId)fail('BENEFIT_STACKING_DENIED');return;}
 if(result.deliveryBenefit&&(body.existingPlatformDiscountId||body.existingDiscountId||body.existingPromoCode)){
  if(body.existingDiscountId||body.existingPromoCode)fail('BENEFIT_STACKING_DENIED');
  if(typeof body.existingPlatformDiscountId!=='string'||!/^[A-Za-z0-9_-]{1,100}$/.test(body.existingPlatformDiscountId))fail('BENEFIT_INVALID');
  const goods=(await db.send(new GetCommand({TableName:TABLE,Key:{discountId:body.existingPlatformDiscountId},ConsistentRead:true}))).Item;
  if(!goods?.benefit||goods.benefit.kind!=='GOODS_AMOUNT')fail('BENEFIT_STACKING_DENIED');assertStacking(goods,result.campaign);
 }else if(!result.deliveryBenefit&&body.deliveryBenefitId){const delivery=await loadDelivery(db,body.deliveryBenefitId,{});assertStacking(result.campaign,delivery.campaign);}
}
module.exports={resolve,facts,deliverySelection,list,loadDelivery,assertStacking,previewStacking};
