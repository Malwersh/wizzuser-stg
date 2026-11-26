'use strict';
// Same canonical minimum parser as the commercial writer; persisted field is minimum_order.
const {GetCommand}=require('@aws-sdk/lib-dynamodb');
const canonical=require('../create-order/quote-runtime/branchMinimumOrder');
async function read(db,branchId){
 const b=(await db.send(new GetCommand({TableName:process.env.BUSINESSES_TABLE||'WhizzMerchants_Businesses',Key:{businessId:branchId},ConsistentRead:true,ProjectionExpression:'businessId, minimum_order'}))).Item;
 if(!b||b.businessId!==branchId)throw Object.assign(Error('GOODS_UNAVAILABLE'),{statusCode:409});
 canonical.minimumOrderIqd(b);return b;
}
function guard(condition,branch){
 condition.ExpressionAttributeNames['#minimum173']='minimum_order';
 if(branch.minimum_order===undefined)condition.ConditionExpression+=' AND attribute_not_exists(#minimum173)';
 else {condition.ConditionExpression+=' AND #minimum173=:minimum173';condition.ExpressionAttributeValues[':minimum173']=branch.minimum_order;}
 return condition;
}
module.exports={...canonical,read,guard};
