// src/utils/cors.ts
export const corsHeaders = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Requested-With',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
  'Access-Control-Max-Age': '86400', // 24 hours cache for preflight
};

export const handleCorsResponse = (statusCode: number, body: any) => {
  return {
    statusCode,
    headers: corsHeaders,
    body: typeof body === 'string' ? body : JSON.stringify(body),
  };
};

export const handleOptionsRequest = () => {
  return handleCorsResponse(200, '');
};
