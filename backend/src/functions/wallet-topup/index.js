'use strict';
// The historical PayTabs implementation cannot safely accept payments: the
// integration has not been enabled and its callbacks were not authenticated.
// Restore only with provider verification, durable pending-payment tracking,
// and lifecycle-guarded, idempotent settlement.
exports.handler=async event=>({
 statusCode:event.httpMethod==='OPTIONS'?204:503,
 headers:{'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'Content-Type,Authorization'},
 body:event.httpMethod==='OPTIONS'?'':JSON.stringify({success:false,code:'PAYMENT_GATEWAY_NOT_ENABLED',message:'الشحن عبر بوابة البطاقة غير مفعّل حاليًا. لم يتغيّر رصيدك.'})
});
