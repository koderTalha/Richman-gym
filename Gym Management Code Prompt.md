You are a senior full-stack engineer and product designer. Build a production-quality web application for a gym that replaces the owner's current Excel-based member and payment workflow.

The gym owner currently manages members in Excel. When a member pays by cash, bank transfer, Easypaisa, JazzCash, or another method, the owner manually marks the member as paid, manually creates a receipt, and manually sends that receipt to the member on WhatsApp.

The new system must replace this workflow.

# PRODUCT GOAL

Build a complete gym website consisting of:

1. Public landing page for the gym
2. Secure admin login
3. Admin dashboard
4. Member management
5. Membership/payment tracking
6. Excel member import
7. Payment recording workflow
8. Automatic receipt generation
9. Automatic WhatsApp receipt sending
10. Receipt/payment history
11. WhatsApp delivery/status tracking
12. Reports and dashboard statistics

The most important workflow in the entire application is:

Payment Confirmed
→ Payment saved
→ Membership/payment status updated
→ Unique receipt created
→ Receipt image generated
→ Receipt stored
→ Receipt sent through WhatsApp
→ WhatsApp status stored
→ Admin sees success/failure
→ Failed WhatsApp sends can be retried

The UI should be easy enough for a non-technical gym owner to use every day.

---

# TECH STACK

Use:

- Next.js with App Router
- TypeScript
- Tailwind CSS
- shadcn/ui where useful
- PostgreSQL
- Prisma ORM
- NextAuth/Auth.js or a secure credential-based authentication implementation
- Zod for validation
- React Hook Form where appropriate
- Server Actions or API routes where appropriate
- Official Meta WhatsApp Business Cloud API for WhatsApp integration
- A clean server-side receipt generation solution capable of generating PNG/JPG
- Also support PDF receipt generation if practical
- Use local storage during development and abstract file storage so S3/Cloudinary-compatible storage can be used in production

Do NOT build microservices.

Keep the architecture as one maintainable full-stack Next.js application.

Use current stable package versions compatible with each other.

---

# DESIGN DIRECTION

Create a premium, modern fitness/gym visual identity.

The site should feel:

- Modern
- Strong
- Professional
- Minimal
- Premium
- Mobile responsive
- Easy to understand
- Fast

Avoid overly flashy animations.

Use strong typography, generous spacing, high-quality dashboard layout, clear cards, tables, badges, buttons, and form states.

Use a consistent design system across the public website and admin application.

The gym name can initially be:

POWER GYM

Make the gym branding configurable later.

---

# PUBLIC WEBSITE

Create a professional public-facing landing page.

Pages/sections should include:

## Navbar

- Logo
- Home
- About
- Memberships
- Facilities
- Contact
- Login button

## Hero Section

Include:

- Strong gym headline
- Supporting copy
- CTA such as "Join Power Gym"
- Secondary CTA such as "View Membership Plans"

Use a premium gym visual design.

## About Section

Brief information about the gym.

## Facilities Section

Examples:

- Strength training
- Cardio
- Free weights
- Personal training
- Modern equipment
- Locker facilities

## Membership Plans

Display configurable plans such as:

Monthly
Quarterly
6 Months
Annual

Each plan should have:

- Name
- Price
- Duration
- Benefits
- CTA

These plans should eventually come from the database.

## Why Choose Us

Use feature cards.

## Testimonials

Create sample placeholder testimonials that can later be replaced.

## Contact Section

Include:

- Phone
- WhatsApp
- Address
- Opening hours
- Contact CTA

## Footer

Include:

- Gym information
- Navigation
- Contact details
- Social placeholders
- Admin login link

The landing page must be fully responsive.

---

# AUTHENTICATION

Create a secure admin login system.

Route:

/admin/login

Fields:

- Email
- Password

Requirements:

- Password hashing
- Protected admin routes
- Session handling
- Logout
- Invalid login errors
- Loading states
- Secure cookies
- Middleware or equivalent route protection

Initially support one role:

ADMIN

Architect the database so other roles such as STAFF can be introduced later.

Do not allow public registration for administrators.

Provide a database seed script that creates a development admin account using environment variables.

---

# ADMIN LAYOUT

Protected routes should use an admin dashboard layout.

Sidebar:

- Dashboard
- Members
- Payments
- Receipts
- Membership Plans
- WhatsApp
- Reports
- Settings
- Logout

Top bar:

- Search if useful
- Gym name
- Admin profile
- Current page title

Make the sidebar responsive for mobile.

---

# ADMIN DASHBOARD

Route:

/admin

Display useful operational metrics:

