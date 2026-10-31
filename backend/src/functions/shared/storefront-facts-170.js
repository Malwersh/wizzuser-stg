'use strict';
// Public stored facts only. Delivery fields are legacy metadata, not an address-bound quote.
function storefrontFacts(value){
 const hasCustomer=Object.hasOwn(value,'customerRating')||Object.hasOwn(value,'customerRatingCount');
 const validCustomer=Number.isSafeInteger(value.customerRatingCount)&&value.customerRatingCount>0&&typeof value.customerRating==='number'&&Number.isFinite(value.customerRating)&&value.customerRating>=1&&value.customerRating<=5;
 const rating=hasCustomer?(validCustomer?value.customerRating:null):value.rating;
 const count=hasCustomer?(validCustomer?value.customerRatingCount:0):(value.reviewCount??value.reviewsCount??value.ratingCount);
 const prep=value.orderReceptionSettings?.defaultPreparationMinutes;
 const text=v=>typeof v==='string'?v:typeof v==='number'&&Number.isFinite(v)?String(v):'';
 const agreements=Array.isArray(value.storefrontDeliveryAgreements)?value.storefrontDeliveryAgreements.filter(x=>x&&typeof x.id==='string'&&Number.isSafeInteger(x.version)&&x.version>0&&Number.isFinite(Date.parse(x.effectiveFrom))&&Number.isFinite(Date.parse(x.effectiveTo))&&Date.parse(x.effectiveFrom)<Date.parse(x.effectiveTo)&&Array.isArray(x.regionIds)&&x.regionIds.length>0&&x.regionIds.every(id=>typeof id==='string')&&Number.isSafeInteger(x.deliveryFeeIqd)&&x.deliveryFeeIqd>=0&&Number.isSafeInteger(x.minimumOrderAmountIqd)&&x.minimumOrderAmountIqd>=0).map(x=>({id:x.id,version:x.version,effectiveFrom:x.effectiveFrom,effectiveTo:x.effectiveTo,regionIds:x.regionIds,deliveryFeeIqd:x.deliveryFeeIqd,minimumOrderAmountIqd:x.minimumOrderAmountIqd})):[];
 return {minimumOrderAmountIqd:Number.isSafeInteger(value.minimum_order)&&value.minimum_order>0?value.minimum_order:null,storefrontDeliveryAgreements:agreements,rating:typeof rating==='number'&&Number.isFinite(rating)&&rating>=0&&rating<=5?rating:null,
  reviewCount:Number.isSafeInteger(count)&&count>=0?count:null,
  averagePreparationMinutes:Number.isInteger(prep)&&prep>=5&&prep<=120?prep:null,
  delivery_time:text(value.deliveryTime??value.delivery_time),delivery_fee:text(value.deliveryFee??value.delivery_fee)};
}
module.exports={storefrontFacts};
