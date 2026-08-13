# Phase 1: Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a running Next.js + PostgreSQL application with the complete database schema, working admin authentication, the admin dashboard shell, and the public landing page.

**Architecture:** Single Next.js 15 App Router application. Server Actions and route handlers stay thin — they validate with Zod and delegate to `services/`. Prisma lives behind a `server-only` singleton in `lib/db` and is never imported into a client component. Auth.js v5 uses a split config so edge middleware can gate `/admin/*` without pulling Node-only dependencies (bcrypt, Prisma) into the edge runtime.

**Tech Stack:** Next.js 15 (App Router), React 19, TypeScript (strict), Tailwind CSS v4, shadcn/ui, PostgreSQL 16 (Docker Compose), Prisma 6, Auth.js v5 (`next-auth@beta`), Zod, bcryptjs, libphonenumber-js, Vitest.

**Reference spec:** [`docs/superpowers/specs/2026-08-12-gym-management-design.md`](../specs/2026-08-12-gym-management-design.md)

> **Note on commits:** The user has asked that nothing be committed. Each task therefore ends with a **verification checkpoint** instead of a `git commit` step. Every checkpoint is a natural commit boundary if commits are re-enabled later.

---

## File Structure

Files created in this phase, and what each owns:

| File | Responsibility |
|---|---|
| `docker-compose.yml` | Local PostgreSQL 16 container on port 5433 |
| `.env.example` / `.env` | Environment variable contract / local values |
| `prisma/schema.prisma` | Complete database schema (all models, all phases) |
| `prisma/seed.ts` | Admin user, GymSettings singleton, Sections, MembershipPlans |
| `lib/db/index.ts` | Prisma client singleton, `server-only` |
| `lib/currency/format.ts` | `formatCurrency(amount, currencyCode)` — PKR-aware, not hardcoded |
| `lib/phone/normalize.ts` | E.164 normalization/validation, default country PK |
| `lib/auth/password.ts` | bcrypt hash/verify |
| `lib/auth/config.edge.ts` | Edge-safe Auth.js config (route gating, JWT/session callbacks) |
| `lib/auth/index.ts` | Full Auth.js instance with the Credentials provider |
| `lib/auth/actions.ts` | `authenticate` Server Action for the login form |
| `lib/validation/auth.ts` | Zod schema for login credentials |
| `middleware.ts` | Edge route protection for `/admin/*` |
| `types/next-auth.d.ts` | Session/JWT type augmentation (adds `id`, `role`) |
| `app/api/auth/[...nextauth]/route.ts` | Auth.js route handler |
| `app/globals.css` | Tailwind v4 import + Crimson & Steel theme tokens |
| `app/layout.tsx` | Root layout, fonts, base background |
| `app/admin/login/page.tsx` + `login-form.tsx` | Login screen |
| `app/admin/layout.tsx` | Auth-gated admin shell (sidebar + topbar) |
| `app/admin/page.tsx` | Phase 1 dashboard placeholder |
| `components/admin/nav-items.ts` | Single source of truth for sidebar nav (items enabled per phase) |
| `components/admin/sidebar.tsx` / `topbar.tsx` | Admin chrome, responsive |
| `components/landing/*.tsx` | Navbar, Hero, About, Facilities, WhyChooseUs, Contact, Footer |
| `app/(public)/page.tsx` | Landing page composition |
| `vitest.config.ts` | Test runner config with `@/*` alias |

---

## Task 1: Scaffold the Next.js project and test tooling

**Files:**
- Create: entire Next.js scaffold at project root
- Create: `vitest.config.ts`
- Modify: `package.json`, `.gitignore`

- [ ] **Step 1: Scaffold Next.js into a temp directory**

`create-next-app` refuses to write into a directory containing unrecognised files (our `Gym Management Code Prompt.md`, `.superpowers/`), so scaffold beside the project and move the files in. `--skip-install` keeps `node_modules` out of the copy.

```bash
cd /Users/mac/StudioProjects/project-folder
npx create-next-app@latest rmf-scaffold \
  --typescript --tailwind --eslint --app \
  --no-src-dir --import-alias "@/*" --use-npm --skip-install --yes
```

Expected: `Success! Created rmf-scaffold at ...`

- [ ] **Step 2: Move the scaffold into the project and install**

```bash
cd "/Users/mac/StudioProjects/project-folder/gym app"
rsync -a --exclude '.gitignore' ../rmf-scaffold/ ./
rm -rf ../rmf-scaffold
npm install
```

Expected: `app/`, `public/`, `package.json`, `tsconfig.json`, `next.config.ts` now exist at the project root; `npm install` completes without errors.

- [ ] **Step 3: Confirm TypeScript strict mode is on**

Read `tsconfig.json` and verify `"strict": true` is present under `compilerOptions`. `create-next-app` sets this by default. If it is missing, add it.

- [ ] **Step 4: Append Next.js entries to the existing .gitignore**

Add these lines to the end of `.gitignore` (the file already covers `node_modules/`, `.next/`, `.env`, `.superpowers/`):

```gitignore
# Next.js / TypeScript build artifacts
next-env.d.ts
*.tsbuildinfo
.vercel
*.pem
```

- [ ] **Step 5: Install runtime and dev dependencies**

```bash
npm install @prisma/client zod bcryptjs libphonenumber-js next-auth@beta
npm install -D prisma vitest @types/bcryptjs tsx
```

Expected: all packages install without peer-dependency errors.

- [ ] **Step 6: Create the Vitest config**

Create `vitest.config.ts`:

```ts
import path from "node:path"
import { defineConfig } from "vitest/config"

export default defineConfig({
  test: {
    environment: "node",
    include: ["**/*.test.ts"],
    exclude: ["node_modules/**", ".next/**"],
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "."),
    },
  },
})
```

- [ ] **Step 7: Add scripts to package.json**

Replace the `"scripts"` block in `package.json` with:

```json
"scripts": {
  "dev": "next dev",
  "build": "next build",
  "start": "next start",
  "lint": "eslint",
  "typecheck": "tsc --noEmit",
  "test": "vitest run",
  "test:watch": "vitest",
  "db:up": "docker compose up -d",
  "db:down": "docker compose down",
  "db:migrate": "prisma migrate dev",
  "db:reset": "prisma migrate reset",
  "db:seed": "prisma db seed",
  "db:studio": "prisma studio"
},
"prisma": {
  "seed": "tsx prisma/seed.ts"
}
```

- [ ] **Step 8: Write a smoke test proving the test runner works**

Create `lib/smoke.test.ts`:

```ts
import { describe, expect, it } from "vitest"

describe("test runner", () => {
  it("runs", () => {
    expect(1 + 1).toBe(2)
  })
})
```

- [ ] **Step 9: Run the test suite**

Run: `npm test`
Expected: PASS — `1 passed (1)`

- [ ] **Step 10: Delete the smoke test**

```bash
rm lib/smoke.test.ts
```

It has served its purpose; real tests follow in Tasks 4–6.

- [ ] **Step 11: Verification checkpoint**

Run: `npm run typecheck && npm run lint`
Expected: no TypeScript errors, no lint errors.

---

## Task 2: PostgreSQL via Docker Compose and environment variables

**Files:**
- Create: `docker-compose.yml`
- Create: `.env.example`
- Create: `.env`

- [ ] **Step 1: Create docker-compose.yml**

Port **5433** is used deliberately so the container does not collide with any PostgreSQL already listening on 5432.

```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: rmf-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: rmf
      POSTGRES_PASSWORD: rmf_dev_password
      POSTGRES_DB: rmf_gym
    ports:
      - "5433:5432"
    volumes:
      - rmf-pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U rmf -d rmf_gym"]
      interval: 5s
      timeout: 5s
      retries: 10

volumes:
  rmf-pgdata:
```

- [ ] **Step 2: Create .env.example**

This file is committed and contains **no real secrets** — placeholders only.

