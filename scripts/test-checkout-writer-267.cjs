const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const C=path.resolve(__dirname,'../../whizzCentralPlatform-stg'),dist=C+'/backend/wallet-service/dist/';
const s=fs.readFileSync('/private/tmp/checkout-267/writer-candidate.js','utf8');
const begin=s.indexOf('// ../wizzuser-stg/backend/src/functions/create-order/quote-runtime/deliveryFundingReader.js\n');
const end=s.indexOf('\n// ../wizzuser-stg/backend/src/functions/create-order/quote-runtime/deliveryPromotion.js',begin);assert(begin>0&&end>begin);
const context={__name:x=>x,__commonJS:obj=>{let m;return()=>{if(!m){m={exports:{}};Object.values(obj)[0](m.exports,m);}return m.exports;}},
require_dist_cjs71:()=>require(C+'/backend/wallet-service/node_modules/@aws-sdk/lib-dynamodb'),
require_deliveryFundingPolicy:()=>require(dist+'deliveryFundingPolicy'),require_deliveryQuoteRecord:()=>require(dist+'deliveryQuoteRecord'),require_catalog:()=>require(C+'/backend/staff-service/catalog'),require_commercial_party:()=>require(C+'/backend/staff-service/commercial-party')};
context.candidate=Function(...Object.keys(context),s.slice(begin,end)+'\nreturn require_deliveryFundingReader();')(...Object.values(context));
const id=require.resolve(dist+'deliveryFundingReader');require(id);require.cache[id].exports=context.candidate;
// Candidate really forwards the permitted mode all the way from creator to reader.
assert(s.includes('db: dynamoDb, lifecycleReadMode: "CONDITION_CHECK"'));
assert(s.includes('createStagingDeliveryFundingReader)({ db, now, lifecycleReadMode: options.lifecycleReadMode })'));
module.exports=context.candidate;
if(!process.env.CHECKOUT_267_PREFLIGHT)require(C+'/backend/wallet-service/test/delivery-funding-reader.test.cjs');
