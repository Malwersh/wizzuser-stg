'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { allocateDeliveryFundedOrder } = require('../src/functions/create-order/quote-runtime/deliveryFundedAllocation');
const { fromWholeIqd: money } = require('../src/functions/create-order/quote-runtime/money');

function order(policyId) {
  return {
    allocationSchemaVersion: 2,
    base: {
      allocationSchemaVersion: 1,
      paymentMethod: 'COD',
      goodsGross: money(10000),
      merchantGoodsDiscount: money(500),
      platformGoodsDiscount: money(0),
      merchantCommission: money(700),
      serviceFee: money(500),
      customerDeliveryFee: money(1500),
      driverEarning: money(4000),
      driverTip: money(500),
      merchantOtherCharges: money(0),
      platformOtherCharges: money(0),
      thirdPartyOtherCharges: money(0),
    },
    deliveryFunding: {
      policyPin: { policyId, version: 1, termsHash: 'a'.repeat(64) },
      allocation: {
        schemaVersion: 1,
        referenceFee: money(4000),
        customerFee: money(1500),
        subsidy: money(2500),
        merchantShare: money(0),
        platformShare: money(2500),
      },
    },
  };
}

test('ordinary and platform-benefit funding preserve the recorded cash, discount and tip allocation', () => {
  const amounts = {
    customerGoodsPayment: 9500, customerTotal: 12000, merchantGoodsEntitlement: 9500,
    merchantPayable: 8800, merchantCommission: 700, thirdPartyPayable: 0,
    driverEarningEntitlement: 4000, driverTipEntitlement: 500, driverTotalEntitlement: 4500,
    deliveryMargin: -2500, deliverySurplus: 0, deliverySubsidy: 2500,
    platformGoodsDiscountFunding: 0, platformSubsidy: 2500, platformNetContribution: -1300,
    driverWalletHold: 10000, driverCashRetained: 2000, driverCashEarningRetained: 1500,
    driverCashTipRetained: 500, driverWalletEarningCredit: 2500, driverWalletTipCredit: 0,
    driverWalletCreditTotal: 2500, platformCollection: 10000, platformFundsAfterDriverCredit: 7500,
    merchantPayableBeforeDeliverySupport: 8800, merchantDeliverySupport: 0,
    platformDeliveryPromotionFunding: 2500, platformPromotionCashReservation: 2500,
    referenceDeliveryFee: 4000, customerDeliveryFee: 1500, deliveryPromotionSubsidy: 2500,
    baselineDeliveryMargin: 0, platformBaselineDeliverySubsidy: 0,
    deliveryNetContribution: -2500, grossDeliveryShortfall: 2500,
  };
  for (const policyId of ['normal-policy', 'PLATFORM_BENEFIT#benefit-1']) {
    const input = order(policyId);
    const expected = Object.fromEntries(Object.entries(amounts).map(([field, value]) => [field, money(value)]));
    assert.deepEqual(allocateDeliveryFundedOrder(input), {
      ...expected,
      ruleVersion: 'ORDER_ALLOCATION_V2_DELIVERY_FUNDING',
      basis: 'SUCCESSFUL_DELIVERY_PROPOSAL',
      paymentMethod: 'COD',
      deliveryFundingPin: input.deliveryFunding.policyPin,
    });
  }
});

test('platform compatibility does not admit unsupported policy identities', () => {
  for (const policyId of ['FOREIGN#policy', 'PLATFORM_BENEFIT#', 'PLATFORM_BENEFIT#FOREIGN#policy']) {
    assert.throws(() => allocateDeliveryFundedOrder(order(policyId)), { code: 'INVALID_DELIVERY_FUNDED_ALLOCATION' });
  }
});
