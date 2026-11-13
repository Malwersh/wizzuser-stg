const {test}=require('node:test');const assert=require('node:assert/strict');
const {enrich}=require('../src/functions/shared/menu-item-prices');
const branch='business_test',id='product_test',category='category_test';
function db(available=true){return {async send(c){const k=c.input.Key;
 if(k.sk==='MENU_VERSION#ACTIVE')return {Item:{publishedVersion:'v1'}};
 if(k.sk)return {Item:{version:'v1',product:{productId:id,businessId:branch,categoryId:category,name:'وجبة',price:10000,isAvailable:true,cuisineIds:['shawarma']}}};
 if(k.productId)return {Item:{productId:id,businessId:branch,isAvailable:available}};
 return {Item:{categoryId:category,businessId:branch,isActive:true}};
}};}
function offer(){return {discountId:'sale',businessId:branch,type:'percentage',value:20,calculationMode:'perItem',applicability:'specificItems',applicable_item_ids:[id]};}
test('published cuisine metadata does not suppress item sale price',async()=>{const row=offer();await enrich(db(),branch,[row],[id]);assert.deepEqual(row.itemPrices,[{productId:id,originalUnitFils:10000000,savingUnitFils:2000000,netUnitFils:8000000}]);});
test('unavailable live product still has no sale projection',async()=>{const row=offer();await enrich(db(false),branch,[row],[id]);assert.deepEqual(row.itemPrices,[]);});