- Total members
- Active members
- Members with payments due
- Payments received today
- Revenue today
- Revenue this month
- Receipts sent today
- Failed WhatsApp receipts
- Upcoming membership expirations

Include:

Recent Payments table

Columns:

- Member
- Amount
- Payment method
- Date
- Receipt number
- WhatsApp status

Include a prominent:

"+ Record Payment"

button.

Also include:

"Add Member"

button.

---

# MEMBER MANAGEMENT

Route:

/admin/members

Display members in a searchable, filterable table.

Columns:

- Member ID
- Name
- Phone
- Membership
- Fee
- Start Date
- Expiry / Next Due Date
- Payment Status
- Membership Status
- Actions

Filters:

- All
- Active
- Inactive
- Paid
- Due
- Expiring Soon

Search by:

- Member name
- Phone
- Member ID

Actions:

- View
- Edit
- Record Payment
- Deactivate

Add Member route/dialog should support:

- Full name
- Phone number
- Email optional
- Gender optional
- Date of birth optional
- Address optional
- Joining date
- Membership plan
- Custom fee if necessary
- Emergency contact optional
- Notes
- Status

Phone numbers must be normalized so they can later be used with WhatsApp.

Assume Pakistan as the initial market, but do not hardcode the app so it cannot support international numbers.

---

# MEMBER PROFILE

Route:

/admin/members/[id]

Display:

- Member name
- Phone
- Membership plan
- Membership status
- Current fee
- Joining date
- Current period
- Next due/expiry date

Show prominent status:

PAID
DUE
EXPIRED
INACTIVE

Include:

"Record Payment"

button.

Sections:

## Payment History

Columns:

- Receipt number
- Billing period
- Amount
- Payment method
- Payment date
- Payment status
- Receipt
- WhatsApp status

## Membership History

Allow the system to maintain history instead of overwriting previous memberships.

## Member Notes

---

# IMPORTANT PAYMENT MODEL

Do NOT simply store:

member.paymentStatus = "paid"

as the primary payment model.

Payment information must be historical and transactional.

A member may have:

January - Paid
February - Paid
March - Paid
April - Due

Design the database around:

Members
Memberships
MembershipPeriods or MembershipSubscriptions
Payments
Receipts

The application should calculate current payment/membership status from the relevant active membership and payment records.

---

# RECORD PAYMENT WORKFLOW

This is the core feature.

From the member page or payment page, admin presses:

"Record Payment"

Show a form containing:

Member:
Automatically selected when opened from member page.

Amount:
Default to membership fee but editable.

Payment method:

- Cash
- Bank Transfer
- Easypaisa
- JazzCash
- Card
- Other

Payment date:
Default today.

Billing period:
For example August 2026.

Transaction/reference ID:
Optional.

Notes:
Optional.

Checkbox:

"Send receipt on WhatsApp"

Default checked if member has a valid phone number.

Button:

"Confirm Payment"

---

# TRANSACTION WORKFLOW

When "Confirm Payment" is clicked:

1. Validate input.

2. Create payment database record.

3. Generate a unique receipt number.

Example format:

PG-2026-000001

Do not generate duplicate receipt numbers.

4. Update/calculate the membership period/payment status.

5. Generate a professional receipt.

6. Generate receipt PNG/JPG.

7. Generate PDF version if supported.

8. Save receipt information.

9. If "Send receipt on WhatsApp" was enabled:
   send receipt through the WhatsApp service.

10. Save WhatsApp API response and message ID.

11. Show success screen.

Example:

Payment recorded successfully.

Receipt: PG-2026-000184

✓ Payment saved
✓ Receipt generated
✓ WhatsApp sent

Buttons:

- View Receipt
- Download Receipt
- Print Receipt
- View Member
- Record Another Payment

If WhatsApp fails:

Payment must STILL remain recorded.

Show:

✓ Payment saved
✓ Receipt generated
✕ WhatsApp failed

Provide:

"Retry WhatsApp"

button.

WhatsApp failure must never roll back a legitimate payment.

Use safe database transactions where appropriate.

---

# RECEIPT DESIGN

Generate a visually polished receipt suitable for WhatsApp.

The receipt image should include:

- Gym logo
- Gym name
- "PAYMENT RECEIPT"
- Receipt number
- Payment date
- Member name
- Member ID
- Membership plan
- Billing period
- Payment method
- Transaction/reference number if available
- Amount paid
- PAID badge
- Gym phone
- Gym address
- Thank-you message

Example layout:

POWER GYM

PAYMENT RECEIPT

Receipt #: PG-2026-000184
Date: 12 Aug 2026

