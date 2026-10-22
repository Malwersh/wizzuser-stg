'use strict';
const { GetCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const {normalizeDiscount, normalizePlatformPromo, validateDiscount, validatePlatformPromo, calculateCheckoutDiscountAmount} = require('./discount-engine');
const {validVersion}=require('./campaign-version');
const {eligibility,catalogItems}=require('./offer-eligibility');
const fail = () => {throw Object.assign(Error('DISCOUNT_UNAVAILABLE'), {statusCode:409});};
const merchantTable = process.env.DISCOUNTS_TABLE || 'WhizzMerchants_Discounts';
const platformTable = process.env.PLATFORM_DISCOUNTS_TABLE || 'WizzCentral_Platform_Discounts';
const fields = ['discountId','businessId','code','status','isActive','type','discountType','value','discountValue',
 'applicability','applicable_item_ids','applicable_category_ids','conditionalParameters','conditional_parameters',
 'validFrom','validTo','valid_from','valid_to','startDate','endDate','minimumOrderAmount','minimum_order_amount',
 'minOrderAmount','minOrderValue','usageCount','usage_count','usage','currentUsage','usageLimit','usage_limit','limit',
 'version','fundingPolicyId','fundingPolicyVersion','updatedAt','updated_at','funding','merchantShare','platformShare','maxDiscount','maxDiscountAmount',
 'allowedBusinessIds','businessIds','customerIds','firstOrderOnly','perCustomerLimit',
 'isDeleted','deletedAt','deletionStatus','target','targetRestaurants','targetSegments','customerSegments','occasions','singleUse','applicableToAll',
 // Live audience constraints must be pinned even when absent at preview time.
 'targetRegionIds','campaignType'];
// Pin all observed fields plus absence of known constraints: concurrent edits or usage invalidate the order.
function reserve(raw, table, platform) {
 validVersion(raw);
 const names={},values={},conditions=[];
 for(const [i,f] of [...new Set([...fields,...Object.keys(raw)])].entries()) {
  names['#r'+i]=f;
  if(raw[f] === undefined)conditions.push('attribute_not_exists(#r'+i+')');
  else {values[':r'+i]=raw[f];conditions.push('#r'+i+' = :r'+i);}
 }
 const d=platform?normalizePlatformPromo(raw):normalizeDiscount(raw);
 const count=d.usageCount;
 if(!Number.isSafeInteger(count)||count<0||count>=Number.MAX_SAFE_INTEGER)fail();
 const counters=platform?['usage','currentUsage']:['usage_count',...(raw.usageCount!==undefined?['usageCount']:[])];
 values[':next']=count+1;
 const updates=counters.map((f,i)=>{names['#u'+i]=f;return '#u'+i+'=:next';});
 const condition=conditions.join(' AND '); if(Buffer.byteLength(condition)>3900)fail();
 return {Update:{TableName:table,Key:{discountId:raw.discountId},UpdateExpression:'SET '+updates.join(', '),
  ConditionExpression:condition,ExpressionAttributeNames:names,ExpressionAttributeValues:values}};
}
async function readPromo(db,code) {
 if(typeof code!=='string'||!code.trim()||code.length>80)fail();
 const matches=await db.send(new QueryCommand({TableName:platformTable,IndexName:'code-index',
  KeyConditionExpression:'#c=:c',ExpressionAttributeNames:{'#c':'code'},ExpressionAttributeValues:{':c':code.trim()},Limit:2}));
 if(matches.LastEvaluatedKey||matches.Items?.length!==1||!matches.Items[0].discountId)fail();
 const raw=(await db.send(new GetCommand({TableName:platformTable,Key:{discountId:matches.Items[0].discountId},ConsistentRead:true}))).Item;
 if(!raw||raw.code!==code.trim())fail(); return raw;
}
async function resolveDiscount({db,branchId,discountId,promoCode,platformDiscountId,subtotal,items,deliveryFee,identity,customer,regionIds=[],preview=false,orderId,guarded}) {
 if(discountId&&(promoCode||platformDiscountId))fail();
 if (discountId !== undefined && discountId !== null && (typeof discountId !== 'string' || !/^[A-Za-z0-9_-]{1,150}$/.test(discountId))) fail();
 if(!discountId&&!promoCode&&!platformDiscountId)return {amount:0,operations:[],snapshot:null};
 const platform=!!(promoCode||platformDiscountId);
 if(platformDiscountId&&(typeof platformDiscountId!=='string'||!/^[-\w]{1,150}$/.test(platformDiscountId)))fail();
 const raw=platform?(platformDiscountId?(await db.send(new GetCommand({TableName:platformTable,Key:{discountId:platformDiscountId},ConsistentRead:true}))).Item:await readPromo(db,promoCode)):(await db.send(new GetCommand({TableName:merchantTable,Key:{discountId},ConsistentRead:true}))).Item;
 if(!raw||raw.isDeleted===true||raw.deletedAt!=null||raw.deletionStatus!=null||raw.isActive===false||(!platform&&(raw.discountId!==discountId||raw.businessId!==branchId)))fail();
 if(platformDiscountId&&promoCode&&raw.code!==promoCode)fail();
 if(platform&&raw.benefit)return require('./platform-benefits').resolve(db,raw,{identity,customer,regionIds,guarded},{branchId,subtotal,items,deliveryFee,preview,orderId});
 let d;try{d=platform?normalizePlatformPromo(raw):normalizeDiscount(raw);}catch{fail();}
 // Commercial delivery savings require an approved, budgeted delivery policy.
 // A legacy coupon is never authority to fund delivery through goods accounting.
 if(process.env.COMMERCIAL_PRICING_MODE==='REQUIRED'&&d.type==='freeDelivery')
  throw Object.assign(Error('OFFER_DELIVERY_POLICY_REQUIRED'),{statusCode:409});
 if (!['allItems','minimumOrder','specificItems','specificCategories',undefined].includes(d.applicability)) fail();
 if(d.applicability==='specificItems'&&(!Array.isArray(d.applicable_item_ids)||!d.applicable_item_ids.length))fail();
 if(d.applicability==='specificCategories'&&(!Array.isArray(d.applicable_category_ids)||!d.applicable_category_ids.length))fail();
 if(!(platform?validatePlatformPromo(d,subtotal):validateDiscount(d,subtotal)).valid)fail();
 const eligible=await eligibility(db,raw,{identity,customer,regionIds,branchId,source:platform?'platform':'merchant',preview});
 const eligibleItems=(items||[]).filter(i=>d.applicability==='specificItems'?d.applicable_item_ids.includes(i.itemId||i.id):d.applicability==='specificCategories'?d.applicable_category_ids.includes(i.categoryId):true);
 if(['specificItems','specificCategories'].includes(d.applicability)&&!eligibleItems.length)fail();
 let amount;try{amount=calculateCheckoutDiscountAmount(d,subtotal,items,deliveryFee);}catch{fail();}

 // A zero-saving offer must never consume campaign or customer usage.
 if(amount===0)throw Object.assign(Error('OFFER_NO_SAVINGS'),{statusCode:409});
 if(!Number.isSafeInteger(amount)||amount<0||amount>(d.type==='freeDelivery'?deliveryFee:subtotal))fail();
 const lines=[];let remaining=amount;const basis=eligibleItems.reduce((sum,i)=>sum+i.price*i.quantity,0);
 if(d.type!=='freeDelivery'&&basis>0){for(let n=0;n<eligibleItems.length;n++){const i=eligibleItems[n],gross=i.price*i.quantity,saving=n===eligibleItems.length-1?remaining:Number(BigInt(amount)*BigInt(gross)/BigInt(basis));remaining-=saving;lines.push({itemId:i.itemId||i.id,...(i.lineId?{lineId:i.lineId}:{}),grossFils:gross,savingsFils:saving,netFils:gross-saving});}}
 return {amount,lines,campaign:raw,expiresAt:d.validTo?Date.parse(d.validTo):null,operations:[reserve(raw,platform?platformTable:merchantTable,platform),...(eligible.redemption?[eligible.redemption]:[])],
  snapshot:{discountId:raw.discountId,source:platform?'PLATFORM':'MERCHANT',type:d.type,target:d.type==='freeDelivery'?'DELIVERY':'GOODS',
   amount,version:raw.version??null,updatedAt:raw.updatedAt??raw.updated_at??null,
   // Explicitly a legacy checkout snapshot, not a commercial funding or settlement proof.
   provesFunding:false}};
}
module.exports={resolveDiscount,readPromo,reserve};
