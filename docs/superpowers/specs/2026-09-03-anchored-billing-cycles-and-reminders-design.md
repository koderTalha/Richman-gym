# Anchored billing cycles and automated payment reminders

Date: 2026-09-03
Status: approved, in implementation

## Problem

The app bills in whole calendar months. `MembershipPeriods.periodStart` is always
UTC midnight on the 1st, and a cycle is identified by a `"YYYY-MM"` billing
month. There is no due date anywhere in the schema — a grep for `dueDate`,
`nextDue` and `due_date` across `lib/` and `test/` returns nothing.

Two consequences the gym owner is feeling:

1. A member who joined on the 6th is billed for calendar September, not
   6 Sep – 6 Oct. The owner thinks in anniversaries; the app thinks in months.
2. There is no reminder system at all, so chasing dues is entirely manual.

Note on the original brief: recording an early payment is **not** currently
blocked. The only `block`-severity rule is `beforeJoining`; `farFuture` is a
`confirm` that fires more than one whole cycle ahead and can be clicked
through. So this work is a change of billing model, not the relaxation of a
guard.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Contiguous cycles with a per-member anchor day.** The next cycle starts where the previous one ended, never where the payment landed. | Resetting the anchor to the payment date drifts forward on every late payment — roughly one free month a year. Contiguity keeps 12 cycles at 12. |
| 2 | **Existing members stay on day 1.** The anchor column is nullable and falls back to the latest cycle's start day. The owner re-anchors individuals from the member screen. | Zero rows written on upgrade; every member reads exactly as they do today. |
| 3 | **Cycles carry a balance.** Settled when allocations reach `expectedAmountMinor`; below that the cycle is partially paid. Cycles predating this release are stamped settled by the migration. | Makes `expectedAmountMinor` meaningful and lets a reminder state a real amount due, without the 2024 ledger turning red. |
| 4 | **Reminder review queue plus opt-in auto-send.** Auto-send is off by default, constrained to configurable gym hours and capped per run. | No cron is possible — this is a desktop app with no server. "Automatic" can only mean "when the counter machine has the app open", which needs guard rails. |
| 5 | **One payment, one receipt, N cycles settled** via a payment-allocation table. | Same mechanism decision 3 needs, so it is one abstraction rather than two. |

## Model

A cycle is `[start, end)`. The end is the start plus the plan's length in
months with the day pinned to the anchor day, clamped to the last day of a
short month. The next cycle starts at the previous end — so contiguity and the
anchor are the same fact, and no `origin` column is needed.

```
anchorDay = 6, duration = 1
  6 Oct ──────── 6 Nov ──────── 6 Dec
```

The anchor is **stored**, not re-derived from the previous boundary, so a short
month cannot permanently demote a member: `31 Jan → 29 Feb → 31 Mar`.

Payment is due at a cycle's **start** — the gym is paid in advance. "Next due
date" is therefore the start of the member's first unsettled cycle.

Re-anchoring never touches a recorded cycle. Changing the billing day writes
the column and takes effect at the next boundary; the transition cycle runs
from the current period end to the occurrence of the new anchor **nearest the
natural end**, keeping it within about a fortnight of a normal cycle. The
transition cycle is charged the full fee — pro-rating would put rounding into
money for a one-off, owner-initiated deviation, and this codebase is
deliberately strict about money.

Timezone convention is unchanged: calendar boundaries are UTC midnight, "what
day is it now" is the local wall clock. Every new pure function takes `now` as
a parameter.

## Schema (v9 → v10, all additive)

```
Memberships        + billingAnchorDay   int NULL
MembershipPeriods  + settledAt          datetime NULL

PaymentAllocations (new)
    paymentId FK → Payments ON DELETE CASCADE
    membershipPeriodId FK → MembershipPeriods
    amountMinor int
    UNIQUE (paymentId, membershipPeriodId)

PaymentReminders (new)
    membershipPeriodId FK ON DELETE CASCADE, memberId FK,
    stage, offsetDays, status, dueDate, sentAt, errorMessage
    UNIQUE (membershipPeriodId, stage, offsetDays)

GymSettings  + reminder configuration and template columns
             + paymentInstructions
```

`settledAt` grandfathers history in **data, not a code branch**: one
`UPDATE ... WHERE EXISTS (a payment)` at migration time stamps every existing
and imported cycle closed. No `if (period.id < watermark)` anywhere.

The `UNIQUE (membershipPeriodId, stage, offsetDays)` key on `PaymentReminders`
*is* the duplicate guard, enforced by SQLite rather than by a read-then-write
race — the same approach as `Payments.idempotencyKey`.

`Payments.membershipPeriodId` stays, pointing at the primary cycle, so the
importer, `PaymentEditService` and the existing test suite keep working.

## Layers

Pure domain (no database, no `DateTime.now()`), extending the split already
established by `billing_month_check.dart` / `billing_month_checker.dart`:

- `domain/billing_cycle.dart` — `addMonthsClamped`, `BillingCycle`,
  `cycleAfter`, `firstCycleFor`, `resolveAnchorDay`, `nearestAnchorTo`
- `domain/payment_settlement.dart` — `SettleableCycle`, `allocate()` waterfall
- `domain/reminder_schedule.dart` — `ReminderSettings`, `decideReminder()`,
  `withinSendingWindow()`

Services:

- `services/billing_cycle_service.dart` — resolve, open and re-anchor cycles
- `services/reminder_service.dart` — build the queue, send, record
- `services/billing_maintenance.dart` — rewritten onto `billing_cycle.dart`
- `services/record_payment_service.dart` — allocation-aware; keeps
  `billingMonth` and gains an optional `targetPeriodId`

A missed reminder never fires late: when several offsets come due while the app
was closed, only the **most recent** is sent and the earlier ones are recorded
as superseded.

## Out of scope

Multi-tenancy. `GymSettings` is a hard single row, as are the receipt counter
and the session. New code adds no singletons and takes its database and
settings by injection, so nothing here blocks tenancy later — but this does not
deliver it.

## Testing

Pure-domain suites run without a database: month-end clamping through February
and back, leap years, re-anchor in both directions, transition cycle length,
the allocation waterfall, reminder supersession, quiet hours.

Database suites: migration grandfathering, advance payment across N cycles with
a remainder, partial then top-up, payment deletion releasing allocations,
reminder duplicate guard, per-run cap.

The backward-compatibility gate is that all 32 existing test files keep passing
unchanged.
