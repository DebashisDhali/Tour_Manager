# Tour Cost App Monetization Blueprint

## Goal
Create a low-friction earning model that keeps the core app usable for everyone, while power users, organizers, and teams pay for clear value.

## Product Reality
- The app solves real daily pain: shared expense tracking, event/tour budgeting, settlement, and member collaboration.
- Users can be: friends groups, event organizers, mess managers, trip leaders, and small teams.
- Best model is hybrid: freemium + premium subscription + transactional upsell + B2B package.

## Monetization Strategy (Practical)

### 1. Freemium Core (Always Free)
Keep this free so growth does not stop:
- Create tours/events/projects
- Add members
- Basic expense split and settlement
- Basic sync
- Join with code

Why:
- Fast user growth
- Better trust
- More upgrade opportunities later

### 2. Pro Subscription (Main Revenue)
Target active organizers and heavy users.

Suggested tiers:
1. Pro Individual (monthly/yearly)
2. Pro Group (up to fixed member limit)
3. Pro Organizer (event-focused)

What Pro unlocks:
- Unlimited active events/tours
- Advanced analytics dashboards
- Export to PDF/Excel with branding
- Smart reminders and due notifications
- Role and permission controls (advanced)
- Priority sync and backup reliability
- AI insights and spending suggestions
- Multi-currency + exchange support

### 3. Team/Business Plan (High ARPU)
Target clubs, tour companies, event agencies, hostels/mess operators.

Features:
- Admin panel for organization
- Shared workspace across many events
- Audit logs and change history
- Invoice/billing controls
- API/webhook access
- Dedicated support SLA

### 4. Add-on Revenue (Non-Subscription)
Monetize specific actions:
- Paid premium report templates
- Paid event branding themes
- Paid GST/VAT-ready accounting export packs
- Paid one-click sponsor report pack

### 5. Ads (Careful Use)
If you use ads, keep them non-intrusive:
- Free users only
- No ad in expense entry flow
- Use subtle banner/native card in non-critical screens

Good rule:
- Ads should not hurt trust in money-related flows.

## Feature Packaging (Free vs Premium)

### Free
- Up to 3 active events
- Basic split methods
- Manual reminders
- Standard support

### Premium
- Unlimited events
- Auto-reminders and smart nudges
- Advanced settlement and insights
- Export center (PDF/Excel/receipt branding)
- Priority cloud sync and backup retention
- AI coach suggestions and budget alerts

### Enterprise
- Centralized controls
- Multi-admin role matrix
- Compliance report packs
- Integration support

## Premium Features You Can Add Next
1. Smart Debt Collection Mode
- Auto schedule: who should pay first
- Reminder sequence with tone levels

2. Event Budget Guardrails
- Category budget caps
- Live overspend alerts

3. Receipt Intelligence
- OCR from bills
- Auto category detection
- Duplicate expense detection

4. Reconciliation Mode
- Verify payer and split conflicts
- Suggest fixes before settlement

5. Organizer Command Center
- Event health score
- Pending approvals, unpaid counts, risk flags

6. Trusted History
- Immutable audit timeline for key actions

7. Family and Group Vault
- Snapshot backup and restore points

8. Branded Exports
- Organization logo, footer, signature blocks

## Pricing Suggestion (Starter)
- Pro Individual: 149-299 BDT/month
- Pro Group: 399-799 BDT/month
- Organizer: 999-1999 BDT/month
- Yearly plans: 20-30% discount

Notes:
- Start low for conversion.
- Increase price after strong retention and proven value.

## Conversion Triggers (Important)
Show upgrade prompts at value moments:
- User reaches active event limit
- User tries export or advanced analytics
- User opens AI insights more than 3 times
- Organizer repeatedly shares reports

Do not over-prompt:
- Avoid showing paywall before first meaningful success.

## Rollout Plan (90 Days)

### Phase 1 (0-30 days)
- Launch feature flags for premium-gated modules
- Add subscription screen and entitlement checks
- Add one premium value feature: Export Center

### Phase 2 (31-60 days)
- Add Budget Guardrails and Smart Reminders
- Add clear upgrade prompts at value points
- Track conversion funnel events

### Phase 3 (61-90 days)
- Launch Organizer plan
- Launch branded export templates
- Add yearly plans and referral offer

## Metrics to Track
- Free to paid conversion
- Day 7 and day 30 retention
- ARPU and MRR
- Churn rate by plan
- Feature adoption per premium module

## Payment and Access Control Requirements
- Platform billing integration
- Server-validated entitlement status
- Local cache for offline checks with expiry
- Grace period handling for billing failures

## Risk and Guardrails
- Never break core trust features behind paywall abruptly
- Keep free plan functional for essential expense flow
- Ensure financial records remain accessible even after downgrade
- Provide transparent billing terms and cancellation

## Recommended Next Build Order
1. Export Center (premium)
2. Budget Guardrails (premium)
3. Smart reminders (premium)
4. Organizer dashboard (pro/enterprise)
5. OCR receipts (premium add-on)

## One-Line Positioning
"Free for group expense basics, premium for serious organizers who want speed, control, and smart insights."