```bash
# ---- Database ----
DATABASE_URL="postgresql://rmf:rmf_dev_password@localhost:5433/rmf_gym?schema=public"

# ---- Auth ----
# Generate with: openssl rand -base64 32
AUTH_SECRET="replace-me-with-a-random-32-byte-base64-string"

# ---- Seed admin account (development only) ----
ADMIN_EMAIL="admin@richmanfitness.local"
ADMIN_PASSWORD="replace-me-with-a-strong-password"
ADMIN_NAME="Gym Owner"

# ---- WhatsApp ----
# mock = no Meta credentials needed (default for development)
# meta = live Meta WhatsApp Business Cloud API
WHATSAPP_PROVIDER="mock"
WHATSAPP_PHONE_NUMBER_ID=""
WHATSAPP_BUSINESS_ACCOUNT_ID=""
WHATSAPP_ACCESS_TOKEN=""
WHATSAPP_WEBHOOK_VERIFY_TOKEN=""

# ---- Storage ----
# local = write receipt files to ./storage on disk
STORAGE_PROVIDER="local"
STORAGE_LOCAL_DIR="./storage"

# ---- App ----
NEXT_PUBLIC_APP_URL="http://localhost:3000"
```

- [ ] **Step 3: Create the local .env**

```bash
cp .env.example .env
```

Then edit `.env` and replace the two placeholder values:

```bash
# Generate the auth secret and print it:
openssl rand -base64 32
```

Set `AUTH_SECRET` to that output, and set `ADMIN_PASSWORD` to a password of at least 8 characters (for example `RichMan#2026`). `.env` is already gitignored.

- [ ] **Step 4: Start the database**

```bash
npm run db:up
```

Expected: `Container rmf-postgres  Started`

- [ ] **Step 5: Verify the database is accepting connections**

```bash
docker exec rmf-postgres pg_isready -U rmf -d rmf_gym
```

Expected: `/var/run/postgresql:5432 - accepting connections`

- [ ] **Step 6: Verification checkpoint**

```bash
docker compose ps
```

Expected: `rmf-postgres` shows status `Up` and `(healthy)`.

---

## Task 3: Prisma schema, migration, and client singleton

**Files:**
- Create: `prisma/schema.prisma`
- Create: `lib/db/index.ts`

The full schema for **all** phases is created now. Later phases add queries against these models, not new migrations — this avoids a migration churn per phase.

- [ ] **Step 1: Initialize Prisma**

```bash
npx prisma init --datasource-provider postgresql
```

Expected: creates `prisma/schema.prisma`. It also appends a `DATABASE_URL` line to `.env` — **delete that duplicate line**, keeping the one already written in Task 2.

- [ ] **Step 2: Write the complete schema**

Replace the entire contents of `prisma/schema.prisma`:

```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

enum Role {
  ADMIN
  STAFF
}

enum PaymentMethod {
  CASH
  BANK_TRANSFER
  EASYPAISA
  JAZZCASH
  CARD
  OTHER
}

enum PaymentSource {
  MANUAL
  IMPORTED
}

enum WhatsAppStatus {
  QUEUED
  SENT
  DELIVERED
  READ
  FAILED
}

enum WhatsAppProvider {
  MOCK
  META
}

enum ImportStatus {
  PENDING
  VALIDATED
  COMMITTED
  FAILED
}

model User {
  id               String       @id @default(uuid())
  name             String
  email            String       @unique
  passwordHash     String
  role             Role         @default(ADMIN)
  createdAt        DateTime     @default(now())
  updatedAt        DateTime     @updatedAt
  paymentsRecorded Payment[]    @relation("recordedBy")
  importJobs       ImportJob[]
  notes            MemberNote[]
}

model GymSettings {
  id                   Int      @id @default(1)
  gymName              String   @default("Rich Man Fitness")
  logoUrl              String?
  phone                String?
  whatsappPhone        String?
  email                String?
  address              String?
  openingHours         String?
  currency             String   @default("PKR")
  receiptPrefix        String   @default("RMF")
  receiptFooterMessage String   @default("Thank you for choosing Rich Man Fitness.")
  updatedAt            DateTime @updatedAt
}

model Section {
  id          String   @id @default(uuid())
  name        String   @unique
  description String?
  isActive    Boolean  @default(true)
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
  members     Member[]
}

model MembershipPlan {
  id             String       @id @default(uuid())
  name           String
  description    String?
  durationMonths Int
  price          Decimal      @db.Decimal(10, 2)
  isActive       Boolean      @default(true)
  createdAt      DateTime     @default(now())
  updatedAt      DateTime     @updatedAt
  memberships    Membership[]
}

model Member {
  id               String       @id @default(uuid())
  memberCode       Int          @unique
  fullName         String
  phone            String
  phoneRaw         String?
  email            String?
  gender           String?
  dateOfBirth      DateTime?
  address          String?
  emergencyContact String?
  joiningDate      DateTime
  sectionId        String?
  section          Section?     @relation(fields: [sectionId], references: [id])
  deactivatedAt    DateTime?
  createdAt        DateTime     @default(now())
  updatedAt        DateTime     @updatedAt
  memberships      Membership[]
  payments         Payment[]
  notes            MemberNote[]

  @@index([fullName])
  @@index([phone])
}

model Membership {
  id          String             @id @default(uuid())
  memberId    String
  member      Member             @relation(fields: [memberId], references: [id])
  planId      String
  plan        MembershipPlan     @relation(fields: [planId], references: [id])
  feeOverride Decimal?           @db.Decimal(10, 2)
  startDate   DateTime
  endDate     DateTime?
  createdAt   DateTime           @default(now())
  updatedAt   DateTime           @updatedAt
  periods     MembershipPeriod[]

  @@index([memberId])
}

model MembershipPeriod {
  id             String     @id @default(uuid())
  membershipId   String
  membership     Membership @relation(fields: [membershipId], references: [id])
  periodStart    DateTime
  periodEnd      DateTime
  expectedAmount Decimal    @db.Decimal(10, 2)
  createdAt      DateTime   @default(now())
  updatedAt      DateTime   @updatedAt
  payments       Payment[]

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
  source             PaymentSource     @default(MANUAL)
  recordedById       String
  recordedBy         User              @relation("recordedBy", fields: [recordedById], references: [id])
  idempotencyKey     String            @unique
  createdAt          DateTime          @default(now())
  updatedAt          DateTime          @updatedAt
  receipt            Receipt?

  @@index([memberId])
  @@index([paymentDate])
}

model Receipt {
  id               String            @id @default(uuid())
  receiptNumber    String            @unique
  paymentId        String            @unique
  payment          Payment           @relation(fields: [paymentId], references: [id])
  pngPath          String
  pdfPath          String?
  generatedAt      DateTime          @default(now())
  createdAt        DateTime          @default(now())
  updatedAt        DateTime          @updatedAt
  whatsappMessages WhatsAppMessage[]
}

model ReceiptCounter {
  year       Int @id
  lastNumber Int @default(0)
}

model WhatsAppMessage {
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
  columnMapping   Json?
  totalRows       Int?
  importedCount   Int?
  skippedCount    Int?
  errorCount      Int?
  errorReportPath String?
  createdAt       DateTime     @default(now())
  updatedAt       DateTime     @updatedAt
}
```

- [ ] **Step 3: Create the initial migration**

```bash
npx prisma migrate dev --name init
```

Expected: `Your database is now in sync with your schema.` and a new folder under `prisma/migrations/`.

- [ ] **Step 4: Verify the tables exist**

```bash
docker exec rmf-postgres psql -U rmf -d rmf_gym -c "\dt"
```

Expected: a table list including `User`, `Member`, `Payment`, `Receipt`, `WhatsAppMessage`, `ImportJob`, `Section`, `MembershipPlan`, `Membership`, `MembershipPeriod`, `ReceiptCounter`, `GymSettings`, `MemberNote`.

- [ ] **Step 5: Create the Prisma client singleton**

Next.js dev-mode hot reload re-executes modules, which would otherwise open a new connection pool on every reload. Create `lib/db/index.ts`:

```ts
import "server-only"

import { PrismaClient } from "@prisma/client"

const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined
}

export const prisma =
  globalForPrisma.prisma ??
  new PrismaClient({
    log: process.env.NODE_ENV === "development" ? ["warn", "error"] : ["error"],
  })

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = prisma
}
```

- [ ] **Step 6: Install the server-only guard package**

```bash
npm install server-only
```

This makes any accidental import of `lib/db` from a client component a **build-time error** rather than a silent security problem.

- [ ] **Step 7: Verification checkpoint**

Run: `npm run typecheck`
Expected: no errors.

---

## Task 4: Currency formatter (TDD)

**Files:**
- Create: `lib/currency/format.ts`
- Test: `lib/currency/format.test.ts`

