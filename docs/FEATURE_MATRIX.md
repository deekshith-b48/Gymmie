# Feature matrix

Legend: ✅ implemented and exercised · 🟡 implemented, not exercised on device · ❌ not implemented

| Module | Status | Notes |
|---|---|---|
| Auth: phone login, OTP, register, gym setup/selection, backend setup | ✅ | dev OTP stand-in |
| Splash, maintenance, expired, unauthorized, update screens | ✅ | |
| Dashboard | ✅ | |
| Members: list/filter, add/edit, detail, renew, at-risk, pick | ✅ | |
| Memberships and plans (+ groups) | ✅ | |
| Transactions, balance, reminders, invoice PDF | ✅ | |
| Reports | ✅ | |
| Leads: list, form, convert | ✅ | |
| Attendance logs, QR scan | ✅ | off by default; admin enables in App Features |
| Members-in-gym home card | ✅ | off by default; admin enables in App Features |
| Member ID card (labels, QR, share as image) | ✅ | |
| Staff, trainer schedule, working hours, bookings | ✅ | |
| Products, sales, expenses | ✅ | |
| Messaging: broadcasts, templates, credits, history, WhatsApp | 🟡 | outbox stand-in, nothing is actually sent |
| Workout plans, diet plans, exercise library, generators, assign to member | ✅ | rule-based generators |
| PAR-Q builder + member signing/view | ✅ builder / 🟡 signing | signature pad not drawn through on emulator |
| Feedback, video links, poster | 🟡 | |
| Biometric devices | 🟡 | off by default; admin enables in App Features |
| Settings hub and pages | ✅ | |
| Report-schedule settings page | ❌ | |
| Payment return link (`gymmie://payments`) handled in the app | 🟡 | the manifest filter exists; the app opens the pay page and the billing screens re-read the order when you come back |
| FCM push registration | ❌ | endpoint exists in backend; needs a real Firebase project |
| `view-photo` route | ❌ | |
| Localisation | 🟡 | English + partial Hindi |
