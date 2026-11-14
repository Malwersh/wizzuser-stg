const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{createRequire}=require('node:module');
const C=path.resolve(__dirname,'../../whizzCentralPlatform-stg'),p='/private/tmp/checkout-270',sdk=require(C+'/backend/wallet-service/node_modules/@aws-sdk/lib-dynamodb');
const file=p+'/runtime/_discount_review/user-create-order/index.js',s=fs.readFileSync(file,'utf8'),at=s.indexOf('// ../wizzuser-stg/backend/src/functions/create-order/index.js');assert(at>0);
const names=['deliveryFundingPolicy','deliveryFundingReader','deliveryPromotionSelection','deliveryCampaignBudget','deliveryFundedAllocation','orderCommercialSource','deliveryQuoteOrder'];
const runtime=Function('require','module','exports','__dirname',s.slice(0,at)+'\nreturn {'+names.map(n=>n+':require_'+n+'()').join(',')+'};')(createRequire(file),{exports:{}},{},path.dirname(file));
const mapDb=db=>({send:c=>{const kind=c.constructor.name.replace(/\d+$/,'');assert(sdk[kind],kind);return db.send(new sdk[kind](c.input));}});
for(const name of names){const id=require.resolve(C+'/backend/wallet-service/dist/'+name);require(id);const out={...runtime[name]};for(const[k,v]of Object.entries(out))if(typeof v==='function'&&/^createStaging/.test(k))out[k]=options=>v({...options,db:mapDb(options.db)});require.cache[id].exports=out;}
module.exports={runtime,mapDb,sdk,C};