Currency must not be hardcoded to PKR (spec requirement), but PKR must render as `Rs. 3,000` rather than `Intl`'s default `PKR 3,000.00`.

- [ ] **Step 1: Write the failing test**

Create `lib/currency/format.test.ts`:

```ts
import { describe, expect, it } from "vitest"

import { formatCurrency } from "@/lib/currency/format"

describe("formatCurrency", () => {
  it("formats PKR by default as Rs. with thousands separators and no decimals", () => {
    expect(formatCurrency(3000)).toBe("Rs. 3,000")
  })

  it("formats PKR explicitly the same way", () => {
    expect(formatCurrency(3000, "PKR")).toBe("Rs. 3,000")
  })

  it("shows two decimals for PKR only when the amount is fractional", () => {
    expect(formatCurrency(3000.5, "PKR")).toBe("Rs. 3,000.50")
  })

  it("formats zero", () => {
    expect(formatCurrency(0, "PKR")).toBe("Rs. 0")
  })

  it("groups large PKR amounts", () => {
    expect(formatCurrency(1234567, "PKR")).toBe("Rs. 1,234,567")
  })

  it("falls back to Intl formatting for other currencies", () => {
    expect(formatCurrency(3000, "USD")).toBe("$3,000.00")
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run lib/currency/format.test.ts`
Expected: FAIL — `Failed to resolve import "@/lib/currency/format"`

- [ ] **Step 3: Write the implementation**

Create `lib/currency/format.ts`:

```ts
/**
 * Currencies whose default Intl rendering we override.
 * PKR would otherwise render as "PKR 3,000.00"; the gym uses "Rs. 3,000".
 */
const SYMBOL_OVERRIDES: Record<string, string> = {
  PKR: "Rs.",
}

export const DEFAULT_CURRENCY = "PKR"

export function formatCurrency(
  amount: number,
  currency: string = DEFAULT_CURRENCY,
): string {
  const symbol = SYMBOL_OVERRIDES[currency]

  if (symbol) {
    const fractionDigits = Number.isInteger(amount) ? 0 : 2
    const formatted = new Intl.NumberFormat("en-US", {
      minimumFractionDigits: fractionDigits,
      maximumFractionDigits: fractionDigits,
    }).format(amount)
    return `${symbol} ${formatted}`
  }

  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
  }).format(amount)
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx vitest run lib/currency/format.test.ts`
Expected: PASS — `6 passed (6)`

- [ ] **Step 5: Verification checkpoint**

Run: `npm run typecheck`
Expected: no errors.

---

## Task 5: Phone normalization (TDD)

**Files:**
- Create: `lib/phone/normalize.ts`
- Test: `lib/phone/normalize.test.ts`

Phone numbers in the owner's ledger look like `0324-4366258`. WhatsApp requires E.164 (`+923244366258`). Pakistan is the default country, but explicit international numbers must still work (spec requirement).

- [ ] **Step 1: Write the failing test**

Create `lib/phone/normalize.test.ts`:

```ts
import { describe, expect, it } from "vitest"

import { isValidPhone, normalizePhone } from "@/lib/phone/normalize"

describe("normalizePhone", () => {
  it("normalizes a hyphenated Pakistani mobile number from the ledger", () => {
    expect(normalizePhone("0324-4366258")).toBe("+923244366258")
  })

  it("normalizes a space-separated Pakistani number", () => {
    expect(normalizePhone("0324 4366258")).toBe("+923244366258")
  })

  it("normalizes an unformatted Pakistani number", () => {
    expect(normalizePhone("03244366258")).toBe("+923244366258")
  })

  it("normalizes a number already in international form", () => {
    expect(normalizePhone("+92 324 4366258")).toBe("+923244366258")
  })

  it("trims surrounding whitespace", () => {
    expect(normalizePhone("  0324-4366258  ")).toBe("+923244366258")
  })

  it("returns null for empty input", () => {
    expect(normalizePhone("")).toBeNull()
    expect(normalizePhone(null)).toBeNull()
    expect(normalizePhone(undefined)).toBeNull()
  })

  it("returns null for a number that is too short to be valid", () => {
    expect(normalizePhone("12")).toBeNull()
  })

  it("returns null for non-numeric junk", () => {
    expect(normalizePhone("NILL")).toBeNull()
  })

  it("honours an explicit international prefix over the default country", () => {
    expect(normalizePhone("+1 415 555 2671")).toBe("+14155552671")
  })

  it("accepts an overridden default country", () => {
    expect(normalizePhone("415 555 2671", "US")).toBe("+14155552671")
  })
})

describe("isValidPhone", () => {
  it("is true for a valid number", () => {
    expect(isValidPhone("0324-4366258")).toBe(true)
  })

  it("is false for an invalid number", () => {
    expect(isValidPhone("NILL")).toBe(false)
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run lib/phone/normalize.test.ts`
Expected: FAIL — `Failed to resolve import "@/lib/phone/normalize"`

- [ ] **Step 3: Write the implementation**

Create `lib/phone/normalize.ts`:

```ts
import { parsePhoneNumberFromString, type CountryCode } from "libphonenumber-js"

/** Pakistan is the initial market, but callers may override per-member. */
export const DEFAULT_COUNTRY: CountryCode = "PK"

/**
 * Converts a raw, human-entered phone number into E.164 form (+923244366258).
 * Returns null when the input is missing or cannot be parsed as a valid number.
 */
export function normalizePhone(
  raw: string | null | undefined,
  country: CountryCode = DEFAULT_COUNTRY,
): string | null {
  if (!raw) return null

  const trimmed = raw.trim()
  if (trimmed.length === 0) return null

  const parsed = parsePhoneNumberFromString(trimmed, country)
  if (!parsed || !parsed.isValid()) return null

  return parsed.number
}

export function isValidPhone(
  raw: string | null | undefined,
  country: CountryCode = DEFAULT_COUNTRY,
): boolean {
  return normalizePhone(raw, country) !== null
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx vitest run lib/phone/normalize.test.ts`
Expected: PASS — `12 passed (12)`

- [ ] **Step 5: Verification checkpoint**

Run: `npm run typecheck`
Expected: no errors.

---

## Task 6: Password hashing (TDD)

**Files:**
- Create: `lib/auth/password.ts`
- Test: `lib/auth/password.test.ts`

`bcryptjs` is used rather than `bcrypt` because it is pure JavaScript — no native build step, which keeps Docker and CI simple.

- [ ] **Step 1: Write the failing test**

Create `lib/auth/password.test.ts`:

```ts
import { describe, expect, it } from "vitest"

import { hashPassword, verifyPassword } from "@/lib/auth/password"

describe("hashPassword", () => {
  it("does not return the plaintext password", async () => {
    const hash = await hashPassword("RichMan#2026")
    expect(hash).not.toBe("RichMan#2026")
  })

  it("returns a bcrypt hash", async () => {
    const hash = await hashPassword("RichMan#2026")
    expect(hash.startsWith("$2")).toBe(true)
  })

  it("produces a different hash each time (random salt)", async () => {
    const a = await hashPassword("RichMan#2026")
    const b = await hashPassword("RichMan#2026")
    expect(a).not.toBe(b)
  })

  it("rejects passwords shorter than 8 characters", async () => {
    await expect(hashPassword("short")).rejects.toThrow(
      "Password must be at least 8 characters",
    )
  })
})

describe("verifyPassword", () => {
  it("accepts the correct password", async () => {
    const hash = await hashPassword("RichMan#2026")
    expect(await verifyPassword("RichMan#2026", hash)).toBe(true)
  })

  it("rejects an incorrect password", async () => {
    const hash = await hashPassword("RichMan#2026")
    expect(await verifyPassword("WrongPassword", hash)).toBe(false)
  })

  it("rejects an empty password", async () => {
    const hash = await hashPassword("RichMan#2026")
    expect(await verifyPassword("", hash)).toBe(false)
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run lib/auth/password.test.ts`
Expected: FAIL — `Failed to resolve import "@/lib/auth/password"`

- [ ] **Step 3: Write the implementation**

Create `lib/auth/password.ts`:

```ts
import bcrypt from "bcryptjs"

const SALT_ROUNDS = 10
export const MIN_PASSWORD_LENGTH = 8

export async function hashPassword(plain: string): Promise<string> {
  if (plain.length < MIN_PASSWORD_LENGTH) {
    throw new Error(
      `Password must be at least ${MIN_PASSWORD_LENGTH} characters`,
    )
  }
  return bcrypt.hash(plain, SALT_ROUNDS)
}

export async function verifyPassword(
  plain: string,
  hash: string,
): Promise<boolean> {
  if (!plain || !hash) return false
  return bcrypt.compare(plain, hash)
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx vitest run lib/auth/password.test.ts`
Expected: PASS — `7 passed (7)`

- [ ] **Step 5: Run the whole suite**

Run: `npm test`
Expected: PASS — 3 test files, 25 tests passing.

- [ ] **Step 6: Verification checkpoint**

Run: `npm run typecheck && npm run lint`
Expected: no errors.

---

## Task 7: Auth.js configuration, route handler, and middleware

**Files:**
- Create: `lib/validation/auth.ts`
- Create: `lib/auth/config.edge.ts`
- Create: `lib/auth/index.ts`
- Create: `types/next-auth.d.ts`
- Create: `app/api/auth/[...nextauth]/route.ts`
- Create: `middleware.ts`

The config is **split in two** on purpose. `middleware.ts` runs on the edge runtime, which cannot execute bcrypt or Prisma. `config.edge.ts` holds only route-gating logic and callbacks; `index.ts` adds the Credentials provider (which does touch Prisma and bcrypt) and is imported only from Node-runtime code.

- [ ] **Step 1: Create the login validation schema**

Create `lib/validation/auth.ts`:

```ts
import { z } from "zod"

export const loginSchema = z.object({
  email: z.string().email("Enter a valid email address"),
  password: z.string().min(1, "Password is required"),
})

export type LoginInput = z.infer<typeof loginSchema>
```

- [ ] **Step 2: Create the edge-safe auth config**

Create `lib/auth/config.edge.ts`:

```ts
import type { NextAuthConfig } from "next-auth"

/**
 * Edge-safe portion of the Auth.js configuration.
 * Contains NO providers — the Credentials provider needs Prisma and bcrypt,
 * neither of which can run in the edge runtime that powers middleware.
 */
export const authConfig = {
  pages: {
    signIn: "/admin/login",
  },
  session: {
    strategy: "jwt",
  },
  callbacks: {
    authorized({ auth, request: { nextUrl } }) {
      const isLoggedIn = Boolean(auth?.user)
      const isOnLogin = nextUrl.pathname === "/admin/login"
      const isOnAdmin = nextUrl.pathname.startsWith("/admin")

      if (isOnLogin) {
        // Already signed in? Skip the login screen.
        if (isLoggedIn) {
          return Response.redirect(new URL("/admin", nextUrl))
        }
        return true
      }

      if (isOnAdmin) {
        return isLoggedIn
      }

      return true
    },
    jwt({ token, user }) {
      if (user) {
        token.id = user.id as string
        token.role = user.role
      }
      return token
    },
    session({ session, token }) {
      session.user.id = token.id
      session.user.role = token.role
      return session
    },
  },
  providers: [],
} satisfies NextAuthConfig
```

- [ ] **Step 3: Augment the Auth.js types**

Without this, `session.user.role` is a type error. Create `types/next-auth.d.ts`:

```ts
import type { Role } from "@prisma/client"
import type { DefaultSession } from "next-auth"

declare module "next-auth" {
  interface Session {
    user: {
      id: string
      role: Role
    } & DefaultSession["user"]
  }

  interface User {
    role: Role
  }
}

declare module "next-auth/jwt" {
  interface JWT {
    id: string
    role: Role
  }
}
```

- [ ] **Step 4: Create the full auth instance**

Create `lib/auth/index.ts`:

```ts
import NextAuth from "next-auth"
import Credentials from "next-auth/providers/credentials"

import { authConfig } from "@/lib/auth/config.edge"
import { verifyPassword } from "@/lib/auth/password"
import { prisma } from "@/lib/db"
import { loginSchema } from "@/lib/validation/auth"

export const { handlers, auth, signIn, signOut } = NextAuth({
  ...authConfig,
  providers: [
    Credentials({
      credentials: {
        email: { label: "Email", type: "email" },
        password: { label: "Password", type: "password" },
      },
      async authorize(credentials) {
        const parsed = loginSchema.safeParse(credentials)
        if (!parsed.success) return null

        const { email, password } = parsed.data

        const user = await prisma.user.findUnique({
          where: { email: email.toLowerCase() },
        })
        if (!user) return null

        const passwordMatches = await verifyPassword(password, user.passwordHash)
        if (!passwordMatches) return null

        return {
          id: user.id,
          name: user.name,
          email: user.email,
          role: user.role,
        }
      },
    }),
  ],
})
```

- [ ] **Step 5: Create the Auth.js route handler**

Create `app/api/auth/[...nextauth]/route.ts`:

```ts
import { handlers } from "@/lib/auth"

export const { GET, POST } = handlers
```

- [ ] **Step 6: Create the middleware**

Create `middleware.ts` at the project root:

```ts
import NextAuth from "next-auth"

import { authConfig } from "@/lib/auth/config.edge"

export default NextAuth(authConfig).auth

export const config = {
  matcher: ["/admin/:path*"],
}
```

- [ ] **Step 7: Verification checkpoint**

Run: `npm run typecheck`
Expected: no errors. If `Role` cannot be imported from `@prisma/client`, run `npx prisma generate` and re-run.

---

## Task 8: Seed script

**Files:**
- Create: `prisma/seed.ts`

