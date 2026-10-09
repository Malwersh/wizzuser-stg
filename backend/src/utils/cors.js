"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.handleOptionsRequest = exports.handleCorsResponse = exports.corsHeaders = void 0;
// src/utils/cors.ts
exports.corsHeaders = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Requested-With',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
    'Access-Control-Max-Age': '86400', // 24 hours cache for preflight
};
var handleCorsResponse = function (statusCode, body) {
    return {
        statusCode: statusCode,
        headers: exports.corsHeaders,
        body: typeof body === 'string' ? body : JSON.stringify(body),
    };
};
exports.handleCorsResponse = handleCorsResponse;
var handleOptionsRequest = function () {
    return (0, exports.handleCorsResponse)(200, '');
};
exports.handleOptionsRequest = handleOptionsRequest;
