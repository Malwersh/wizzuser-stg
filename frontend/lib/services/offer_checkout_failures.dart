/// These codes are emitted before the order transaction commits. Unknown or
/// infrastructure failures must retain the pending attempt for reconciliation.
const rejectedOfferCodes = <String>{
  'BENEFIT_EXHAUSTED',
  'BENEFIT_EXPIRED',
  'BENEFIT_PAUSED',
  'BENEFIT_NOT_ELIGIBLE',
  'BENEFIT_WRONG_BRANCH',
  'BENEFIT_WRONG_REGION',
  'BENEFIT_MINIMUM_ORDER',
  'BENEFIT_DELIVERY_CAP_EXCEEDED',
  'BENEFIT_DISTANCE_EXCEEDED',
  'BENEFIT_NO_SAVINGS',
  'BENEFIT_STACKING_DENIED',
  'BENEFIT_LOGIN_REQUIRED',

  'DISCOUNT_UNAVAILABLE',
  'DISCOUNT_PREVIEW_CHANGED',
  'OFFER_NO_SAVINGS',
  'OFFER_ALREADY_USED',
  'OFFER_FIRST_ORDER_ONLY',
  'OFFER_LOGIN_REQUIRED',
  'OFFER_NOT_ELIGIBLE',
  'OFFER_WRONG_MERCHANT',
  'OFFER_WRONG_REGION',
  'OFFER_DELIVERY_POLICY_REQUIRED',
  'OFFER_CUSTOMER_LIMIT_UNSUPPORTED',
  'OFFER_AUDIENCE_UNSUPPORTED',
};

bool isDefinitiveOfferRejection(dynamic code, int statusCode) =>
    statusCode >= 400 && statusCode < 500 && rejectedOfferCodes.contains(code);