Phase 1 seeds only what Phase 1 exercises: the admin user, the settings singleton, Sections (from the real ledger's sheets), and MembershipPlans. Test **members** and historical payments are seeded in Phase 2, where the Member model gets its UI.

- [ ] **Step 1: Write the seed script**

Create `prisma/seed.ts`:

```ts
import { PrismaClient } from "@prisma/client"

import { hashPassword } from "../lib/auth/password"

const prisma = new PrismaClient()

async function main() {
  const adminEmail = process.env.ADMIN_EMAIL
  const adminPassword = process.env.ADMIN_PASSWORD
  const adminName = process.env.ADMIN_NAME ?? "Gym Owner"

  if (!adminEmail || !adminPassword) {
    throw new Error(
      "ADMIN_EMAIL and ADMIN_PASSWORD must be set in .env before seeding",
    )
  }

  // --- Admin user -----------------------------------------------------------
  const passwordHash = await hashPassword(adminPassword)
  const admin = await prisma.user.upsert({
    where: { email: adminEmail.toLowerCase() },
    update: { name: adminName, passwordHash },
    create: {
      email: adminEmail.toLowerCase(),
      name: adminName,
      passwordHash,
      role: "ADMIN",
    },
  })
  console.log(`Seeded admin user: ${admin.email}`)

  // --- Gym settings singleton ----------------------------------------------
  await prisma.gymSettings.upsert({
    where: { id: 1 },
    update: {},
    create: {
      id: 1,
      gymName: "Rich Man Fitness",
      phone: "+923000000000",
      whatsappPhone: "+923000000000",
      email: "info@richmanfitness.local",
      address: "Main Boulevard, Lahore, Pakistan",
      openingHours: "Mon-Sat: 6:00 AM - 11:00 PM",
      currency: "PKR",
      receiptPrefix: "RMF",
      receiptFooterMessage: "Thank you for choosing Rich Man Fitness.",
    },
  })
  console.log("Seeded gym settings")

  // --- Sections (mirroring the owner's existing ledger sheets) --------------
  const sections = [
    { name: "Boys", description: "Main day-shift roster (Entry Book - Boys)" },
    { name: "Girls", description: "Main day-shift roster (Entry Book - Girls)" },
    { name: "Night Shift", description: "Late-evening batch" },
  ]

  for (const section of sections) {
    await prisma.section.upsert({
      where: { name: section.name },
      update: { description: section.description },
      create: section,
    })
  }
  console.log(`Seeded ${sections.length} sections`)

  // --- Membership plans -----------------------------------------------------
  const plans = [
    {
      name: "Monthly",
      description: "Full gym access, billed every month.",
      durationMonths: 1,
      price: 3000,
    },
    {
      name: "Quarterly",
      description: "Three months of full access at a reduced rate.",
      durationMonths: 3,
      price: 8000,
    },
    {
      name: "6 Months",
      description: "Half-year membership with the best mid-term value.",
      durationMonths: 6,
      price: 15000,
    },
    {
      name: "Annual",
      description: "Twelve months of full access at our lowest monthly rate.",
      durationMonths: 12,
      price: 28000,
    },
  ]

  for (const plan of plans) {
    const existing = await prisma.membershipPlan.findFirst({
      where: { name: plan.name },
    })
    if (existing) {
      await prisma.membershipPlan.update({
        where: { id: existing.id },
        data: plan,
      })
    } else {
      await prisma.membershipPlan.create({ data: plan })
    }
  }
  console.log(`Seeded ${plans.length} membership plans`)
}

main()
  .then(async () => {
    await prisma.$disconnect()
  })
  .catch(async (error) => {
    console.error(error)
    await prisma.$disconnect()
    process.exit(1)
  })
```

Note: `MembershipPlan.name` has no unique constraint (two plans may legitimately share a name over time), so plans use find-then-update rather than `upsert`.

- [ ] **Step 2: Run the seed**

```bash
npm run db:seed
```

Expected output:
```
Seeded admin user: admin@richmanfitness.local
Seeded gym settings
Seeded 3 sections
Seeded 4 membership plans
```

- [ ] **Step 3: Verify the seed is idempotent**

```bash
npm run db:seed
```

Expected: the same output, no unique-constraint errors.

- [ ] **Step 4: Verify the data landed**

```bash
docker exec rmf-postgres psql -U rmf -d rmf_gym \
  -c 'SELECT email, role FROM "User";' \
  -c 'SELECT name FROM "Section";' \
  -c 'SELECT name, "durationMonths", price FROM "MembershipPlan";'
```

Expected: 1 user with role `ADMIN`, 3 sections, 4 plans.

- [ ] **Step 5: Verification checkpoint**

Run: `npm run typecheck`
Expected: no errors.

---

## Task 9: Theme tokens and root layout

**Files:**
- Modify: `app/globals.css`
- Modify: `app/layout.tsx`

Crimson & Steel, the direction confirmed during brainstorming. Tailwind v4 defines theme tokens in CSS via `@theme` — there is no `tailwind.config.js`.

- [ ] **Step 1: Replace app/globals.css**

```css
@import "tailwindcss";

@theme {
  /* --- Crimson & Steel palette --- */
  --color-ink-950: #0b0b0d;
  --color-ink-900: #121215;
  --color-ink-850: #17171b;
  --color-ink-800: #1a1a1f;
  --color-ink-700: #26262d;
  --color-ink-600: #3a3a44;
  --color-ink-400: #8b8b98;
  --color-ink-200: #d4d4dc;
  --color-ink-50: #f5f5f7;

  --color-crimson-400: #f04858;
  --color-crimson-500: #e11d2e;
  --color-crimson-600: #c2162a;

  /* --- Status colours (badges) --- */
  --color-status-paid: #22c55e;
  --color-status-paid-bg: #14311f;
  --color-status-due: #f5a623;
  --color-status-due-bg: #33280f;
  --color-status-expired: #ef4444;
  --color-status-expired-bg: #331616;
  --color-status-inactive: #8b8b98;
  --color-status-inactive-bg: #232329;

  --font-display: var(--font-geist-sans), system-ui, sans-serif;
}

html {
  color-scheme: dark;
}

body {
  background-color: var(--color-ink-950);
  color: var(--color-ink-50);
  -webkit-font-smoothing: antialiased;
}
```

- [ ] **Step 2: Replace app/layout.tsx**

```tsx
import type { Metadata } from "next"
import { Geist } from "next/font/google"

import "./globals.css"

const geist = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
})

export const metadata: Metadata = {
  title: "Rich Man Fitness",
  description:
    "Rich Man Fitness — strength training, cardio, and personal coaching.",
}

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body className={`${geist.variable} font-display antialiased`}>
        {children}
      </body>
    </html>
  )
}
```

- [ ] **Step 3: Delete the default scaffold page**

`create-next-app` generated `app/page.tsx`. The landing page is created at `app/(public)/page.tsx` in Task 12 — two files cannot both own the `/` route.

```bash
rm app/page.tsx
```

- [ ] **Step 4: Verification checkpoint**

Run: `npm run typecheck`
Expected: no errors. (`npm run dev` will 404 on `/` until Task 12 — that is expected at this point.)

---

## Task 10: Login page

**Files:**
- Create: `lib/auth/actions.ts`
- Create: `app/admin/login/login-form.tsx`
- Create: `app/admin/login/page.tsx`

- [ ] **Step 1: Create the authenticate Server Action**

Create `lib/auth/actions.ts`:

```ts
"use server"

import { AuthError } from "next-auth"

import { signIn, signOut } from "@/lib/auth"

export async function authenticate(
  _prevState: string | undefined,
  formData: FormData,
): Promise<string | undefined> {
  try {
    await signIn("credentials", {
      email: formData.get("email"),
      password: formData.get("password"),
      redirectTo: "/admin",
    })
  } catch (error) {
    if (error instanceof AuthError) {
      if (error.type === "CredentialsSignin") {
        return "Invalid email or password."
      }
      return "Something went wrong. Please try again."
    }
    // A successful signIn throws a NEXT_REDIRECT error that must propagate.
    throw error
  }
}

export async function logout(): Promise<void> {
  await signOut({ redirectTo: "/admin/login" })
}
```

- [ ] **Step 2: Create the login form client component**

Create `app/admin/login/login-form.tsx`:

```tsx
"use client"

import { useActionState } from "react"
import { useFormStatus } from "react-dom"

import { authenticate } from "@/lib/auth/actions"

function SubmitButton() {
  const { pending } = useFormStatus()

  return (
    <button
      type="submit"
      disabled={pending}
      className="w-full rounded-lg bg-crimson-500 px-4 py-3 text-sm font-semibold text-white transition hover:bg-crimson-600 disabled:cursor-not-allowed disabled:opacity-60"
    >
      {pending ? "Signing in…" : "Sign in"}
    </button>
  )
}

export function LoginForm() {
  const [errorMessage, formAction] = useActionState(authenticate, undefined)

  return (
    <form action={formAction} className="space-y-4">
      <div>
        <label
          htmlFor="email"
          className="mb-1.5 block text-xs font-medium uppercase tracking-wide text-ink-400"
        >
          Email
        </label>
        <input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          required
          autoFocus
          className="w-full rounded-lg border border-ink-700 bg-ink-900 px-3 py-2.5 text-sm text-ink-50 outline-none transition placeholder:text-ink-600 focus:border-crimson-500"
          placeholder="admin@richmanfitness.local"
        />
      </div>

      <div>
        <label
          htmlFor="password"
          className="mb-1.5 block text-xs font-medium uppercase tracking-wide text-ink-400"
        >
          Password
        </label>
        <input
          id="password"
          name="password"
          type="password"
          autoComplete="current-password"
          required
          className="w-full rounded-lg border border-ink-700 bg-ink-900 px-3 py-2.5 text-sm text-ink-50 outline-none transition placeholder:text-ink-600 focus:border-crimson-500"
          placeholder="••••••••"
        />
      </div>

      {errorMessage ? (
        <p
          role="alert"
          className="rounded-lg border border-status-expired/40 bg-status-expired-bg px-3 py-2 text-sm text-status-expired"
        >
          {errorMessage}
        </p>
      ) : null}

      <SubmitButton />
    </form>
  )
}
```

- [ ] **Step 3: Create the login page**

Create `app/admin/login/page.tsx`:

```tsx
import type { Metadata } from "next"
import Link from "next/link"

import { LoginForm } from "./login-form"

export const metadata: Metadata = {
  title: "Admin Sign In — Rich Man Fitness",
}

export default function LoginPage() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-ink-950 px-4">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <Link
            href="/"
            className="text-xl font-extrabold uppercase tracking-widest text-ink-50"
          >
            Rich Man<span className="text-crimson-500"> Fitness</span>
          </Link>
          <p className="mt-2 text-sm text-ink-400">Admin sign in</p>
        </div>

        <div className="rounded-2xl border border-ink-800 bg-ink-900 p-6">
          <LoginForm />
        </div>

        <p className="mt-6 text-center text-xs text-ink-600">
          Authorised staff only. Contact the gym owner for access.
        </p>
      </div>
    </main>
  )
}
```

- [ ] **Step 4: Start the dev server**

```bash
npm run dev
```

Expected: `Ready in ...` on http://localhost:3000

- [ ] **Step 5: Verify unauthenticated access is blocked**

Open http://localhost:3000/admin in a browser.
Expected: redirected to `/admin/login` (this proves the middleware from Task 7 works).

- [ ] **Step 6: Verify invalid credentials are rejected**

On `/admin/login`, submit `admin@richmanfitness.local` with password `wrongpassword`.
Expected: stays on the page and shows **"Invalid email or password."**

- [ ] **Step 7: Verify valid credentials succeed**

Submit `admin@richmanfitness.local` with the `ADMIN_PASSWORD` value from `.env`.
Expected: redirected to `/admin`. It renders a 404 for now — the dashboard page is Task 11. Reaching a 404 at `/admin` instead of being bounced to `/admin/login` is the proof that the session was created.

- [ ] **Step 8: Verification checkpoint**

Run: `npm run typecheck && npm run lint`
Expected: no errors.

---

## Task 11: Admin shell — sidebar, topbar, dashboard placeholder

**Files:**
- Create: `components/admin/nav-items.ts`
- Create: `components/admin/sidebar.tsx`
- Create: `components/admin/topbar.tsx`
- Create: `app/admin/layout.tsx`
- Create: `app/admin/page.tsx`

Nav items are driven by one array with an `enabled` flag. Routes built in later phases are rendered dimmed and non-clickable rather than as dead links or "coming soon" stub pages. Each later phase flips its own flag to `true`.

- [ ] **Step 1: Create the nav config**

Create `components/admin/nav-items.ts`:

```ts
export type NavItem = {
  label: string
  href: string
  /** Routes are enabled as their phase lands. Disabled items render dimmed. */
  enabled: boolean
}

export const NAV_ITEMS: NavItem[] = [
  { label: "Dashboard", href: "/admin", enabled: true },
  { label: "Members", href: "/admin/members", enabled: false },
  { label: "Payments", href: "/admin/payments", enabled: false },
  { label: "Receipts", href: "/admin/receipts", enabled: false },
  { label: "Membership Plans", href: "/admin/membership-plans", enabled: false },
  { label: "WhatsApp", href: "/admin/whatsapp", enabled: false },
  { label: "Reports", href: "/admin/reports", enabled: false },
  { label: "Settings", href: "/admin/settings", enabled: false },
]
```

- [ ] **Step 2: Create the sidebar**

Create `components/admin/sidebar.tsx`:

```tsx
"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"

import { NAV_ITEMS } from "@/components/admin/nav-items"
import { logout } from "@/lib/auth/actions"

export function Sidebar({ gymName }: { gymName: string }) {
  const pathname = usePathname()

  return (
    <aside className="flex h-full w-64 flex-col border-r border-ink-800 bg-ink-900">
      <div className="border-b border-ink-800 px-5 py-5">
        <span className="text-sm font-extrabold uppercase tracking-widest text-ink-50">
          {gymName}
        </span>
      </div>

      <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-4">
        {NAV_ITEMS.map((item) => {
          const isActive =
            item.href === "/admin"
              ? pathname === "/admin"
              : pathname.startsWith(item.href)

          if (!item.enabled) {
            return (
              <span
                key={item.href}
                aria-disabled="true"
                title="Available in a later phase"
                className="block cursor-not-allowed rounded-lg px-3 py-2 text-sm text-ink-600"
              >
                {item.label}
              </span>
            )
          }

          return (
            <Link
              key={item.href}
              href={item.href}
              className={
                isActive
                  ? "block rounded-lg bg-crimson-500/10 px-3 py-2 text-sm font-medium text-crimson-400"
                  : "block rounded-lg px-3 py-2 text-sm text-ink-200 transition hover:bg-ink-800"
              }
            >
              {item.label}
            </Link>
          )
        })}
      </nav>

      <form action={logout} className="border-t border-ink-800 p-3">
        <button
          type="submit"
          className="w-full rounded-lg px-3 py-2 text-left text-sm text-ink-400 transition hover:bg-ink-800 hover:text-ink-50"
        >
          Log out
        </button>
      </form>
    </aside>
  )
}
```

- [ ] **Step 3: Create the topbar**

Create `components/admin/topbar.tsx`:

```tsx
export function Topbar({
  adminName,
  adminEmail,
}: {
  adminName: string
  adminEmail: string
}) {
  const initial = adminName.trim().charAt(0).toUpperCase() || "A"

  return (
    <header className="flex items-center justify-between border-b border-ink-800 bg-ink-900/60 px-5 py-3.5 backdrop-blur">
      <div className="lg:hidden">
        <span className="text-sm font-extrabold uppercase tracking-widest text-ink-50">
          Rich Man<span className="text-crimson-500"> Fitness</span>
        </span>
      </div>

      <div className="ml-auto flex items-center gap-3">
        <div className="hidden text-right sm:block">
          <p className="text-sm font-medium text-ink-50">{adminName}</p>
          <p className="text-xs text-ink-400">{adminEmail}</p>
        </div>
        <div className="flex h-9 w-9 items-center justify-center rounded-full bg-crimson-500 text-sm font-semibold text-white">
          {initial}
        </div>
      </div>
    </header>
  )
}
```

- [ ] **Step 4: Create the admin layout**

The middleware already gates `/admin/*`; this layout re-checks the session because it needs the user object anyway, and a second server-side check is cheap defence in depth.

Create `app/admin/layout.tsx`:

```tsx
import { redirect } from "next/navigation"

import { Sidebar } from "@/components/admin/sidebar"
import { Topbar } from "@/components/admin/topbar"
import { auth } from "@/lib/auth"
import { prisma } from "@/lib/db"

export default async function AdminLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const session = await auth()
  if (!session?.user) {
    redirect("/admin/login")
  }

  const settings = await prisma.gymSettings.findUnique({ where: { id: 1 } })
  const gymName = settings?.gymName ?? "Rich Man Fitness"

  return (
    <div className="flex min-h-screen bg-ink-950">
      <div className="hidden lg:block">
        <Sidebar gymName={gymName} />
      </div>

      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar
          adminName={session.user.name ?? "Admin"}
          adminEmail={session.user.email ?? ""}
        />
        <main className="flex-1 px-5 py-6">{children}</main>
      </div>
    </div>
  )
}
```

Note the login page lives at `app/admin/login/page.tsx`, which is **inside** this layout's segment. Move it out so the login screen is not wrapped in the admin shell — see the next step.

- [ ] **Step 5: Move the login route out of the admin layout**

Wrap the login route in its own route group so it keeps the `/admin/login` URL but escapes `app/admin/layout.tsx`:

```bash
mkdir -p "app/(auth)/admin/login"
mv app/admin/login/page.tsx "app/(auth)/admin/login/page.tsx"
mv app/admin/login/login-form.tsx "app/(auth)/admin/login/login-form.tsx"
rmdir app/admin/login
```

Route groups in parentheses do not appear in the URL, so `/admin/login` still resolves — but it now renders outside `app/admin/layout.tsx` and so is never auth-gated by it.

- [ ] **Step 6: Create the Phase 1 dashboard**

Real operational metrics arrive in Phase 3 once payments exist. Phase 1 shows counts that are genuinely available now, so the page is real rather than a mock.

Create `app/admin/page.tsx`:

```tsx
import type { Metadata } from "next"

import { formatCurrency } from "@/lib/currency/format"
import { prisma } from "@/lib/db"

export const metadata: Metadata = {
  title: "Dashboard — Rich Man Fitness",
}

export default async function DashboardPage() {
  const [memberCount, sectionCount, plans, settings] = await Promise.all([
    prisma.member.count(),
    prisma.section.count({ where: { isActive: true } }),
    prisma.membershipPlan.findMany({
      where: { isActive: true },
      orderBy: { durationMonths: "asc" },
    }),
    prisma.gymSettings.findUnique({ where: { id: 1 } }),
  ])

  const currency = settings?.currency ?? "PKR"

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-ink-50">Dashboard</h1>
        <p className="mt-1 text-sm text-ink-400">
          Foundation is in place. Member and payment metrics arrive in the next
          phases.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <StatCard label="Total members" value={String(memberCount)} />
        <StatCard label="Active sections" value={String(sectionCount)} />
        <StatCard label="Membership plans" value={String(plans.length)} />
      </div>

      <div className="rounded-xl border border-ink-800 bg-ink-900 p-5">
        <h2 className="mb-4 text-sm font-semibold uppercase tracking-wide text-ink-400">
          Membership plans
        </h2>
        <ul className="divide-y divide-ink-800">
          {plans.map((plan) => (
            <li
              key={plan.id}
              className="flex items-center justify-between py-3"
            >
              <div>
                <p className="text-sm font-medium text-ink-50">{plan.name}</p>
                <p className="text-xs text-ink-400">
                  {plan.durationMonths}{" "}
                  {plan.durationMonths === 1 ? "month" : "months"}
                </p>
              </div>
              <span className="text-sm font-semibold text-crimson-400">
                {formatCurrency(Number(plan.price), currency)}
              </span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-ink-800 bg-ink-900 p-5">
      <p className="text-xs font-medium uppercase tracking-wide text-ink-400">
        {label}
      </p>
      <p className="mt-2 text-3xl font-bold text-ink-50">{value}</p>
    </div>
  )
}
```

- [ ] **Step 7: Verify the shell renders**

With `npm run dev` running, sign in at http://localhost:3000/admin/login.
Expected: lands on `/admin` showing the sidebar (Dashboard active, other items dimmed), the topbar with the admin's name/email and avatar initial, three stat cards (`0` members, `3` sections, `4` plans), and the four seeded plans priced as `Rs. 3,000`, `Rs. 8,000`, `Rs. 15,000`, `Rs. 28,000`.

- [ ] **Step 8: Verify logout works**

Click **Log out** in the sidebar.
Expected: redirected to `/admin/login`. Navigating back to `/admin` redirects to the login page again.

- [ ] **Step 9: Verification checkpoint**

Run: `npm run typecheck && npm run lint && npm test`
Expected: no type errors, no lint errors, 25 tests passing.

---

## Task 12: Public landing page

**Files:**
- Create: `components/landing/navbar.tsx`
- Create: `components/landing/hero.tsx`
- Create: `components/landing/about.tsx`
- Create: `components/landing/facilities.tsx`
- Create: `components/landing/why-choose-us.tsx`
- Create: `components/landing/contact.tsx`
- Create: `components/landing/footer.tsx`
- Create: `app/(public)/page.tsx`

The **Membership Plans** section is deliberately absent from Phase 1 — the spec requires those to come from the database, and plan management lands in Phase 2. The navbar links to `#memberships`, which Phase 2 fills in. Testimonials land in Phase 7 (polish).

- [ ] **Step 1: Create the navbar**

Create `components/landing/navbar.tsx`:

```tsx
import Link from "next/link"

const LINKS = [
  { label: "Home", href: "#home" },
  { label: "About", href: "#about" },
  { label: "Memberships", href: "#memberships" },
  { label: "Facilities", href: "#facilities" },
  { label: "Contact", href: "#contact" },
]

export function Navbar() {
  return (
    <header className="sticky top-0 z-50 border-b border-ink-800 bg-ink-950/80 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-5 py-4">
        <Link
          href="#home"
          className="text-lg font-extrabold uppercase tracking-widest text-ink-50"
        >
          Rich Man<span className="text-crimson-500"> Fitness</span>
        </Link>

        <nav className="hidden items-center gap-7 md:flex">
          {LINKS.map((link) => (
            <a
              key={link.href}
              href={link.href}
              className="text-sm text-ink-200 transition hover:text-crimson-400"
            >
              {link.label}
            </a>
          ))}
        </nav>

        <Link
          href="/admin/login"
          className="rounded-lg border border-ink-700 px-4 py-2 text-sm font-medium text-ink-50 transition hover:border-crimson-500 hover:text-crimson-400"
        >
          Login
        </Link>
      </div>
    </header>
  )
}
```

- [ ] **Step 2: Create the hero**

Create `components/landing/hero.tsx`:

```tsx
export function Hero() {
  return (
    <section
      id="home"
      className="border-b border-ink-800 bg-gradient-to-b from-ink-900 to-ink-950"
    >
      <div className="mx-auto max-w-6xl px-5 py-24 md:py-32">
        <p className="mb-4 text-xs font-semibold uppercase tracking-[0.2em] text-crimson-500">
          Train hard. Get stronger.
        </p>
        <h1 className="max-w-3xl text-4xl font-extrabold leading-tight tracking-tight text-ink-50 md:text-6xl">
          Build the strongest version of yourself.
        </h1>
        <p className="mt-6 max-w-xl text-base leading-relaxed text-ink-400 md:text-lg">
          Modern equipment, serious coaching, and a training floor built for
          people who show up. Membership plans for every schedule and budget.
        </p>

        <div className="mt-9 flex flex-col gap-3 sm:flex-row">
          <a
            href="#contact"
            className="rounded-lg bg-crimson-500 px-6 py-3 text-center text-sm font-semibold text-white transition hover:bg-crimson-600"
          >
            Join Rich Man Fitness
          </a>
          <a
            href="#memberships"
            className="rounded-lg border border-ink-700 px-6 py-3 text-center text-sm font-semibold text-ink-50 transition hover:border-crimson-500 hover:text-crimson-400"
          >
            View Membership Plans
          </a>
        </div>
      </div>
    </section>
  )
}
```

- [ ] **Step 3: Create the about section**

Create `components/landing/about.tsx`:

```tsx
export function About() {
  return (
    <section id="about" className="border-b border-ink-800">
      <div className="mx-auto max-w-6xl px-5 py-20">
        <h2 className="text-3xl font-bold tracking-tight text-ink-50">
          About the gym
        </h2>
        <p className="mt-5 max-w-2xl text-base leading-relaxed text-ink-400">
          Rich Man Fitness is a strength-first training facility. We keep the
          floor clean, the equipment maintained, and the coaching honest. Whether
          you are lifting for the first time or chasing a personal record, you
          get the same attention and the same standard.
        </p>
      </div>
    </section>
  )
}
```

- [ ] **Step 4: Create the facilities section**

Create `components/landing/facilities.tsx`:

```tsx
const FACILITIES = [
  {
    title: "Strength training",
    body: "Racks, platforms, and barbells built for heavy, consistent work.",
  },
  {
    title: "Cardio",
    body: "Treadmills, bikes, and rowers maintained and always available.",
  },
  {
    title: "Free weights",
    body: "A complete dumbbell range with benches and dedicated floor space.",
  },
  {
    title: "Personal training",
    body: "One-on-one coaching and programming from experienced trainers.",
  },
  {
    title: "Modern equipment",
    body: "Machines serviced on a schedule, replaced before they wear out.",
  },
  {
    title: "Locker facilities",
    body: "Secure lockers and changing rooms so you can train straight after work.",
  },
]

export function Facilities() {
  return (
    <section id="facilities" className="border-b border-ink-800 bg-ink-900/40">
      <div className="mx-auto max-w-6xl px-5 py-20">
        <h2 className="text-3xl font-bold tracking-tight text-ink-50">
          Facilities
        </h2>

        <div className="mt-10 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {FACILITIES.map((facility) => (
            <div
              key={facility.title}
              className="rounded-xl border border-ink-800 bg-ink-900 p-6"
            >
              <h3 className="text-base font-semibold text-ink-50">
                {facility.title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-ink-400">
                {facility.body}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
```

- [ ] **Step 5: Create the why-choose-us section**

Create `components/landing/why-choose-us.tsx`:

```tsx
const REASONS = [
  {
    title: "Serious training floor",
    body: "No queues for the rack, no broken machines left unrepaired.",
  },
  {
    title: "Flexible plans",
    body: "Monthly through annual memberships — pay for the commitment you want.",
  },
  {
    title: "Instant receipts",
    body: "Pay by cash, bank transfer, Easypaisa or JazzCash and get your receipt on WhatsApp immediately.",
  },
  {
    title: "Day and night batches",
    body: "Separate day and night-shift timings, and a dedicated ladies section.",
  },
]

export function WhyChooseUs() {
  return (
    <section className="border-b border-ink-800">
      <div className="mx-auto max-w-6xl px-5 py-20">
        <h2 className="text-3xl font-bold tracking-tight text-ink-50">
          Why choose us
        </h2>

        <div className="mt-10 grid gap-5 sm:grid-cols-2">
          {REASONS.map((reason) => (
            <div
              key={reason.title}
              className="rounded-xl border border-ink-800 bg-ink-900 p-6"
            >
              <h3 className="text-base font-semibold text-crimson-400">
                {reason.title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-ink-400">
                {reason.body}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
```

- [ ] **Step 6: Create the contact section**

Contact details come from the `GymSettings` singleton so they stay editable from Settings later, rather than being hardcoded into markup.

Create `components/landing/contact.tsx`:

```tsx
import { prisma } from "@/lib/db"

export async function Contact() {
  const settings = await prisma.gymSettings.findUnique({ where: { id: 1 } })

  const details = [
    { label: "Phone", value: settings?.phone },
    { label: "WhatsApp", value: settings?.whatsappPhone },
    { label: "Email", value: settings?.email },
    { label: "Address", value: settings?.address },
    { label: "Opening hours", value: settings?.openingHours },
  ].filter((detail): detail is { label: string; value: string } =>
    Boolean(detail.value),
  )

  return (
    <section id="contact" className="border-b border-ink-800 bg-ink-900/40">
      <div className="mx-auto max-w-6xl px-5 py-20">
        <h2 className="text-3xl font-bold tracking-tight text-ink-50">
          Visit us
        </h2>

        <dl className="mt-10 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {details.map((detail) => (
            <div key={detail.label}>
              <dt className="text-xs font-medium uppercase tracking-wide text-ink-400">
                {detail.label}
              </dt>
              <dd className="mt-1 text-sm text-ink-50">{detail.value}</dd>
            </div>
          ))}
        </dl>

        {settings?.whatsappPhone ? (
          <a
            href={`https://wa.me/${settings.whatsappPhone.replace(/\D/g, "")}`}
            target="_blank"
            rel="noopener noreferrer"
            className="mt-10 inline-block rounded-lg bg-crimson-500 px-6 py-3 text-sm font-semibold text-white transition hover:bg-crimson-600"
          >
            Message us on WhatsApp
          </a>
        ) : null}
      </div>
    </section>
  )
}
```

- [ ] **Step 7: Create the footer**

Create `components/landing/footer.tsx`:

```tsx
import Link from "next/link"

