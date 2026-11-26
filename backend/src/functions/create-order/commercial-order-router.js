'use strict';
// Transitional release adapter: the downloaded legacy handler keeps its original implementation.
// Only coordinated REQUIRED modes load the canonical commercial order handler.
const { customerOrderView } = require('../shared/customer-order-view');
function publicOrderResponse(response) {
    if (!response || typeof response.body !== 'string' || response.isBase64Encoded) return response;
    let body;
    try { body = JSON.parse(response.body); } catch { return response; }
    if (!body || typeof body !== 'object' || Array.isArray(body)) return response;
    let changed = false;
    if (body.order && typeof body.order === 'object') { body.order = customerOrderView(body.order); changed = true; }
    if (Array.isArray(body.orders)) { body.orders = body.orders.map(customerOrderView); changed = true; }
    return changed ? { ...response, body: JSON.stringify(body) } : response;
}
function createCommercialOrderRouter({ legacy, loadCommercial, env = process.env }) {
    const reject = (statusCode, code) => ({ statusCode, headers: { 'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store' }, body: JSON.stringify({ success: false, code }) });
    return async (event, context) => {
        // Preflight is transport only, and must not load a financial handler.
        if (event.httpMethod === 'OPTIONS') return legacy(event, context);
        const quoteMode = env.DELIVERY_QUOTE_MODE || 'OFF';
        const commercialMode = env.COMMERCIAL_PRICING_MODE || 'OFF';
        if (!['OFF', 'REQUIRED'].includes(quoteMode) || !['OFF', 'REQUIRED'].includes(commercialMode) || quoteMode !== commercialMode)
            return reject(503, 'COMMERCIAL_NOT_CONFIGURED');
        if (commercialMode === 'REQUIRED') {
            const result=await loadCommercial()(event,context);
            let response,request;
            try{response=JSON.parse(result.body);request=typeof event.body==='string'?JSON.parse(event.body):event.body;}catch{}
            const experimental=event.resource==='/orders/commercial-preview'||request&&['quoteId','commercialConsent','action'].some(k=>Object.prototype.hasOwnProperty.call(request,k));
            if(response?.code==='FINANCE_ROLLOUT_OUT_OF_SCOPE'&&!experimental)return publicOrderResponse(await legacy(event,context));
            return publicOrderResponse(result);
        }
        let body;
        try { body = typeof event.body === 'string' && !event.isBase64Encoded ? JSON.parse(event.body) : event.body; } catch { /* Legacy handler owns malformed-body validation. */ }
        if (event.resource === '/orders/commercial-preview' || body && typeof body === 'object' &&
            ['quoteId', 'commercialConsent', 'action'].some(key => Object.prototype.hasOwnProperty.call(body, key)))
            return reject(409, 'COMMERCIAL_NOT_ENABLED');
        return publicOrderResponse(await legacy(event, context));
    };
}
module.exports = { createCommercialOrderRouter, publicOrderResponse };