Member:
Ali Khan

Membership:
Monthly Membership

Billing Period:
August 2026

Payment Method:
Cash

AMOUNT PAID

Rs. 3,000

PAID

Thank you for choosing Power Gym.

Design it vertically so it looks good on a mobile phone in WhatsApp.

Store both the receipt metadata and generated file path/URL.

---

# RECEIPTS PAGE

Route:

/admin/receipts

Table:

- Receipt number
- Member
- Amount
- Billing period
- Payment method
- Created date
- WhatsApp status
- Actions

Actions:

- View
- Download PNG
- Download PDF
- Print
- Resend WhatsApp

Search by:

- Receipt number
- Member
- Phone

Filters:

- Date
- Payment method
- WhatsApp sent
- WhatsApp failed

---

# WHATSAPP INTEGRATION

Create a dedicated WhatsApp service module.

Do NOT tightly couple the Meta API implementation to payment logic.

Example architecture:

services/
  whatsapp/
    client.ts
    sendReceipt.ts
    types.ts

Create environment variables for:

WHATSAPP_PHONE_NUMBER_ID
WHATSAPP_ACCESS_TOKEN
WHATSAPP_BUSINESS_ACCOUNT_ID
WHATSAPP_WEBHOOK_VERIFY_TOKEN

Use the official Meta WhatsApp Business Cloud API.

Do not use WhatsApp Web automation, Selenium, browser automation, or unofficial libraries that may violate WhatsApp's rules.

The integration should support:

- Sending a message to member phone
- Sending receipt image/media
- Storing Meta message ID
- Handling API failures
- Retrying failed sends
- Recording message status

Design the implementation so production-approved WhatsApp message templates can be introduced.

Where actual Meta credentials are unavailable during development:

Implement a mock WhatsApp provider.

Environment:

WHATSAPP_PROVIDER=mock

or:

WHATSAPP_PROVIDER=meta

Mock mode should behave as if the message was successfully sent and create realistic test status records.

This is important so the full application can be developed and tested without real WhatsApp credentials.

---

# WHATSAPP WEBHOOK

Create a webhook endpoint for Meta WhatsApp status updates.

Support statuses such as:

- queued
- sent
- delivered
- read
- failed

Store:

- external message ID
- status
- timestamp
- error message if applicable

Protect webhook verification according to Meta requirements.

Do not expose secrets to the browser.

---

# WHATSAPP PAGE

Route:

/admin/whatsapp

Show messaging history.

Columns:

- Member
- Phone
- Receipt
- Message ID
- Sent date
- Current status
- Error

Status badges:

Queued
Sent
Delivered
Read
Failed

Filters:

- All
- Sent
- Delivered
- Read
- Failed

For failed messages include:

"Retry"

action.

---

# EXCEL IMPORT

A major requirement is importing the gym owner's existing Excel member sheet.

Route:

/admin/members/import

Support:

.xlsx
.csv

Create an import wizard.

Step 1:
Upload file.

Step 2:
Show detected columns.

Step 3:
Map Excel columns to application fields.

Example:

Excel "Customer Name"
→ Member Name

Excel "Mobile"
→ Phone

Excel "Monthly Fee"
→ Fee

Excel "Payment Status"
→ Existing Status

Step 4:
Preview first rows.

Step 5:
Validate.

Detect:

- Empty names
- Invalid phone numbers
- Duplicate members
- Invalid dates
- Invalid fees

Step 6:
Import.

Show summary:

245 members imported
8 duplicates skipped
3 rows need attention

Allow downloading rejected/error rows if practical.

IMPORTANT:

Do not permanently depend on Excel after migration.

PostgreSQL must become the primary source of truth.

---

# MEMBERSHIP PLANS

Route:

/admin/membership-plans

Admin can create plans.

Fields:

- Plan name
- Description
- Duration
- Price
- Active/inactive

Examples:

Monthly
3 Months
6 Months
Annual

Members can be assigned a plan.

Allow custom member pricing when needed.

---

# PAYMENTS PAGE

Route:

/admin/payments

Show:

- Payment ID
- Receipt number
- Member
- Amount
- Billing period
- Method
- Reference number
- Payment date
- Recorded by
- WhatsApp status

Filters:

- Date range
- Method
- Member
- Billing month

Include:

"+ Record Payment"

---

# REPORTING

Route:

/admin/reports

Create useful basic reports:

Revenue:
- Today
- This month
- Selected date range

Payment method breakdown:
- Cash
- Bank
- Easypaisa
- JazzCash
- Other

Membership report:
- Active members
- Expired
- Due
- Expiring soon

