'use strict';
// Public stored facts only. Delivery fields are legacy metadata, not an address-bound quote.
function storefrontFacts(value){
 const count=value.reviewCount??value.reviewsCount??value.ratingCount;
 const prep=value.orderReceptionSettings?.defaultPreparationMinutes;
 const text=v=>typeof v==='string'?v:typeof v==='number'&&Number.isFinite(v)?String(v):'';
 return {rating:typeof value.rating==='number'&&Number.isFinite(value.rating)&&value.rating>=0&&value.rating<=5?value.rating:null,
  reviewCount:Number.isSafeInteger(count)&&count>=0?count:null,
  averagePreparationMinutes:Number.isInteger(prep)&&prep>=5&&prep<=120?prep:null,
  delivery_time:text(value.deliveryTime??value.delivery_time),delivery_fee:text(value.deliveryFee??value.delivery_fee)};
}
module.exports={storefrontFacts};
