| Method | Path | Auth | Permission |
|---|---|---|---|
| GET | `/dev/pay/:token` | none |  |
| POST | `/dev/pay/:token/complete` | none |  |
| GET | `/health` | none |  |
| GET | `/healthcheck` | none |  |
| GET | `/pay/return/:token` | none |  |
| GET | `/ready` | none |  |
| POST | `/v3/auth/logout` | user |  |
| GET | `/v3/biohub/devices` | gym | devices.read |
| POST | `/v3/biohub/devices` | gym | devices.write |
| DELETE | `/v3/biohub/devices/:id` | gym | devices.write |
| GET | `/v3/biohub/devices/:id` | gym | devices.read |
| PATCH | `/v3/biohub/devices/:id` | gym | devices.write |
| POST | `/v3/biohub/devices/:id/rotate-key` | gym | devices.write |
| POST | `/v3/users/self/email/verification` | user |  |
| POST | `/v3/users/self/otp` | user |  |
| POST | `/v3/users/self/otp/verify` | user |  |
| GET | `/v4/gyms/:id` | gym | settings.read |
| GET | `/v5/apps/configs/settings` | none |  |
| GET | `/v5/attendance` | gym | attendance.read |
| DELETE | `/v5/attendance/:id` | gym | attendance.write |
| POST | `/v5/attendance/:id/checkout` | gym | attendance.write |
| GET | `/v5/attendance/export` | gym | attendance.read |
| POST | `/v5/attendance/guest` | gym | attendance.write |
| POST | `/v5/attendance/mark` | gym | attendance.write |
| POST | `/v5/attendance/mark-by-qr` | gym | attendance.write |
| GET | `/v5/attendance/summary` | gym | attendance.read |
| POST | `/v5/auth/login/otp` | none |  |
| POST | `/v5/auth/login/otp/verify` | none |  |
| POST | `/v5/auth/refresh` | none |  |
| POST | `/v5/auth/signin/choose` | none |  |
| POST | `/v5/auth/signin/otp` | none |  |
| POST | `/v5/auth/signin/verify` | none |  |
| GET | `/v5/balance-reminder` | gym | finance.read |
| POST | `/v5/balance-reminder` | gym | finance.write |
| DELETE | `/v5/balance-reminder/:id` | gym | finance.write |
| PATCH | `/v5/balance-reminder/:id` | gym | finance.write |
| POST | `/v5/balance-reminder/:id/done` | gym | finance.write |
| GET | `/v5/balance-reminder/member/:memberId` | gym | finance.read |
| GET | `/v5/billings/invoices/:orderId` | gym | settings.read |
| GET | `/v5/billings/subscriptions` | gym | settings.read |
| GET | `/v5/billings/subscriptions/history` | gym | settings.read |
| GET | `/v5/billings/subscriptions/usage` | gym | settings.read |
| POST | `/v5/biohub/device/events` | none |  |
| POST | `/v5/biohub/device/heartbeat` | none |  |
| GET | `/v5/biohub/device/members` | none |  |
| POST | `/v5/biohub/force-sync` | gym | devices.write |
| GET | `/v5/biohub/logs` | gym | devices.read |
| GET | `/v5/biohub/logs/calendar` | gym | devices.read |
| GET | `/v5/biohub/logs/export` | gym | devices.read |
| POST | `/v5/biohub/member/:id/block` | gym | devices.write |
| POST | `/v5/biohub/member/:id/enroll` | gym | devices.write |
| GET | `/v5/biohub/member/:id/enrollments` | gym | devices.read |
| POST | `/v5/biohub/member/:id/unblock` | gym | devices.write |
| POST | `/v5/biohub/members/sync` | gym | devices.write |
| POST | `/v5/biohub/reset` | gym | devices.write |
| GET | `/v5/broadcasts` | gym | broadcasts.read |
| POST | `/v5/broadcasts` | gym | broadcasts.write |
| GET | `/v5/broadcasts/:id` | gym | broadcasts.read |
| PATCH | `/v5/broadcasts/:id` | gym | broadcasts.write |
| POST | `/v5/broadcasts/:id/cancel` | gym | broadcasts.write |
| POST | `/v5/broadcasts/recipients/preview` | gym | broadcasts.read |
| GET | `/v5/broadcasts/templates` | gym | broadcasts.read |
| POST | `/v5/broadcasts/templates` | gym | broadcasts.write |
| DELETE | `/v5/broadcasts/templates/:id` | gym | broadcasts.write |
| PATCH | `/v5/broadcasts/templates/:id` | gym | broadcasts.write |
| GET | `/v5/credit-packs` | gym | broadcasts.read |
| GET | `/v5/credits/stats` | gym | broadcasts.read |
| GET | `/v5/credits/transactions` | gym | broadcasts.read |
| GET | `/v5/credits/transactions/export` | gym | broadcasts.read |
| GET | `/v5/dashboards/gyms/insights` | gym | reports.read |
| GET | `/v5/dashboards/gyms/occupancy` | gym | attendance.read |
| GET | `/v5/dashboards/gyms/reports/schedule` | gym | reports.read |
| PUT | `/v5/dashboards/gyms/reports/schedule` | gym | settings.write |
| GET | `/v5/dashboards/gyms/reports/transactions` | gym | reports.read |
| GET | `/v5/dashboards/gyms/summary` | gym | members.read |
| POST | `/v5/diet/generate` | gym | plansets.write |
| DELETE | `/v5/diet/members/:memberId` | gym | plansets.write |
| GET | `/v5/diet/members/:memberId` | gym | plansets.read |
| PUT | `/v5/diet/members/:memberId` | gym | plansets.write |
| GET | `/v5/diet/plans` | gym | plansets.read |
| POST | `/v5/diet/plans` | gym | plansets.write |
| DELETE | `/v5/diet/plans/:id` | gym | plansets.write |
| GET | `/v5/diet/plans/:id` | gym | plansets.read |
| PUT | `/v5/diet/plans/:id` | gym | plansets.write |
| POST | `/v5/diet/plans/:id/assign` | gym | plansets.write |
| GET | `/v5/exercises` | gym | plansets.read |
| POST | `/v5/exercises` | gym | plansets.write |
| DELETE | `/v5/exercises/:id` | gym | plansets.write |
| PATCH | `/v5/exercises/:id` | gym | plansets.write |
| GET | `/v5/exercises/categories` | gym | plansets.read |
| GET | `/v5/exercises/meta` | gym | plansets.read |
| GET | `/v5/expenses` | gym | expenses.read |
| POST | `/v5/expenses` | gym | expenses.write |
| DELETE | `/v5/expenses/:id` | gym | expenses.write |
| GET | `/v5/expenses/:id` | gym | expenses.read |
| PATCH | `/v5/expenses/:id` | gym | expenses.write |
| GET | `/v5/expenses/categories` | gym | expenses.read |
| GET | `/v5/feedbacks` | gym | feedback.read |
| GET | `/v5/feedbacks/:id` | gym | feedback.read |
| POST | `/v5/feedbacks/:id/favorite` | gym | feedback.read |
| POST | `/v5/feedbacks/:id/seen` | gym | feedback.read |
| GET | `/v5/feedbacks/latest-unseen` | gym | feedback.read |
| GET | `/v5/feedbacks/stats` | gym | feedback.read |
| POST | `/v5/files` | gym | (any gym member) |
| GET | `/v5/files/:id` | user |  |
| GET | `/v5/gyms` | user |  |
| POST | `/v5/gyms` | user |  |
| GET | `/v5/gyms/:id` | gym | settings.read |
| PATCH | `/v5/gyms/:id` | gym | settings.write |
| GET | `/v5/gyms/current` | gym | (any gym member) |
| GET | `/v5/gyms/features` | gym | settings.read |
| PUT | `/v5/gyms/features/:key` | gym | settings.write |
| GET | `/v5/gyms/payment-methods` | gym | finance.read |
| PUT | `/v5/gyms/payment-methods` | gym | settings.write |
| DELETE | `/v5/gyms/payment-setup` | gym | settings.write |
| GET | `/v5/gyms/payment-setup` | gym | settings.read |
| PUT | `/v5/gyms/payment-setup` | gym | settings.write |
| POST | `/v5/gyms/payment-setup/skip` | gym | settings.write |
| GET | `/v5/gyms/portal/qr` | gym | settings.read |
| POST | `/v5/gyms/portal/qr/regenerate` | gym | settings.write |
| GET | `/v5/gyms/preferences` | gym | settings.read |
| PATCH | `/v5/gyms/preferences` | gym | settings.write |
| GET | `/v5/gyms/staffs` | gym | staff.read |
| POST | `/v5/gyms/staffs` | gym | staff.write |
| DELETE | `/v5/gyms/staffs/:userId` | gym | staff.write |
| PATCH | `/v5/gyms/staffs/:userId` | gym | staff.write |
| POST | `/v5/gyms/staffs/:userId/resend-invite` | gym | staff.write |
| GET | `/v5/gyms/tags` | gym | members.read |
| POST | `/v5/gyms/tags` | gym | members.write |
| DELETE | `/v5/gyms/tags/:id` | gym | members.write |
| PATCH | `/v5/gyms/tags/:id` | gym | members.write |
| GET | `/v5/gyms/tax` | gym | settings.read |
| POST | `/v5/gyms/tax` | gym | settings.write |
| DELETE | `/v5/gyms/tax/:id` | gym | settings.write |
| PATCH | `/v5/gyms/tax/:id` | gym | settings.write |
| GET | `/v5/integrations` | gym | settings.read |
| POST | `/v5/integrations/whatsapp/disable` | gym | settings.write |
| POST | `/v5/integrations/whatsapp/enable` | gym | settings.write |
| GET | `/v5/invoices/:invoiceNo` | gym | finance.read |
| GET | `/v5/masters/countries` | none |  |
| GET | `/v5/masters/country/phone-code` | none |  |
| GET | `/v5/masters/health-conditions` | none |  |
| GET | `/v5/masters/languages` | none |  |
| GET | `/v5/masters/timezones` | none |  |
| GET | `/v5/me/feature-announcements` | user |  |
| POST | `/v5/me/feature-announcements/:id/seen` | user |  |
| POST | `/v5/member/auth/code` | none |  |
| POST | `/v5/member/auth/logout` | member |  |
| POST | `/v5/member/auth/logout-all` | member |  |
| POST | `/v5/member/auth/otp` | none |  |
| POST | `/v5/member/auth/otp/verify` | none |  |
| POST | `/v5/member/auth/refresh` | none |  |
| POST | `/v5/member/auth/select-gym` | none |  |
| DELETE | `/v5/member/data` | member |  |
| GET | `/v5/member/data` | member |  |
| PUT | `/v5/member/data` | member |  |
| GET | `/v5/member/me` | member |  |
| DELETE | `/v5/member/me/account` | member |  |
| GET | `/v5/member/me/account` | member |  |
| PATCH | `/v5/member/me/account` | member |  |
| POST | `/v5/member/me/account/delete-otp` | member |  |
| GET | `/v5/member/me/attendance` | member |  |
| GET | `/v5/member/me/notifications` | member |  |
| PUT | `/v5/member/me/notifications` | member |  |
| POST | `/v5/member/me/payment-link` | member |  |
| GET | `/v5/member/me/payment-options` | member |  |
| POST | `/v5/member/me/phone/otp` | member |  |
| POST | `/v5/member/me/phone/verify` | member |  |
| DELETE | `/v5/member/me/photo` | member |  |
| GET | `/v5/member/me/photo` | member |  |
| PUT | `/v5/member/me/photo` | member |  |
| GET | `/v5/member/me/plans` | member |  |
| GET | `/v5/member/me/preferences` | member |  |
| PUT | `/v5/member/me/preferences` | member |  |
| GET | `/v5/member/me/privacy` | member |  |
| PUT | `/v5/member/me/privacy` | member |  |
| GET | `/v5/member/me/profile` | member |  |
| GET | `/v5/member/me/requests` | member |  |
| POST | `/v5/member/me/requests` | member |  |
| DELETE | `/v5/member/me/requests/:id` | member |  |
| GET | `/v5/member/me/sessions` | member |  |
| DELETE | `/v5/member/me/sessions/:id` | member |  |
| POST | `/v5/member/me/sessions/revoke-others` | member |  |
| POST | `/v5/member/opengym/launch` | member |  |
| GET | `/v5/members` | gym | members.read |
| POST | `/v5/members` | gym | members.write |
| DELETE | `/v5/members/:id` | gym | settings.write |
| GET | `/v5/members/:id` | gym | members.read |
| PATCH | `/v5/members/:id` | gym | members.write |
| DELETE | `/v5/members/:id/access-code` | gym | members.write |
| POST | `/v5/members/:id/access-code` | gym | members.write |
| POST | `/v5/members/:id/app-invite` | gym | members.write |
| POST | `/v5/members/:id/block` | gym | members.write |
| POST | `/v5/members/:id/conditions` | gym | members.write |
| DELETE | `/v5/members/:id/conditions/:cid` | gym | members.write |
| PATCH | `/v5/members/:id/conditions/:cid` | gym | members.write |
| GET | `/v5/members/:id/documents` | gym | members.read |
| POST | `/v5/members/:id/documents` | gym | members.write |
| DELETE | `/v5/members/:id/documents/:docId` | gym | members.write |
| GET | `/v5/members/:id/health` | gym | members.read |
| POST | `/v5/members/:id/health` | gym | members.write |
| PUT | `/v5/members/:id/labels` | gym | members.write |
| POST | `/v5/members/:id/member-app/reopen` | gym | members.write |
| POST | `/v5/members/:id/parq/sign` | gym | members.write | plansets.write |
| POST | `/v5/members/:id/payment-link` | gym | finance.write |
| PUT | `/v5/members/:id/trainer` | gym | members.write |
| GET | `/v5/members/:id/training` | gym | members.read |
| POST | `/v5/members/:id/unblock` | gym | members.write |
| GET | `/v5/members/export` | gym | members.read |
| GET | `/v5/members/insights/at-risk` | gym | members.read |
| GET | `/v5/members/transactions` | gym | finance.read |
| DELETE | `/v5/members/transactions/:id` | gym | finance.write |
| GET | `/v5/members/transactions/:id` | gym | finance.read |
| GET | `/v5/members/transactions/balance` | gym | finance.read |
| GET | `/v5/members/transactions/export` | gym | finance.read |
| POST | `/v5/members/transactions/settle` | gym | finance.write |
| POST | `/v5/members/transactions/write-off` | gym | finance.write |
| GET | `/v5/membership-requests` | gym | requests.read |
| GET | `/v5/membership-requests/:id` | gym | requests.read |
| POST | `/v5/membership-requests/:id/decision` | gym | requests.write |
| GET | `/v5/memberships` | gym | members.read |
| POST | `/v5/memberships` | gym | members.write |
| GET | `/v5/memberships/:id` | gym | members.read |
| POST | `/v5/memberships/:id/end` | gym | members.write |
| POST | `/v5/memberships/:id/extend` | gym | members.write |
| POST | `/v5/memberships/:id/freeze` | gym | members.write |
| POST | `/v5/memberships/:id/resume` | gym | members.write |
| POST | `/v5/memberships/:id/sessions` | gym | members.write | trainer.self |
| DELETE | `/v5/memberships/:id/sessions/:logId` | gym | members.write |
| POST | `/v5/memberships/:id/start` | gym | members.write |
| POST | `/v5/memberships/:id/upgrade` | gym | members.write |
| GET | `/v5/memberships/plan-groups` | gym | plans.read |
| POST | `/v5/memberships/plan-groups` | gym | plans.write |
| DELETE | `/v5/memberships/plan-groups/:id` | gym | plans.write |
| PATCH | `/v5/memberships/plan-groups/:id` | gym | plans.write |
| POST | `/v5/memberships/plan-groups/:id/move-plans` | gym | plans.write |
| GET | `/v5/memberships/plans` | gym | plans.read |
| POST | `/v5/memberships/plans` | gym | plans.write |
| DELETE | `/v5/memberships/plans/:id` | gym | plans.write |
| GET | `/v5/memberships/plans/:id` | gym | plans.read |
| PATCH | `/v5/memberships/plans/:id` | gym | plans.write |
| POST | `/v5/memberships/plans/:id/disable` | gym | plans.write |
| POST | `/v5/memberships/plans/:id/duplicate` | gym | plans.write |
| POST | `/v5/memberships/plans/:id/enable` | gym | plans.write |
| GET | `/v5/memberships/plans/keys` | gym | plans.read |
| POST | `/v5/memberships/quote` | gym | members.read |
| GET | `/v5/message-templates/entity/:entity` | gym | broadcasts.read |
| GET | `/v5/message-templates/notifications` | gym | broadcasts.read |
| PATCH | `/v5/message-templates/notifications/:key` | gym | broadcasts.write |
| POST | `/v5/message-templates/notifications/:key/reset` | gym | broadcasts.write |
| POST | `/v5/message-templates/preview` | gym | broadcasts.read |
| GET | `/v5/messages` | gym | broadcasts.read |
| GET | `/v5/messages/export` | gym | broadcasts.read |
| POST | `/v5/messages/send` | gym | members.write |
| DELETE | `/v5/notifiers` | user |  |
| POST | `/v5/notifiers` | user |  |
| GET | `/v5/parq-form` | gym | plansets.read |
| PUT | `/v5/parq-form` | gym | plansets.write |
| GET | `/v5/parq-form/areas` | gym | plansets.read |
| POST | `/v5/parq-form/generate` | gym | plansets.write |
| GET | `/v5/parq-form/versions` | gym | plansets.read |
| GET | `/v5/parq/status` | gym | members.read |
| GET | `/v5/parq/submissions` | gym | members.read |
| GET | `/v5/parq/submissions/:id` | gym | members.read |
| GET | `/v5/payments/orders/:id` | gym | broadcasts.read |
| POST | `/v5/payments/orders/credit-packs` | gym | broadcasts.write |
| POST | `/v5/payments/orders/renewal-link` | gym | settings.write |
| POST | `/v5/payments/webhooks/gym/:gymId/razorpay` | none |  |
| POST | `/v5/payments/webhooks/razorpay` | none |  |
| GET | `/v5/portal/:code` | none |  |
| POST | `/v5/portal/:code/feedback` | none |  |
| POST | `/v5/portal/:code/otp` | none |  |
| POST | `/v5/portal/:code/register` | none |  |
| POST | `/v5/portal/:code/verify` | none |  |
| GET | `/v5/product-sales` | gym | products.read |
| POST | `/v5/product-sales` | gym | products.write |
| DELETE | `/v5/product-sales/:id` | gym | products.write |
| GET | `/v5/product-sales/:id` | gym | products.read |
| GET | `/v5/products` | gym | products.read |
| POST | `/v5/products` | gym | products.write |
| DELETE | `/v5/products/:id` | gym | products.write |
| GET | `/v5/products/:id` | gym | products.read |
| PATCH | `/v5/products/:id` | gym | products.write |
| POST | `/v5/products/:id/stock/correct` | gym | products.write |
| POST | `/v5/products/:id/stock/damage` | gym | products.write |
| GET | `/v5/products/:id/stock/history` | gym | products.read |
| POST | `/v5/products/:id/stock/receive` | gym | products.write |
| POST | `/v5/products/:id/stock/track` | gym | products.write |
| POST | `/v5/products/:id/stock/untrack` | gym | products.write |
| GET | `/v5/products/categories` | gym | products.read |
| GET | `/v5/products/damage-reasons` | gym | products.read |
| GET | `/v5/products/low-stock` | gym | products.read |
| GET | `/v5/prospects/members` | gym | leads.read |
| POST | `/v5/prospects/members` | gym | leads.write |
| DELETE | `/v5/prospects/members/:id` | gym | leads.write |
| GET | `/v5/prospects/members/:id` | gym | leads.read |
| PATCH | `/v5/prospects/members/:id` | gym | leads.write |
| POST | `/v5/prospects/members/:id/contacted` | gym | leads.write |
| POST | `/v5/prospects/members/:id/convert` | gym | leads.write | members.write |
| POST | `/v5/prospects/members/:id/disable` | gym | leads.write |
| POST | `/v5/prospects/members/:id/enable` | gym | leads.write |
| POST | `/v5/prospects/members/:id/snooze` | gym | leads.write |
| GET | `/v5/prospects/members/export` | gym | leads.read |
| GET | `/v5/prospects/meta` | gym | leads.read |
| POST | `/v5/register/partner` | none |  |
| POST | `/v5/register/partner/complete` | gym | settings.read |
| POST | `/v5/register/partner/gym` | user |  |
| POST | `/v5/register/partner/verify` | none |  |
| GET | `/v5/trainers` | gym | members.read |
| GET | `/v5/trainers/:id/bookings` | gym | members.read |
| GET | `/v5/trainers/:id/work-hours` | gym | members.read |
| GET | `/v5/trainers/me/bookings` | gym | trainer.self |
| POST | `/v5/trainers/me/bookings` | gym | trainer.self | trainers.write |
| DELETE | `/v5/trainers/me/bookings/:id` | gym | trainer.self | trainers.write |
| POST | `/v5/trainers/me/bookings/clear` | gym | trainer.self | trainers.write |
| POST | `/v5/trainers/me/bookings/preview` | gym | trainer.self | trainers.write |
| GET | `/v5/trainers/me/work-hours` | gym | trainer.self |
| PUT | `/v5/trainers/me/work-hours` | gym | trainer.self |
| DELETE | `/v5/users/self` | user |  |
| GET | `/v5/users/self` | user |  |
| PATCH | `/v5/users/self` | user |  |
| POST | `/v5/users/self/delete-otp` | user |  |
| DELETE | `/v5/users/self/photo` | user |  |
| POST | `/v5/users/self/photo` | user |  |
| POST | `/v5/users/self/revoke-sessions` | user |  |
| GET | `/v5/video-links` | gym | plans.read |
| POST | `/v5/video-links` | gym | videos.write |
| DELETE | `/v5/video-links/:id` | gym | videos.write |
| PATCH | `/v5/video-links/:id` | gym | videos.write |
| POST | `/v5/workout/generate` | gym | plansets.write |
| DELETE | `/v5/workout/members/:memberId` | gym | plansets.write |
| GET | `/v5/workout/members/:memberId` | gym | plansets.read |
| PUT | `/v5/workout/members/:memberId` | gym | plansets.write |
| GET | `/v5/workout/plans` | gym | plansets.read |
| POST | `/v5/workout/plans` | gym | plansets.write |
| DELETE | `/v5/workout/plans/:id` | gym | plansets.write |
| GET | `/v5/workout/plans/:id` | gym | plansets.read |
| PUT | `/v5/workout/plans/:id` | gym | plansets.write |
| POST | `/v5/workout/plans/:id/assign` | gym | plansets.write |
