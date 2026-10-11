# First paying gym (India)

## What you sell

Gym owners pay a monthly or yearly subscription. The plans, limits and add-ons are enforced by the server:

| Plan | Price (incl. 18% GST) | Members | Staff | Includes |
|---|---|---|---|---|
| Trial | free, 14 days from the end of gym setup, once per owner (kept on the server) | 300 | 5 | everything, so they can try it |
| Starter | ₹499 / month | 150 | 3 | members, plans, payments, attendance, reports, reminders |
| Growth | ₹999 / month (₹9,990 / year) | 800 | 10 | + member app, WhatsApp messaging, product sales, workout and diet plans |
| Pro | ₹1,999 / month (₹19,990 / year) | 5,000 | 50 | + AI insights and workouts, biometric devices |

After the end date the gym is read-only for 7 days, then only billing works; its members are locked out of the member app too.
Message credits (1 credit per message) are a second income: packs of 500 / 1,000 / 5,000. Price them above what MSG91 and WhatsApp
charge you per message (check both rate cards on the day you set prices) and edit `catalog.js` or `PRICING_FILE`.
These numbers are a starting point, not research: test them with the first ten gyms.

## Pilot (weeks 1-6)

1. Pick 3-5 gyms you can visit. Free for 30 days, in exchange for feedback and a testimonial.
2. Onboard in person: create the gym, import members (CSV from their register), set plans and the UPI QR, run one renewal and one broadcast with them watching.
3. Week 2: check what they use. Renewal reminders, dues and at-risk members are the reasons owners pay; make sure they see money recovered on the dashboard.
4. Day 25: show the price, switch them to Starter/Growth with `scripts/admin.js` (or let them pay in the app).

## Numbers to watch

Gyms activated, members added per gym, messages sent, trial to paid conversion, monthly churn, credit purchases, support requests per gym.
Revenue: `node scripts/admin.js revenue 2026-11`.

## Referral

A gym that signs up with another gym's 6-digit code earns that gym 30 free days and 100 credits when it first pays.

## Not yet (later)

Member online payments to the gym (Razorpay Route), class and personal-trainer booking, iOS, other countries (UAE and UK are the closest:
remove the India defaults first).

## Collecting members' fees

A gym can connect its **own** Razorpay account (Settings > Online payments, or the optional step after setup, which can be skipped). Keys are checked with Razorpay,
stored sealed, and never shown again. Money goes to the gym's account; Gymmie only creates the payment link with the gym's keys and records the payment when the gym's own
webhook (`/v5/payments/webhooks/gym/<gym id>/razorpay`, event `payment_link.paid`) confirms it. This is separate from the gym's Gymmie subscription.
