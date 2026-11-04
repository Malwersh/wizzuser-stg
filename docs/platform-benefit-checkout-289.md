# Customer benefit selection — 289

Adds a platform-benefit card immediately above the existing checkout discounts section, preserving the current checkout, home, cart and confirmation designs. Only the benefit DTO and authenticated list client were selectively reused from origin/integration/discounts-settlements-20261022; no wholesale native/UI merge was performed.

The new checkout sheet lists the account's benefits for the branch/address with amount, minimum goods and remaining uses. Selection validates the exact basket and address through the existing authenticated preview endpoint. Successful selection replaces the prior merchant discount or code; a failed switch preserves the current benefit. This UI supports one selected benefit at a time. It does not introduce stacking of a benefit with another coupon. A selected delivery benefit's exact savings appear in the authoritative final review, rather than applying a potentially different road-reference preview saving to the agreed price locally.

Goods benefit IDs are carried as platformDiscountId and delivery benefit IDs as deliveryBenefitId through createOrder, preview, consent and final confirmation. The existing agreement-first financial runtime remains authoritative. Basket/address/account/quote changes invalidate the prior validation. Tip changes preserve benefit eligibility but require fresh final consent. A pending confirmation blocks changing benefits. Explicit pre-commit benefit rejections release the uncommitted retry; unknown or infrastructure failures preserve it for reconciliation.

No campaign, grant, order, payment, wallet or delivery policy was created/modified by this work. The user's existing 500-IQD grant remains the test fixture. Opening the sheet and previewing a benefit do not reserve or consume it.

Verification:
- 32 commercial/benefit/discount/amount/review/widget tests pass (one unrelated scoped-build test skipped outside its explicit build).
- 22 historical delivery-confirmation tests pass with COMMERCIAL_PRICING_ENABLED=false, their intended configuration. Running these legacy fixtures under commercial checkout incorrectly requires a review callback they do not supply; separate suite settings preserve both modes.
- The agreement example is covered explicitly: goods 7000, goods discount 500, service 500, agreed delivery 1500, final consent 8500 against road quote 2000.
- Static analysis found no errors/warnings in the new integration; existing style/deprecation/print infos remain. Build 222 targets the customer simulator. Human selection and final review remain to be checked after installation; do not submit an order automatically.

Artifacts: /private/tmp/benefit-checkout-289/{tests-commercial.log,tests-legacy.log,build.log}.
