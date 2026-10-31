# Checkout presentation 294

Restaurant discounts now open a searchable, lazily built sheet instead of adding one radio row per campaign to checkout. The summary shows campaign count and selected campaign. Selection still calls the existing server validation; closing the sheet does not change selection. Minimum goods amount is shown on each offer. No campaigns, orders, funding policies or accounting were changed.

Checkout cards use consistent rounded corners, subdued blue shadows and a cool neutral background. Icons and benefit action text use brand blue for contrast; yellow is reserved for fills and emphasis with dark text. Original brand constants are unchanged.

Verification: two widget tests with 15 campaigns at 320 and 390 logical pixels cover search, selection and layout errors. Targeted analyzer reports info-level existing checkout lints only, no warnings/errors. Customer simulator build 233.
