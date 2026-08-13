# Rich Man Fitness — Gym Management System: Design Spec

**Date:** 2026-08-12
**Status:** Approved for implementation planning
**Source brief:** [`Gym Management Code Prompt.md`](../../../Gym%20Management%20Code%20Prompt.md) (original product prompt, treated as the base requirements — this doc supersedes it where the two disagree, per decisions recorded below)

## 1. Product summary

Replace the gym owner's Excel + manual-WhatsApp workflow with a single Next.js application. The core automation, and the highest-priority feature in the whole system:

```
Record Payment → Save Payment → Update membership/payment status → Generate unique receipt
→ Render receipt PNG/PDF → Store receipt → Send receipt via WhatsApp → Store WhatsApp status
→ Admin sees ✓/✕ per step → Failed WhatsApp sends are retryable, payment is never rolled back
```

Everything else (member management, plans, reports, settings, Excel import) exists in service of making that workflow fast, reliable, and easy for a non-technical owner to run from a phone.

## 2. Decisions made during brainstorming (deltas from the original brief)

These were resolved through discussion with the gym owner and by inspecting the owner's real, currently-in-use Excel ledger ("RICH MAN FITNESS LEDGER"):

| Topic | Decision |
|---|---|
| Gym name | **Rich Man Fitness** (from the real ledger title), not the placeholder "Power Gym". Still configurable in Settings. |
| Auth | **Auth.js (NextAuth v5)** with the Credentials provider + bcrypt, over a hand-rolled session implementation. |
| Receipt PNG engine | **satori + resvg** (JSX → SVG → PNG). No headless browser, no native canvas bindings; same technique `@vercel/og` uses. |
| Receipt PDF engine | **pdf-lib**, embedding the exact same satori/resvg-rendered PNG into a one-page PDF — guarantees PNG and PDF are pixel-identical, one layout to maintain. |
| WhatsApp | Build entirely against the **mock provider** first (`WHATSAPP_PROVIDER=mock`). No Meta credentials exist yet; the abstraction is designed so Meta is a drop-in swap later. |
| Local Postgres | **Docker Compose**, fully local/offline — no cloud account needed for development. |
| Sections/branches | **New first-class concept.** The real ledger has separate "Entry Book (Boys)" / (Girls) and "Night Shift" sheets. Modeled as a `Section` entity (e.g. "Boys", "Girls", "Night Shift") that a `Member` belongs to. Filterable in Members/Reports/Dashboard. Managed via a simple CRUD tab inside Settings — not a dedicated sidebar item (YAGNI). |
| Excel import shape | The real ledger is a **wide format**: one row per member, with **12 month columns (Jan–Dec) per year-sheet**, each cell holding the amount paid that month. This is materially different from a flat "one row = current status" import and is designed for explicitly (see §7). |
| Historical import scope | **Import all available years** of ledger history as real historical `Payment`/`MembershipPeriod` records. Historical/imported payments **always skip WhatsApp sending** (`source = IMPORTED`) — no receipts get sent retroactively for old cash payments. Only new, live-recorded payments trigger WhatsApp. |
| Visual style | **"Crimson & Steel"** — near-black backgrounds, crimson-red accent, white type. Confirmed by the owner over two alternatives (Amber & Charcoal, Emerald & Slate). |
| Receipt layout | Vertical, phone-width layout; includes Section (e.g. "Monthly — Boys") since that's meaningful context in the real roster; reference/transaction number shown only when the payment method has one. |

## 3. Architecture

Single Next.js 15 (App Router) application. No microservices, no separate backend service.

