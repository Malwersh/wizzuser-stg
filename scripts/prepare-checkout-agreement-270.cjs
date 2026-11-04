'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),cp=require('node:child_process');
const U=path.resolve(__dirname,'..'),C=path.resolve(U,'../whizzCentralPlatform-stg'),p='/private/tmp/checkout-270',ts=require(C+'/backend/wallet-service/node_modules/typescript'),esbuild=require(C+'/backend/wallet-service/node_modules/esbuild');
let s=fs.readFileSync(p+'/writer-base.js','utf8');const changes=[];
function range(name){const marker='// ../wizzuser-stg/backend/src/functions/create-order/quote-runtime/'+name+'.js\n',start=s.indexOf(marker);assert(start>=0,name);const next=s.indexOf('\n// ',start+marker.length);return[start,next<0?s.length:next];}
function edit(name,fn){const[a,b]=range(name),before=s.slice(a,b),after=fn(before);assert.notEqual(before,after,name);s=s.slice(0,a)+after+s.slice(b);changes.push(name);}
const storeFile='checkout-store-agreement-270.js';
esbuild.buildSync({entryPoints:[C+'/backend/wallet-service/dist/storeDeliveryAgreement.js'],bundle:true,platform:'node',target:'node20',outfile:p+'/'+storeFile,logLevel:'warning'});
function parsed(chunk){const ast=ts.createSourceFile('module.js',chunk,ts.ScriptTarget.Latest,true,ts.ScriptKind.JS);const stmt=ast.statements.find(n=>ts.isVariableStatement(n)),method=stmt.declarationList.declarations[0].initializer.arguments[0].properties[0];assert(ts.isMethodDeclaration(method));return{ast,method};}
for(const name of ['deliveryFundingPolicy','deliveryFundingReader','deliveryPromotionSelection','deliveryCampaignBudget','deliveryFundedAllocation'])edit(name,chunk=>{
 const{ast,method}=parsed(chunk),old=method.body.getText(ast),exportsName=method.parameters[0].name.text;
 const imports=Object.fromEntries([...old.matchAll(/(?:var|const) (\w+_\d+) = ([\w$]+\(\));/g)].map(m=>[m[1],m[2]]));
 let body=fs.readFileSync(C+'/backend/wallet-service/dist/'+name+'.js','utf8');
 if(name==='deliveryFundedAllocation'){
  const needle='!(0, deliveryQuoteRecord_1.quoteEntityIdValid)(pin.policyId)';assert(body.includes(needle));
  body=body.replace(needle,'!((0, deliveryQuoteRecord_1.quoteEntityIdValid)(pin.policyId) || (typeof pin.policyId === "string" && pin.policyId.startsWith("PLATFORM_BENEFIT#") && (0, deliveryQuoteRecord_1.quoteEntityIdValid)(pin.policyId.slice("PLATFORM_BENEFIT#".length))))');
 }
 body=body.replace(/\bexports\b/g,exportsName).replace(/((?:var|const) (\w+_\d+) = )require\(["']([^"']+)["']\)/g,(_,prefix,n,request)=>{
  if(request==='./storeDeliveryAgreement')return prefix+'require("../../'+storeFile+'")';
  assert(imports[n],'import '+name+':'+n);return prefix+imports[n];
 }).replace(/require\(['"]\.\.\/\.\.\/staff-service\/catalog['"]\)/g,'require_catalog()').replace(/require\(['"]\.\.\/\.\.\/staff-service\/commercial-party['"]\)/g,'require_commercial_party()');
 assert(!/require\(['"]\.\//.test(body),'unmapped local imports '+name);
 return chunk.slice(0,method.body.getStart(ast)+1)+'\n'+body+'\n'+chunk.slice(method.body.end-1);
});
edit('orderCommercialSource',chunk=>{
 const pairs=[['const terms = record.terms;','let terms = record.terms;'],['        (0, branchMinimumOrder_1.assertMinimumOrder)(branch, goods.goodsGross.minorAmount);\n',''],['if (promotion?.applied) {','if (promotion?.applied) {\n          if(promotion.agreement === true) terms = {...terms,commission:copy(promotion.commission)};'],['const deliveryAmount =','(0, branchMinimumOrder_1.assertMinimumOrder)(promotion?.agreement === true ? {minimum_order:promotion.minimumOrderAmountIqd}:branch,goods.goodsGross.minorAmount);\n        const deliveryAmount ='],['...promotion?.benefitReceipt ?','...(promotion?.agreement === true ? {deliveryAgreement:{...promotion.deliveryFunding.policyPin,kind:promotion.customerRule}} : {}),\n          ...promotion?.benefitReceipt ?']];
 for(const[a,b]of pairs){assert.equal(chunk.split(a).length,2,a);chunk=chunk.replace(a,b);}return chunk;
});
edit('deliveryQuoteOrder',chunk=>{
 const needle='if (benefitFunding ?';assert.equal(chunk.split(needle).length,2);
 chunk=chunk.replace(needle,'if (deliveryFunding.allocation.schemaVersion === 2 ? !storeDeliveryAgreement_270.hasStoreAgreementOrderEvidence(operations, deliveryFunding, orderId, c7.userId) : benefitFunding ?');
 const{ast,method}=parsed(chunk);chunk=chunk.slice(0,method.body.getStart(ast)+1)+'\nvar storeDeliveryAgreement_270=require("../../'+storeFile+'");'+chunk.slice(method.body.getStart(ast)+1);
 const code=fs.readFileSync(C+'/backend/wallet-service/dist/deliveryQuoteOrder.js','utf8'),nextAst=ts.createSourceFile('next.js',code,ts.ScriptTarget.Latest,true,ts.ScriptKind.JS);
 const selected=nextAst.statements.filter(n=>ts.isFunctionDeclaration(n)&&['normalizedCheckTerms','composeQuoteOrderOperations'].includes(n.name?.text));assert.equal(selected.length,2);
 const{ast:oldAst,method:oldMethod}=parsed(chunk);const oldFn=oldMethod.body.statements.find(n=>ts.isFunctionDeclaration(n)&&n.name?.text==='composeQuoteOrderOperations');assert(oldFn);
 const replacement=selected.map(n=>n.getText(nextAst)).join('\n');return chunk.slice(0,oldFn.getStart(oldAst))+replacement+chunk.slice(oldFn.end);
});
function once(a,b){assert.equal(s.split(a).length,2,a);s=s.replace(a,b);}
once('      const deliveryPromotion = selectedDeliveryBenefit ?', '      const pricingReads = body.action === "preview_commercial" ? require("../../checkout-pricing-reads-270.js").createCheckoutPricingReads(dynamoDb) : null;\n      const pricingDb = pricingReads?.db ?? dynamoDb;\n      const pricingStartedAt = Date.now();\n      const deliveryPromotion = selectedDeliveryBenefit ?');
once('db: dynamoDb, lifecycleReadMode: "CONDITION_CHECK",','db: pricingDb, lifecycleReadMode: "CONDITION_CHECK", previewOnly: body.action === "preview_commercial",');
once('createStagingCommercialSource({ db: dynamoDb, deliveryPromotion,','createStagingCommercialSource({ db: pricingDb, deliveryPromotion,');
once('schemaVersion: commercial.deliveryFunding ? 2 : 1,','schemaVersion: commercial.deliveryFunding ? (commercial.deliveryAgreement ? 3 : 2) : 1,\n          ...(commercial.deliveryAgreement ? { deliveryAgreement: commercial.deliveryAgreement } : {}),');
// No customer data, tokens or basket contents in performance diagnostics.
once('if (commercial.calculation.allocationInput.goodsGross.minorAmount !== goodsSubtotal','if (body.action === "preview_commercial") console.info("CHECKOUT_COMMERCIAL_REVIEW", {durationMs:Date.now()-pricingStartedAt,...pricingReads.stats});\n      if (commercial.calculation.allocationInput.goodsGross.minorAmount !== goodsSubtotal');
fs.copyFileSync(U+'/backend/src/functions/create-order/checkout-pricing-reads.js',p+'/checkout-pricing-reads-270.js');
fs.writeFileSync(p+'/writer-candidate.js',s);cp.execFileSync(process.execPath,['--check',p+'/writer-candidate.js']);
fs.writeFileSync(p+'/preparation.json',JSON.stringify({modules:changes,added:[storeFile,'checkout-pricing-reads-270.js'],platformBenefitCompatibilityRetained:s.includes('hasBenefitOrderEvidence')&&s.includes('platformBenefitReceipt')&&s.includes('deliveryCashRounding'),configurationChanged:false,iamChanged:false},null,2));
console.log('Prepared agreement runtime preserving platform benefits and wrappers:',changes.join(', '));