Receipt report:
- Total receipts
- Successfully sent
- Failed sends

Allow CSV export.

Do not overbuild advanced analytics initially.

---

# SETTINGS

Route:

/admin/settings

Sections:

## Gym Information

- Gym name
- Logo
- Phone
- WhatsApp phone
- Email
- Address
- Currency
- Receipt footer message

Default currency:

PKR

Display amounts like:

Rs. 3,000

Do not hardcode currency logic so other currencies cannot be added.

## Receipt Settings

Allow configuration of:

- Receipt prefix
- Gym logo
- Footer
- Contact details

## WhatsApp Settings

Display configuration status but NEVER expose secret tokens.

Show:

WhatsApp:
Connected / Not configured

Provider:
Mock / Meta

Phone number:
masked or public business number

---

# DATABASE DESIGN

Create a proper Prisma schema.

At minimum consider models for:

User
GymSettings
Member
MembershipPlan
Membership
Payment
Receipt
WhatsAppMessage
MemberNote
ImportJob

Suggested relationships:

Member
has many Memberships

Member
has many Payments

Payment
belongs to Member

Payment
has one Receipt

Receipt
has zero or many WhatsAppMessage attempts

Membership
belongs to Member

Membership
belongs to MembershipPlan

User
records Payments

Do not blindly implement this exact schema if a better normalized structure makes sense.

Use:

- UUIDs or secure IDs internally
- createdAt
- updatedAt

Use database constraints where appropriate.

Receipt number must be unique.

Phone numbers should be normalized.

Payment records should not be silently deleted.

Use soft deletion/deactivation where financial history must remain preserved.

---

# BUSINESS RULES

Implement these carefully:

1. Financial history must not disappear if a member is deactivated.

2. Payment records must be immutable enough to preserve an audit trail.

3. Duplicate payment submission should be protected against accidental double clicks.

4. WhatsApp failure does not invalidate payment.

5. Receipt number must always be unique.

6. A receipt must reference exactly one payment.

7. Every payment should record who created it.

8. Membership status should be derived from actual dates and payment/membership records, not only from a manually edited text field.

9. Phone number validation must occur before WhatsApp send.

10. The user must be warned before destructive operations.

---

# SEARCH AND FILTERING

Create reusable search/filter behavior.

Users should be able to quickly find a member by:

- Name
- Phone
- Member ID

The gym owner may have hundreds or thousands of members, so optimize common queries appropriately.

---

# UX REQUIREMENTS

The owner should be able to perform the most common workflow extremely quickly.

Target workflow:

Dashboard
→ Search "Ali"
→ Open Ali
→ Record Payment
→ Confirm
→ Done

Do not make the owner navigate through many unnecessary screens.

Provide:

- Loading states
- Empty states
- Validation errors
- Success notifications
- Error notifications
- Confirmation dialogs
- Mobile responsive tables/cards
- Useful badges
- Keyboard-friendly forms

---

# MOBILE SUPPORT

The admin dashboard must work properly on:

- Desktop
- Tablet
- Mobile

This is important because the gym owner may use the system on a phone.

Make Record Payment especially easy to use on mobile.

---

# SECURITY

Implement production-minded security.

Requirements:

- Password hashing
- Secure authentication
- Protected routes
- Server-side authorization
- Input validation
- Zod validation
- CSRF-safe patterns
- Secure session cookies
- No secrets in client code
- Environment variables
- Sanitize/validate uploads
- Validate Excel file type and size
- Rate-limit sensitive APIs where practical
- Prevent unauthorized receipt access

Never log access tokens or passwords.

---

# ENVIRONMENT VARIABLES

Create:

.env.example

Include placeholders for:

DATABASE_URL

AUTH_SECRET

ADMIN_EMAIL
ADMIN_PASSWORD

WHATSAPP_PROVIDER

WHATSAPP_PHONE_NUMBER_ID
WHATSAPP_BUSINESS_ACCOUNT_ID
WHATSAPP_ACCESS_TOKEN
WHATSAPP_WEBHOOK_VERIFY_TOKEN

NEXT_PUBLIC_APP_URL

STORAGE_PROVIDER
and any required storage credentials

Never commit actual secrets.

---

# DEVELOPMENT MODE

The complete app must work locally without:

- Meta WhatsApp credentials
- Cloud storage credentials

Provide:

Mock WhatsApp service

and:

Local receipt/file storage

so development can run immediately.

---

# SEED DATA

Create seed data including:

Admin:

admin@powergym.local

Use environment variable for password.

Create sample membership plans.

Create approximately 15 realistic test members.