```
Visitor browser ──┐                    Admin (gym owner) browser
                   ▼                                  ▼
            ┌──────────────────────────────────────────────────┐
            │                Next.js App Router                 │
            │  app/(public)      app/admin        app/api        │
            │  landing page      dashboard,       NextAuth,      │
            │                    members,         WhatsApp       │
            │                    payments, …      webhook,       │
            │                                      receipt file  │
            └───────────────────────┬────────────────────────────┘
                                     ▼
                         services/  (business workflows)
                recordPayment · importMembers · computeMemberStatus · reports
                                     ▼
        lib/auth   lib/db (Prisma)   lib/receipts   lib/whatsapp   lib/storage
                                     ▼
        PostgreSQL (Docker, local)   WhatsApp Cloud API (Meta / mock)   File storage (local → S3-compatible)
```

**Layering rule:** Server Actions and route handlers are thin — validate input with Zod, then call a `services/` function. All real logic lives in `services/`, which is what tests target. `lib/db` (the Prisma client) is `server-only` and is never imported from a `"use client"` file or exposed to the browser.

## 4. Database schema (Prisma)

The payment model is intentionally **historical and transactional**, never a single overwritten status flag (per business rule #8 in the original brief). The chain:

```
Member → Membership → MembershipPeriod → Payment → Receipt → WhatsAppMessage
```

This maps directly onto the real ledger: each `MembershipPeriod` corresponds to one month column in the sheet. Changing a member's plan closes the old `Membership` row (`endDate` set) and opens a new one, preserving membership history per the brief's requirement.

```prisma
enum Role             { ADMIN STAFF }
enum PaymentMethod    { CASH BANK_TRANSFER EASYPAISA JAZZCASH CARD OTHER }
enum PaymentSource    { MANUAL IMPORTED }
enum WhatsAppStatus   { QUEUED SENT DELIVERED READ FAILED }
enum WhatsAppProvider { MOCK META }
enum ImportStatus     { PENDING VALIDATED COMMITTED FAILED }

model User {
  id               String   @id @default(uuid())
  name             String
  email            String   @unique
  passwordHash     String
  role             Role     @default(ADMIN)
  createdAt        DateTime @default(now())
  updatedAt        DateTime @updatedAt
  paymentsRecorded Payment[]    @relation("recordedBy")
  importJobs       ImportJob[]
  notes            MemberNote[]
}

model GymSettings {
  id                   Int      @id @default(1)   // singleton row
  gymName              String   @default("Rich Man Fitness")
  logoUrl              String?
  phone                String?
  whatsappPhone        String?
  email                String?
  address              String?
  openingHours         String?
  currency             String   @default("PKR")   // ISO code; drives lib/currency formatter
  receiptPrefix        String   @default("RMF")
  receiptFooterMessage String   @default("Thank you for choosing Rich Man Fitness.")
  updatedAt            DateTime @updatedAt
}

model Section {                                    // Boys / Girls / Night Shift / future branches
  id          String   @id @default(uuid())
  name        String   @unique
  description String?
  isActive    Boolean  @default(true)
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
  members     Member[]
}

model MembershipPlan {
  id             String   @id @default(uuid())
  name           String                            // Monthly, Quarterly, 6 Months, Annual
  description    String?
  durationMonths Int
  price          Decimal  @db.Decimal(10, 2)
  isActive       Boolean  @default(true)
  createdAt      DateTime @default(now())
  updatedAt      DateTime @updatedAt
  memberships    Membership[]
}

model Member {
  id               String    @id @default(uuid())
  memberCode       Int       @unique                // human-friendly Member ID (from Excel "Enroll." or auto-assigned)
  fullName         String
  phone            String                            // normalized E.164 (libphonenumber-js)
  phoneRaw         String?                           // as originally entered/imported
  email            String?
  gender           String?
  dateOfBirth      DateTime?
  address          String?
  emergencyContact String?
  joiningDate      DateTime
  sectionId        String?
  section          Section?  @relation(fields: [sectionId], references: [id])
  deactivatedAt    DateTime?                          // soft-deactivate; never hard-deleted
  createdAt        DateTime  @default(now())
  updatedAt        DateTime  @updatedAt
  memberships      Membership[]
  payments         Payment[]
  notes            MemberNote[]

  @@index([fullName])
  @@index([phone])
}

model Membership {                                   // one row per plan enrollment; plan changes close old row (history)
  id          String     @id @default(uuid())
  memberId    String
  member      Member     @relation(fields: [memberId], references: [id])
  planId      String
  plan        MembershipPlan @relation(fields: [planId], references: [id])
  feeOverride Decimal?   @db.Decimal(10, 2)          // custom member pricing
  startDate   DateTime
  endDate     DateTime?                               // null = currently active enrollment
  createdAt   DateTime   @default(now())
  updatedAt   DateTime   @updatedAt
  periods     MembershipPeriod[]

  @@index([memberId])
}

model MembershipPeriod {                             // one row per billing cycle == one month column in the ledger
  id             String     @id @default(uuid())
  membershipId   String
  membership     Membership @relation(fields: [membershipId], references: [id])
  periodStart    DateTime                             // first day of cycle, e.g. 2026-08-01
  periodEnd      DateTime                             // computed from plan cadence at creation time
  expectedAmount Decimal    @db.Decimal(10, 2)         // fee snapshot at creation time
  createdAt      DateTime   @default(now())
  updatedAt      DateTime   @updatedAt
  payments       Payment[]
  // paid/due is DERIVED (does a non-voided Payment exist?) — never a manually edited flag

  @@unique([membershipId, periodStart])
}

model Payment {
  id                 String            @id @default(uuid())
  memberId           String
  member             Member            @relation(fields: [memberId], references: [id])
  membershipPeriodId String?
  membershipPeriod   MembershipPeriod? @relation(fields: [membershipPeriodId], references: [id])
  amount             Decimal           @db.Decimal(10, 2)
  method             PaymentMethod
  referenceNumber    String?
  paymentDate        DateTime
  notes              String?
  source             PaymentSource     @default(MANUAL)   // MANUAL vs IMPORTED — drives WhatsApp skip
  recordedById       String
  recordedBy         User              @relation("recordedBy", fields: [recordedById], references: [id])
  idempotencyKey     String            @unique             // blocks accidental double-submit
  createdAt          DateTime          @default(now())
  updatedAt          DateTime          @updatedAt
  receipt            Receipt?

  @@index([memberId])
  @@index([paymentDate])
}

model Receipt {
  id               String   @id @default(uuid())
  receiptNumber    String   @unique                  // e.g. RMF-2026-000184
  paymentId        String   @unique
  payment          Payment  @relation(fields: [paymentId], references: [id])
  pngPath          String
  pdfPath          String?
  generatedAt      DateTime @default(now())
  createdAt        DateTime @default(now())
  updatedAt        DateTime @updatedAt
  whatsappMessages WhatsAppMessage[]
}

model ReceiptCounter {                               // atomic per-year sequence, incremented inside the payment transaction
  year       Int @id
  lastNumber Int @default(0)
}

model WhatsAppMessage {                               // retry = new row (attemptNumber+1); full attempt history preserved
  id                String           @id @default(uuid())
  receiptId         String
  receipt           Receipt          @relation(fields: [receiptId], references: [id])
  memberId          String
  phone             String
  provider          WhatsAppProvider
  externalMessageId String?
  status            WhatsAppStatus   @default(QUEUED)
  errorMessage      String?
  attemptNumber     Int              @default(1)
  sentAt            DateTime?
  deliveredAt       DateTime?
  readAt            DateTime?
  failedAt          DateTime?
  createdAt         DateTime         @default(now())
  updatedAt         DateTime         @updatedAt

  @@index([status])
}

model MemberNote {
  id          String   @id @default(uuid())
  memberId    String
  member      Member   @relation(fields: [memberId], references: [id])
  body        String
  createdById String
  createdBy   User     @relation(fields: [createdById], references: [id])
  createdAt   DateTime @default(now())
}

model ImportJob {
  id              String       @id @default(uuid())
  fileName        String
  uploadedById    String
  uploadedBy      User         @relation(fields: [uploadedById], references: [id])
  status          ImportStatus @default(PENDING)
  columnMapping   Json?                                // wizard's column→field mapping, incl. month-column mapping
  totalRows       Int?
  importedCount   Int?
  skippedCount    Int?
  errorCount      Int?
  errorReportPath String?                               // downloadable CSV of rejected/error rows
  createdAt       DateTime     @default(now())
  updatedAt       DateTime     @updatedAt
}
```

### Notable design choices

- **No manually-editable status field.** `MembershipPeriod`/`Membership` status (PAID/DUE/EXPIRED/INACTIVE) is always computed by a `computeMemberStatus()` service function from dates + payment existence, never stored redundantly. This satisfies business rule #8 directly.
- **`idempotencyKey`** on `Payment` is generated client-side (one UUID per form load) and enforced unique at the DB level — the double-submit guard from business rule #3.
- **`ReceiptCounter`** gives atomic, gap-free-per-year receipt numbers even under concurrent submissions (row-locked increment inside the same DB transaction as payment creation).
- **Nothing is hard-deleted.** `Member.deactivatedAt` and immutable `Payment`/`Receipt` rows preserve financial history (business rules #1, #2, #7).
- **`Payment.source`** (`MANUAL` vs `IMPORTED`) is what lets the Excel importer reuse the exact same payment/receipt creation code path while skipping the WhatsApp step for historical rows.

## 5. Route structure

**Public** — `app/(public)/`
```
/                     Landing page (hero, about, facilities, plans, why-us, testimonials, contact, footer)
/admin/login          Admin login
```

**Admin** — `app/admin/` (protected by middleware; redirects to `/admin/login` when unauthenticated)
```
/admin                        Dashboard — metrics, recent payments, quick actions
/admin/members                 Member list — search/filter
/admin/members/import          Excel import wizard
/admin/members/[id]             Member profile — history, notes, record payment
/admin/payments                 Payments log
/admin/receipts                 Receipts log
/admin/membership-plans         Plan CRUD
/admin/whatsapp                 WhatsApp message history
/admin/reports                  Revenue / membership / receipt reports
/admin/settings                 Gym info, receipt settings, WhatsApp status, Sections CRUD
```

**API / route handlers** — `app/api/`
```
/api/auth/[...nextauth]         Auth.js handler
/api/webhooks/whatsapp          Meta status callback (GET verify, POST status updates)
/api/receipts/[id]/file         Protected receipt file serving (auth-checked, never a public static path)
```

Everything else (record payment, member CRUD, import commit, WhatsApp retry) is a **Server Action** calling into `services/` — not a duplicate REST API — to avoid two parallel validation paths for the same operation.

## 6. Folder structure

```
app/
  (public)/page.tsx, layout.tsx
  admin/
    login/page.tsx
    layout.tsx                 sidebar + topbar shell
    page.tsx                    dashboard
    members/page.tsx, import/page.tsx, [id]/page.tsx
    payments/page.tsx
    receipts/page.tsx
    membership-plans/page.tsx
    whatsapp/page.tsx
    reports/page.tsx
    settings/page.tsx
  api/
    auth/[...nextauth]/route.ts
    webhooks/whatsapp/route.ts
    receipts/[id]/file/route.ts

components/
  landing/   Navbar, Hero, About, Facilities, PlanCard, WhyChooseUs, Testimonials, Contact, Footer
  admin/     Sidebar, Topbar, StatCard, PageHeader
  members/   MemberTable, MemberFilters, MemberForm, MemberStatusBadge, ImportWizard/*
  payments/  RecordPaymentDialog, PaymentTable, PaymentFilters
  receipts/  ReceiptPreview, ReceiptActions, ReceiptTemplate (the satori JSX layout)
  whatsapp/  WhatsAppStatusBadge, RetryButton
  ui/        shadcn primitives + composed (DataTable, EmptyState, ConfirmDialog, CurrencyInput, PhoneInput)

lib/
  auth/      Auth.js config, session helpers, password hashing
  db/        Prisma client singleton (server-only)
  validation/ Zod schemas (member, payment, plan, import, settings)
  receipts/  satori render, resvg rasterize, pdf-lib embed, receiptNumber()
  whatsapp/  client.ts, sendReceipt.ts, types.ts, providers/mock.ts, providers/meta.ts
  storage/   interface + local-disk provider (+ S3-compatible provider stub)
  phone/     normalize/validate (libphonenumber-js), default PK, not hardcoded to it
  currency/  format(amount, currencyCode) — PKR "Rs. 3,000" special-cased, Intl fallback otherwise

services/
  payments/  recordPayment.ts, retryWhatsApp.ts
  members/   createMember.ts, computeMemberStatus.ts, deactivateMember.ts
  import/    parseWorkbook.ts, pivotLedgerRows.ts, validateRows.ts, commitImport.ts
  reports/   revenue.ts, membershipBreakdown.ts, receiptStats.ts

prisma/      schema.prisma, seed.ts, migrations/
types/       shared DTOs not owned by Prisma (ImportPreviewRow, DashboardStats, …)
```

## 7. Payment → Receipt → WhatsApp workflow

```
Admin clicks "Confirm Payment"
  1. Validate form (Zod) + idempotency key blocks accidental double-submit
  2. DB transaction:
       - create Payment row
       - resolve/create MembershipPeriod
       - atomically increment ReceiptCounter → unique receipt number (RMF-2026-000184)
  3. Render receipt: satori (JSX→SVG) → resvg (SVG→PNG) → pdf-lib embeds PNG into a 1-page PDF
  4. Save both files via storage abstraction; save Receipt row
  ── transaction commits here — payment + receipt are durably saved regardless of what follows ──
  5a. "Send on WhatsApp" checked → call lib/whatsapp (mock or meta)
        → save WhatsAppMessage(status, externalId)
        → UI: ✓ Payment saved · ✓ Receipt generated · ✓ WhatsApp sent
  5b. WhatsApp call fails → WhatsAppMessage saved with status=FAILED + error
        → UI: ✓ Payment saved · ✓ Receipt generated · ✕ WhatsApp failed [Retry WhatsApp]
        → Payment is never rolled back
```

Retry creates a **new** `WhatsAppMessage` row (`attemptNumber + 1`) rather than mutating the old one, preserving full attempt history.

**Excel import reuses this exact same core** (`recordPayment` service, called once per historical month-cell) but always with `sendWhatsApp: false` / `source: IMPORTED` — no WhatsApp spam for years-old cash payments already collected before this system existed.

## 8. Excel import — wide ledger format

The owner's real sheet (**"RICH MAN FITNESS LEDGER"**, tab "Entry Book (Boys)", plus "Fee Detail 2024/2026" and "Night Shift 2026") is a wide format, not flat rows:

| Column | Maps to |
|---|---|
| Enroll. | `Member.memberCode` |
| Name | `Member.fullName` |
| Contact Detail | `Member.phone` (normalized) |
| Fee Submit | Most recent payment date (informational; superseded by actual per-month data below) |
| Jan … Dec | One `MembershipPeriod` + `Payment` per month where the cell has a value > 0 for that year-sheet; blank/`0`/`NILL` = no payment that month |
| Ref No: | `Payment.referenceNumber` |
| Status (Online/Cash Payment) | `Payment.method` — "Online Payment" maps to `OTHER` by default (editable in the mapping step), "Cash Payment" → `CASH` |
| Extra Add, | `MemberNote.body` |
| (sheet name / tab) | `Member.section` — "Entry Book (Boys)" → Section "Boys"; "Night Shift 2026" → Section "Night Shift" |

Import wizard steps (per original brief, extended for the wide format):

1. Upload `.xlsx`/`.csv`, select which sheet(s)/tabs to import.
2. Detect columns, **including the Jan–Dec block**, and detect the sheet's year (from sheet name or an explicit year input).
3. Map columns → fields (Name, Phone, Fee Submit, Ref No, Status/Method, Extra Add/Notes) and confirm the month-column block + year.
4. Preview: show first rows **pivoted** — i.e., preview what payment/period records each row will generate, not just the raw row.
5. Validate: empty names, invalid phones, duplicate members (by phone or memberCode), invalid dates, invalid fees; flag rows needing attention.
6. Commit: for each valid month-cell, create (or reuse) the `Membership` → `MembershipPeriod` → `Payment` chain with `source: IMPORTED`, `sendWhatsApp: false`. Summary shown: "N members imported, N periods backfilled, N duplicates skipped, N rows need attention," with a downloadable CSV of rejected rows.

Importing the same file/sheet twice must not duplicate periods — enforced by the `@@unique([membershipId, periodStart])` constraint plus a pre-check in `commitImport`.

## 9. Visual identity

**Crimson & Steel**: near-black backgrounds (`#0b0b0d`), crimson-red accent (`#e11d2e`), white/off-white type, dark steel-gray secondary surfaces. Strong, minimal, premium fitness feel — pairs cleanly with a PAID(green)/DUE(amber)/EXPIRED(red) badge system in the admin without clashing with the brand accent.

Receipt: vertical, phone-width (≈280–320px design width) card. Fields top-to-bottom: gym name, "PAYMENT RECEIPT" label, receipt #, date, member name + member code, membership plan + section, billing period, payment method (+ reference number only when applicable), a highlighted amount block with a PAID badge, thank-you footer. See mockup captured during brainstorming (`.superpowers/brainstorm/…/content/02-visual-style.html`, not committed — local only).

## 10. Implementation phases

1. **Foundation** — project init, Docker Compose Postgres, Prisma schema + migration, Auth.js login, admin shell layout (sidebar/topbar, Crimson & Steel theme), public landing page skeleton.
2. **Core data** — Membership plans, Sections, Members CRUD, member profile, search/filter.
3. **Payments** — record payment, MembershipPeriod derivation, payment history, status computation (`computeMemberStatus`).
4. **Receipts** — satori/resvg PNG, pdf-lib PDF, receipt history page.
5. **WhatsApp** — provider abstraction, mock provider, retry flow, Meta provider (credential-ready but unused until real credentials exist), webhook.
6. **Excel import** — wizard UI, wide-ledger pivot parser, validation, historical backfill (no WhatsApp), error report download.
7. **Reports, Settings, polish** — reports + CSV export, Settings (incl. Sections CRUD, receipt/WhatsApp config display), mobile responsiveness pass, tests.

Each phase ends in a runnable application (per the original brief's explicit instruction not to generate the whole app as one untested dump).

## 11. Out of scope / explicitly deferred

- STAFF role UI (schema supports it via `Role` enum; no STAFF-specific screens built now).
- Real Meta WhatsApp credentials/integration testing (built and ready, not exercised until credentials exist).
- Cloud file storage (S3/Cloudinary) wiring — abstraction exists, local-disk provider used until production deployment target is chosen.
- Multi-currency UI beyond the formatter abstraction (PKR is the only currency actually used).
- Partial payments / a payment covering multiple `MembershipPeriod`s at once.

## 12. Open items for the owner (non-blocking)

- Confirm exact sheet names/years available (e.g. is there a "Fee Detail 2025"? An "Entry Book (Girls)"?) before Phase 6 implementation — the ledger photo showed tabs scrolled partially out of view.
- Confirm what a month cell contains when a member pays a **different amount than usual** that month (partial payment, discount) — currently assumed the cell amount is authoritative per month regardless of the plan's standard price.
