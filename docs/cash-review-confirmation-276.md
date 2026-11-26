# 276 — cash payment report confirmation in customer and driver apps

Read-only verification of test order ORD1792642212555 / 878cc8ee-17e6-56eb-884c-142ae0f00635 found cash case version 6: original driver/customer reports IQD8250 and newer driver/customer reports IQD9000. Reports are staging simulations (user confirmed no physical cash). Case remains REVIEW_REQUIRED and order arrived_at_customer with openPaymentClaimId; no final financial outcome. Latest IQD9000 reports still require administrative re-verification; prior verification was IQD8250. No report, verification, payment or order status was submitted by the agent.

Both native screens now show a six-second SnackBar after a successful server response and dismiss the keyboard. A persistent card displays the account's latest saved report from the server, including after refresh/reopening. Refund acknowledgments retain distinct wording. Retry/idempotency and original-auth transport unchanged. Five tests pass per app, including success confirmation, account-specific latest report and refresh persistence; both screen analyzers report no issues.

Customer build 221 installed on iPhone16Pro simulator; driver profile build 220 installed and launched on real iPhone. Simulator restart needed after transient host disk space/SpringBoard failure. Old temporary task archives were preserved on external ignored build/retained-task-artifacts with original /private/tmp symlinks. No data erased, no server code deployed, no merchant app changes.

Next human action: administrator reloads cash review and explicitly matches the latest IQD9000 driver/customer reports, then resolves full collection review, then driver completes delivery as a staging simulation. Do not infer admin verification from the matched amount reports alone.
