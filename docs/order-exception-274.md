# Part 274 — missing order exception policy in deployed create-order bundle

Human driver cash-review test for ORD1792640866303 / 8eefde64-8493-550a-861d-2e95a442343b failed to load. Read-only server inspection found status arrived_at_customer, financial snapshot schema 3, accepted customerTotal IQD 9000, but no exceptionPolicy. customerCashCase.context correctly rejects that order. The local create-order source already pins the policy, but the deployed bundled writer from part 270 omitted the pin.

Bounded repair inserts the existing canonical createOrderExceptionPolicy(order.createdAt) call only for FULL_CASH_AT_DELIVERY_V1 orders at initial creation and packages its bundled dependency. All unrelated deployed ZIP entries and writer code are preserved. No current/historical order is backfilled; no cash acknowledgment, refund, settlement or order creation was performed by the agent.

Validation: 3 candidate bundle policy/unchanged-code tests and 45 exception-policy, cash-case, refund and order-handler regressions passed. Deployed-byte/configuration verification is recorded in order-exception-publication-274.json. New-order human testing remains pending; this is not a successful end-to-end cash collection test.

The existing active human-test order needs truthful completion/return handling before another assignment; do not fabricate full collection to clear it. Driver build 219 remains the independent profile build with the visible collection-problem button.
