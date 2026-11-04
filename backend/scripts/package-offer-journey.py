"""Overlay the offer journey on backed-up deployed Lambdas; preserve unrelated live files."""
import zipfile,json,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1];base=Path(sys.argv[1]);source=root/'src'
shared=['discount-contract.js','campaign-version.js','discount-engine.js','discount-reservation.js','discount-preview.js','discount-list.js','offer-eligibility.js','offer-context.js','offer-attribution.js']
def patch_order(s):
 marker='// If an auth token exists, extract the Cognito subject'
 start=s.index('        '+marker);end=s.index('        // Validate items array',start)
 s=s[:start]+"        const offerContext=await require('../shared/offer-context').offerContext(dynamoDb,event,body);\n        const userSub=offerContext.identity?.sub||null;\n"+s[end:]
 s=s.replace('const deliveryFee = Math.round((body.deliveryFee || 10)', 'const deliveryFee = Math.round((body.deliveryFee ?? 10)')
 start=s.index('        // Merchant discount (WhizzMerchants_Discounts) - validated server-side');end=s.index('        // Enforce pricing equation:',start)
 block="""        const {resolveDiscount}=require('../shared/discount-reservation');
        const {catalogItems,orderOperation}=require('../shared/offer-eligibility');
        const accountOrder=await orderOperation(offerContext.customer);
        const discountOperations=[...(offerContext.guarded.condition?[offerContext.guarded.condition]:[]),...(accountOrder?[accountOrder]:[]),...(offerContext.addressCondition?[offerContext.addressCondition]:[])];
        let discountItems=[];
        if(body.discountId||body.promoCode||body.platformDiscountId){
            if(processedItems.some(i=>i.modifiers.length)||body.items.some(i=>i.customizations?.length))throw Object.assign(Error('UNSUPPORTED_DISCOUNT_ITEMS'),{statusCode:409});
            const catalog=await require('./quote-runtime/orderGoodsPricing').createStagingOrderGoodsPricing({db:dynamoDb}).price({branchId:body.storeId,items:processedItems.map(i=>({productId:i.itemId,quantity:i.quantity}))});
            if(catalog.goodsGross.minorAmount!==goodsSubtotal||catalog.lines.some(l=>processedItems.find(i=>i.itemId===l.productId)?.unitPrice!==l.unitPrice.minorAmount))throw Object.assign(Error('CART_PRICE_CHANGED'),{statusCode:409});
            discountItems=catalogItems(catalog);discountOperations.push(...catalog.conditions);
        }
        const resolved=await resolveDiscount({db:dynamoDb,branchId:body.storeId,discountId:body.discountId,promoCode:body.promoCode,platformDiscountId:body.platformDiscountId,subtotal:goodsSubtotal,items:discountItems,deliveryFee,...offerContext});
        const discountFils=resolved.amount;
        if(resolved.snapshot&&(typeof body.discount!=='number'||!Number.isFinite(body.discount)||Math.round(body.discount*1000)!==discountFils))throw Object.assign(Error('DISCOUNT_PREVIEW_CHANGED'),{statusCode:409});
        discountOperations.push(...resolved.operations,...await require('../shared/offer-attribution').attribution(dynamoDb,body.offerSlideId,resolved.snapshot));
        if(discountOperations.length>95)throw Object.assign(Error('CART_TOO_LARGE_FOR_OFFER'),{statusCode:409});
        const appliedDiscount=resolved.snapshot?.source==='MERCHANT'?resolved.campaign:null;
        const appliedPromo=resolved.snapshot?.source==='PLATFORM'?resolved.campaign:null;

"""
 s=s[:start]+block+s[end:]
 s=s.replace("promoCode: body.promoCode || null,", "promoCode: appliedPromo?.code || null,\n            offerSnapshot:resolved.snapshot,\n            offerSlideId:body.offerSlideId||null,")
 s=s.replace("            await dynamoDb.send(new TransactWriteCommand({TransactItems: [", "            if(resolved.expiresAt&&Date.now()>=resolved.expiresAt)throw Object.assign(Error('DISCOUNT_EXPIRED'),{statusCode:409});\n            await dynamoDb.send(new TransactWriteCommand({TransactItems: [\n                ...discountOperations,")
 start=s.index('        // Increment the merchant discount usage counter');end=s.index('        // Send order to merchant backend webhook',start);s=s[:start]+s[end:]
 s=s.replace("error:'BUSINESS_UNAVAILABLE'", "error:'ORDER_OR_OFFER_CHANGED'")
 s=s.replace('            statusCode: 500,\n            headers:', '            statusCode: error.statusCode||500,\n            headers:')
 return s
for name,handler in [('CreateOrder',None),('ValidatePromoCode','validate-promo-code'),('ApplyPromoCode','apply-promo-code'),('GetStoreDiscounts','get-store-discounts')]:
 filename='WizzUser-'+name+'-staging';overlays={}
 for f in shared:overlays['functions/shared/'+f]=(source/'functions/shared'/f).read_bytes()
 overlays['functions/create-order/account-guard.js']=(source/'functions/create-order/account-guard.js').read_bytes()
 for f in (source/'functions/create-order/quote-runtime').rglob('*.js'):overlays['functions/create-order/quote-runtime/'+str(f.relative_to(source/'functions/create-order/quote-runtime'))]=f.read_bytes()
 with zipfile.ZipFile(base/(filename+'.zip')) as src:
  if name=='CreateOrder':overlays['functions/create-order/index.js']=patch_order(src.read('functions/create-order/index.js').decode()).encode()
  elif name=='GetStoreDiscounts':overlays['functions/'+handler+'/index.js']=b"exports.handler=require('../shared/discount-list').list(false);\n"
  else:overlays['functions/'+handler+'/index.js']=("exports.handler=require('../shared/discount-preview').preview("+('true' if name=='ValidatePromoCode' else 'false')+");\n").encode()
  # Assert the real deployed handler path matches our wrapper before packaging.
  config=json.loads((base/(filename+'.json')).read_text())['Configuration']
  expected='functions/'+('create-order' if name=='CreateOrder' else handler)+'/index.handler'
  assert config['Handler']==expected,(config['Handler'],expected)
  with zipfile.ZipFile(base/(filename+'-update.zip'),'w',zipfile.ZIP_DEFLATED) as dst:
   for item in src.infolist():
    # Both commands and clients must resolve to the same runtime SDK. The legacy
    # nested SDK shadows only catalog/order modules and is incompatible with shared modules.
    if item.filename.startswith(('functions/create-order/node_modules/@aws-sdk/client-dynamodb/','functions/create-order/node_modules/@aws-sdk/lib-dynamodb/')):continue
    if item.filename not in overlays:dst.writestr(item,src.read(item.filename))
   for path,data in overlays.items():dst.writestr(path,data)
  if name=='CreateOrder':(base/'patched-live-order.js').write_bytes(overlays['functions/create-order/index.js'])
 print('Packaged',filename)
