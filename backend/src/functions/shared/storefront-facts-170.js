'use strict';
// Public stored facts only. Delivery fields are legacy metadata, not an address-bound quote.
function storefrontFacts(value){
 const count=value.reviewCount??value.reviewsCount??value.ratingCount;
 const prep=value.orderReceptionSettings?.defaultPreparationMinutes;
 const text=v=>typeof v==='string'?v:typeof v==='number'&&Number.isFinite(v)?String(v):'';
 const agreements=Array.isArray(value.storefrontDeliveryAgreements)?value.storefrontDeliveryAgreements.filter(x=>x&&typeof x.id==='string'&&Number.isSafeInteger(x.version)&&x.version>0&&Number.isFinite(Date.parse(x.effectiveFrom))&&Number.isFinite(Date.parse(x.effectiveTo))&&Date.parse(x.effectiveFrom)<Date.parse(x.effectiveTo)&&Array.isArray(x.regionIds)&&x.regionIds.length>0&&x.regionIds.every(id=>typeof id==='string')&&Number.isSafeInteger(x.deliveryFeeIqd)&&x.deliveryFeeIqd>=0&&Number.isSafeInteger(x.minimumOrderAmountIqd)&&x.minimumOrderAmountIqd>=0).map(x=>({id:x.id,version:x.version,effectiveFrom:x.effectiveFrom,effectiveTo:x.effectiveTo,regionIds:x.regionIds,deliveryFeeIqd:x.deliveryFeeIqd,minimumOrderAmountIqd:x.minimumOrderAmountIqd})):[];
 return {minimumOrderAmountIqd:Number.isSafeInteger(value.minimum_order)&&value.minimum_order>0?value.minimum_order:null,storefrontDeliveryAgreements:agreements,rating:typeof value.rating==='number'&&Number.isFinite(value.rating)&&value.rating>=0&&value.rating<=5?value.rating:null,
  reviewCount:Number.isSafeInteger(count)&&count>=0?count:null,
  averagePreparationMinutes:Number.isInteger(prep)&&prep>=5&&prep<=120?prep:null,
  delivery_time:text(value.deliveryTime??value.delivery_time),delivery_fee:text(value.deliveryFee??value.delivery_fee)};
}
module.exports={storefrontFacts};
