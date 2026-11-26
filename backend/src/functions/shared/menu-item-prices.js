'use strict';
const {normalizeDiscount}=require('./discount-engine');
exports.enrich = async (db, branch, rows, itemIds, commands = require('@aws-sdk/lib-dynamodb')) => {
 const readOnlyDb={send(command){if(command?.constructor?.name?.replace(/\d+$/,'')!=='GetCommand')throw Error('ITEM_PRICE_READ_ONLY');return db.send(new commands.GetCommand(command.input));}};
     const pricing=require('../create-order/quote-runtime/orderGoodsPricing').createStagingOrderGoodsPricing({db:readOnlyDb});
     const eligible=new Set(rows.filter(d=>d.calculationMode==='perItem').flatMap(d=>d.applicable_item_ids));
     const priced=new Map();
     const wanted=itemIds.filter(id=>eligible.has(id));
     for(let n=0;n<wanted.length;n+=4)await Promise.all(wanted.slice(n,n+4).map(async id=>{
      try {const result=await pricing.price({branchId:branch,items:[{productId:id,quantity:1}]});const line=result.lines[0];
       priced.set(id,{price:line.unitPrice.minorAmount,quantity:1,itemId:id});}catch(e){if(!['GOODS_UNAVAILABLE','INVALID_GOODS_SELECTION','GOODS_PRICING_UNSUPPORTED'].includes(e.code))throw e;}
     }));
     for(const row of rows)if(row.calculationMode==='perItem') {
      row.pricingRevision=require('crypto').createHash('sha256').update(JSON.stringify(row)).digest('hex');
      row.itemPrices=[];row.itemPricesValidUntil=new Date(Math.min(Date.now()+60000,row.validTo?Date.parse(row.validTo):Infinity)).toISOString();
      for(const id of row.applicable_item_ids||[])if(priced.has(id)) {
       const item=priced.get(id),d=normalizeDiscount({...row,status:'active',usage_count:0});
       const saving=require('./discount-engine').calculateCheckoutDiscountAmount(d,item.price,[item],0);
       if(saving>0)row.itemPrices.push({productId:id,originalUnitFils:item.price,savingUnitFils:saving,netUnitFils:item.price-saving});
      }
     }

};