export function Footer() {
  return (
    <footer className="bg-ink-950">
      <div className="mx-auto max-w-6xl px-5 py-14">
        <div className="grid gap-10 sm:grid-cols-3">
          <div>
            <p className="text-lg font-extrabold uppercase tracking-widest text-ink-50">
              Rich Man<span className="text-crimson-500"> Fitness</span>
            </p>
            <p className="mt-3 max-w-xs text-sm leading-relaxed text-ink-400">
              A strength-first training facility for people who show up.
            </p>
          </div>

          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-ink-400">
              Explore
            </p>
            <ul className="mt-3 space-y-2 text-sm">
              <li>
                <a href="#about" className="text-ink-200 hover:text-crimson-400">
                  About
                </a>
              </li>
              <li>
                <a
                  href="#facilities"
                  className="text-ink-200 hover:text-crimson-400"
                >
                  Facilities
                </a>
              </li>
              <li>
                <a
                  href="#contact"
                  className="text-ink-200 hover:text-crimson-400"
                >
                  Contact
                </a>
              </li>
            </ul>
          </div>

          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-ink-400">
              Staff
            </p>
            <ul className="mt-3 space-y-2 text-sm">
              <li>
                <Link
                  href="/admin/login"
                  className="text-ink-200 hover:text-crimson-400"
                >
                  Admin login
                </Link>
              </li>
            </ul>
          </div>
        </div>

        <p className="mt-12 border-t border-ink-800 pt-6 text-xs text-ink-600">
          © {new Date().getFullYear()} Rich Man Fitness. All rights reserved.
        </p>
      </div>
    </footer>
  )
}
```

- [ ] **Step 8: Compose the landing page**

Create `app/(public)/page.tsx`:

```tsx
import { About } from "@/components/landing/about"
import { Contact } from "@/components/landing/contact"
import { Facilities } from "@/components/landing/facilities"
import { Footer } from "@/components/landing/footer"
import { Hero } from "@/components/landing/hero"
import { Navbar } from "@/components/landing/navbar"
import { WhyChooseUs } from "@/components/landing/why-choose-us"