Some members should be:

Paid
Due
Expired
Inactive

Create sample historical payments and receipts.

This will make dashboard development easier.

---

# TESTING

Add tests for critical business logic.

At minimum test:

- Authentication protections
- Payment creation
- Receipt number generation
- Duplicate receipt prevention
- Payment validation
- Member status calculation
- WhatsApp failure behavior
- Retry behavior

Use an appropriate testing framework for the stack.

---

# PROJECT STRUCTURE

Keep code well organized.

Suggested conceptual structure:

app/
  (public)/
  admin/
  api/

components/
  admin/
  landing/
  members/
  payments/
  receipts/
  ui/

lib/
  auth/
  database/
  validation/
  receipts/
  whatsapp/
  storage/

services/

prisma/

types/

Do not create unnecessary abstractions.

---

# README

Write an excellent README.

Include:

- Project overview
- Screenshots placeholders
- Features
- Architecture
- Requirements
- Local setup
- Database setup
- Environment variables
- Prisma migration commands
- Seed commands
- Running locally
- Mock WhatsApp setup
- Meta WhatsApp setup
- Webhook setup
- Production deployment notes

---

# INITIAL DEVELOPMENT ORDER

Build the system incrementally.

Phase 1:
- Project initialization
- Database
- Authentication
- Admin shell
- Public landing page

Phase 2:
- Membership plans
- Members
- Member profile
- Search/filter

Phase 3:
- Payments
- Payment history
- Status calculation

Phase 4:
- Receipt generation
- PNG
- PDF
- Receipt history

Phase 5:
- WhatsApp abstraction
- Mock provider
- Meta provider
- Retry functionality
- Webhooks

Phase 6:
- Excel import

Phase 7:
- Reports
- Settings
- UX polish
- Testing

Do not attempt to generate the entire application as one giant untested code dump.

Implement one working phase at a time while keeping the application runnable.

---

# IMPORTANT CODING INSTRUCTIONS

Before writing code:

1. Analyze the requirements.
2. Create the architecture.
3. Create the database schema.
4. Create an implementation plan.
5. Then start implementation.

When implementing:

- Do not leave core features as TODO comments.
- Do not fake database operations.
- Do not fake receipt generation.
- Use mock WhatsApp only behind an explicit provider abstraction.
- Keep TypeScript strict.
- Keep components reasonably small.
- Reuse components.
- Avoid unnecessary dependencies.
- Avoid deprecated APIs.
- Handle errors properly.
- Keep server logic out of client components whenever possible.
- Do not expose Prisma directly to the browser.

After each major phase:

- Run TypeScript checks.
- Run linting.
- Run relevant tests.
- Fix errors before continuing.

---

# CORE ACCEPTANCE TEST

The application is considered successful when this exact workflow works:

1. Admin logs in.

2. Admin searches for "Ali Khan".

3. Admin opens Ali's profile.

4. Ali currently has August membership payment marked as due.

5. Admin presses "Record Payment".

6. Admin selects:
   Amount: Rs. 3,000
   Method: Cash
   Billing period: August 2026
   Send WhatsApp: Yes

7. Admin presses "Confirm Payment".

8. System creates payment.

9. System creates unique receipt number.

10. System generates a professional PNG receipt.

11. System stores the receipt.

12. System changes Ali's current payment state to paid.

13. System sends the receipt through the configured WhatsApp provider.

14. System stores WhatsApp message status.

15. Admin sees:

Payment Recorded Successfully

✓ Payment Saved
✓ Receipt Generated
✓ WhatsApp Sent

16. Ali's member page now shows the new payment in Payment History.

17. Receipt appears under Receipts.

18. WhatsApp message appears under WhatsApp history.

19. Dashboard revenue updates correctly.

20. If the WhatsApp call fails, the payment and receipt remain saved and admin can press "Retry WhatsApp".

This workflow is the highest priority of the application.

---

# FINAL PRODUCT PHILOSOPHY

This is NOT primarily a large generic gym ERP.

It is a simple operational system designed around one major automation:

RECEIVE PAYMENT
→ RECORD PAYMENT
→ GENERATE RECEIPT
→ SEND WHATSAPP
→ SAVE EVERYTHING

Make this workflow extremely reliable and easy.

The gym owner is replacing Excel and manual WhatsApp work, so the software should feel simpler than the old process, not more complicated.

Start by showing me:

1. Proposed architecture
2. Prisma/database schema
3. Route structure
4. Folder structure
5. Major reusable components
6. Payment-to-receipt-to-WhatsApp workflow
7. Implementation phases

Then begin building Phase 1.