export default function LandingPage() {
  return (
    <>
      <Navbar />
      <main>
        <Hero />
        <About />
        <Facilities />
        <WhyChooseUs />
        <Contact />
      </main>
      <Footer />
    </>
  )
}
```

- [ ] **Step 9: Verify the landing page renders**

Open http://localhost:3000
Expected: dark Crimson & Steel landing page with a sticky navbar, hero with both CTAs, About, six facility cards, four why-choose-us cards, contact details pulled from the seeded `GymSettings` (phone, WhatsApp, email, address, opening hours), a WhatsApp CTA, and a footer with an Admin login link.

- [ ] **Step 10: Verify responsiveness**

Open browser dev tools and set the viewport to 390 × 844 (iPhone-class).
Expected: no horizontal scrolling; the navbar link row is hidden while the logo and Login button remain; all card grids collapse to a single column.

- [ ] **Step 11: Verification checkpoint**

Run: `npm run typecheck && npm run lint && npm test`
Expected: no type errors, no lint errors, 25 tests passing.

---

## Task 13: Phase 1 acceptance verification

**Files:** none — verification only.

- [ ] **Step 1: Verify a clean production build**

```bash
npm run build
```

Expected: `Compiled successfully`, with a route table listing `/`, `/admin`, `/admin/login`, and `/api/auth/[...nextauth]`.

- [ ] **Step 2: Verify a from-scratch database bootstrap**

This proves a new developer can start from nothing:

```bash
npm run db:reset -- --force
npm run db:seed
```

Expected: migrations reapply, seed prints the four success lines from Task 8.

- [ ] **Step 3: Run the full check suite**

```bash
npm run typecheck && npm run lint && npm test
```

Expected: no type errors, no lint errors, 25 tests passing across 3 files.

- [ ] **Step 4: Walk the Phase 1 acceptance path manually**

With `npm run dev` running:

1. Visit `/` → landing page renders.
2. Click **Login** in the navbar → lands on `/admin/login`.
3. Submit wrong credentials → "Invalid email or password." is shown.
4. Submit the seeded credentials → lands on `/admin` with the shell rendered.
5. Visit `/admin` in a private window (no session) → redirected to `/admin/login`.
6. Click **Log out** → returned to `/admin/login`; `/admin` is protected again.

Expected: all six steps behave as described.

- [ ] **Step 5: Confirm no secrets are committed**

```bash
git status --short
git check-ignore -v .env
```

Expected: `.env` does not appear in `git status`, and `check-ignore` confirms it matches a `.gitignore` rule.

---

## Phase 1 Definition of Done

- [ ] `docker compose ps` shows a healthy `rmf-postgres`
- [ ] All 14 Prisma models exist in the database
- [ ] `npm run db:seed` is idempotent and creates the admin, settings, 3 sections, 4 plans
- [ ] `/admin/*` is unreachable without a session; `/admin/login` redirects to `/admin` when already signed in
- [ ] Login rejects bad credentials with a visible error and accepts seeded credentials
- [ ] Admin shell renders sidebar (later-phase items dimmed), topbar, and a real dashboard
- [ ] Log out clears the session
- [ ] Landing page renders and is usable at 390px wide
- [ ] `npm run typecheck`, `npm run lint`, `npm test`, and `npm run build` all pass
- [ ] No secrets are tracked by git

---

## What Phase 1 deliberately does not include

Each is scheduled in a later phase and gets its own plan:

| Deferred | Phase |
|---|---|
| Member CRUD, member profile, search/filter, plan management UI, Sections CRUD, DB-driven Membership Plans landing section, 15 seeded test members | 2 |
| Record Payment workflow, `MembershipPeriod` derivation, `computeMemberStatus`, payment history | 3 |
| Receipt PNG (satori/resvg), PDF (pdf-lib), receipt storage abstraction, receipts page | 4 |
| WhatsApp provider abstraction, mock provider, Meta provider, retry, webhook, WhatsApp page | 5 |
| Excel import wizard and wide-ledger pivot parser | 6 |
| Reports, CSV export, Settings screens, testimonials, mobile polish pass | 7 |
