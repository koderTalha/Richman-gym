# Cycle re-pricing on a fee change

Date: 2026-09-11
Status: implemented, all tests passing (768)

Context for anyone — human or agent — picking this up cold. It assumes
`2026-09-03-anchored-billing-cycles-and-reminders-design.md`, which introduced
the cycle model this fixes a hole in.

## The bug, as the owner reported it

> "Payment is always due for the members. He was added as a member on the
> monthly plan of 1500 and after some months his plan goes up to 2500. Now all
> the payments have been completed but still the payment is due for the member."

It was true, and reproducible in every configuration tested.

## Root cause

`MembershipPeriods.expectedAmountMinor` is a **fee snapshot taken when the cycle
opens**. That rule is correct for history — a price rise must not rewrite months
the member already paid — but it was applied to *every* cycle, including ones
nobody had put a rupee into.

The failure sequence:

1. `BillingMaintenance` opens the member's March cycle. It snapshots the fee in
   force that morning: **1500**.
2. The owner raises the fee to **2500**. Nothing touches the open cycle.
3. The owner collects **2500**. `recordAdvancePayment` allocates arrears-first:
   1500 fills March, and the leftover **1000 has nowhere to go but forward**.
4. `settleableFor` grows the offered list until the money is covered, so the
   spill **opens April's cycle early** and part-pays it (1000 of 2500).
5. A cycle row is a debt. The member now has one more cycle open than they have
   been billed for, and it is short by exactly 1500.
6. Every later payment clears the previous shortfall and creates an identical
   one. Permanent.

Observed over 12 months of paying the full fee on time:

```
paid=24000  billed=25500  cycles=13  unsettled=1  outstanding=1500 (for ever)
```

Thirteen cycles for twelve months lived is the tell. The member was actually
**1000 in credit** while the app reported them **1500 in arrears**.

The trigger is **not** how the fee was raised — editing the plan price and moving
the member to a dearer plan produce an identical treadmill. It is whether an
**unpaid cycle already existed** at the moment of the change.

Knock-on surfaces: the Record Payment dialog's outstanding banner, and
`ReminderService` (`reminder_service.dart:119` reads `billing.nextUnsettled`),
which would chase members for money they do not owe.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **An unpaid cycle is re-priced to the member's current fee.** It is a bill that has not been issued, not history. | Closes the gap at source: the cycle asks 2500, the owner collects 2500, nothing spills. |
| 2 | **A settled cycle is never re-priced.** | Reopening a closed debt. |
| 3 | **A cycle holding *any* money is never re-priced, part-payments included.** | The member paid that against the old price; moving it afterwards backdates the rise. |
| 4 | **A cycle that has already ended is never re-priced.** | Arrears were incurred at the price in force then. A member who owes January owes January's fee, not today's. |
| 5 | **The rise reaches the member's *current* cycle, not just the next one.** Owner's explicit choice. | The alternative requires the owner to collect the old fee for the current month or the bug recurs immediately. |
| 6 | **Members already stuck are reported, never auto-corrected.** Owner's explicit choice. | See below — this is the important one. |

### Why decision 6 matters

In the database a treadmilled payment is **byte-for-byte indistinguishable**
from a genuine arrears payment. Both look like: one payment, split across two
cycles, earlier cycle under-priced.

- Treadmill: owner collected the new fee for a cycle still priced at the old one.
- Legitimate: member genuinely owed a cheaper month, cleared it, and part-paid
  the current one.

There is no price-history table, so nothing can tell them apart after the fact.
Auto-collapsing the first would silently rewrite the second. **Do not build an
automatic repair.** If asked to, re-read this section first.

## Implementation

### `lib/data/cycle_repricing.dart` (new)

The rule, in the data layer so both repositories can call it without `data/`
importing `services/`.

- `repriceOpenCycles(db, memberId:, now:)` → count re-priced.
  Skips deactivated members. Resolves the fee as
  `membership.feeOverrideMinor ?? plan.priceMinor`. Re-prices cycles where
  `settledAt == null` **and** no money against them **and** `periodEnd > today`.
- `repriceOpenCyclesForPlan(db, planId:, now:)` — loops the above over every
  active member on that plan.
- `_periodsHoldingMoney` checks **allocations *and* raw payment rows**, because a
  pre-v10 database can hold a payment with no allocation and that money counts.

Nothing reads the clock; `now` is passed in, matching `BillingMaintenance` and
`ReminderService`.

### Call sites — every route the fee can move

| Route | Where |
|---|---|
| Plan switch, and per-member fee override | `MemberRepository.update` — one call after the if/else chain covers both branches |
| Plan price edited in Settings | `SettingsRepository.savePlan` → `repriceOpenCyclesForPlan` |

`MemberRepository.update`'s early `return` in the no-enrolment branch was turned
into an `else if` chain so the re-price runs on every path.

Both gained an optional `DateTime? now` for testability.

### `lib/services/billing_reconciliation.dart` (new)

Finds members already stuck. Changes **no data**.

`findBillingDiscrepancies(db, now:)` flags an active member when **both** hold:

- their earliest unsettled cycle has `outstanding > 0` (the app is showing them
  as owing), **and**
- `total paid >= total billed for cycles that have actually started`.

Cycles that have not started are excluded from "billed" on purpose — opening one
early *is* the bug, and counting it would hide the credit that gives the member
away.

This is the one contradiction that is safe to assert. Someone genuinely behind
has paid *less* than billed and is never flagged. Someone simply paid up in
advance owes nothing and is never flagged. It takes both halves.

`reportBillingDiscrepancies` writes one audit event per member
(`AuditAction.billingDiscrepancyFound`, `AuditCategory.billing`, outcome
`refused` — the app declining to guess, not a failure), **once per member** —
the Logs screen is read, and repeating the same members every morning would
bury everything else. Surfaces as **"Payments need checking"**.

### `lib/services/startup_maintenance.dart` (new)

`runStartupMaintenance(db, now:)` = `ensureCurrentPeriods` +
`reportBillingDiscrepancies`. Called by `main()` and by the top bar's Reload
button, so the two cannot drift. Both steps idempotent.

### Supporting UI

- **Reload button** in `AppShell`'s top bar, left of the theme toggle
  (`appShellReloadKey`). Runs `runStartupMaintenance`, then bumps a
  `_reloadToken` that keys the subtree holding the current screen — rebuilding
  it recreates its bloc and re-fires the load event the bloc is constructed
  with, so one mechanism reloads every screen. Named **Reload**, not Refresh:
  Dashboard, Logs and Reminders already have per-screen Refresh buttons that
  only re-read what is on screen.
- `logs_screen.dart` gained labels for `billingDiscrepancyFound` and
  `billingAnchorChanged` (the latter had been missing).

## Tests

All written failing first. Suite: **732 passing**.

| File | Covers |
|---|---|
| `test/fee_change_reprice_test.dart` | The 9 rules — re-prices via plan price / plan switch / fee override; leaves settled, part-paid, already-ended and deactivated alone; fee *cuts* reach unpaid cycles too; and the headline: 6 months paying the new fee leaves 8 cycles for 8 months, nothing unsettled, nothing outstanding |
| `test/billing_reconciliation_test.dart` | Flags the stuck member with the right numbers; does **not** flag genuine arrears, a fully-paid member, someone paid 3 months ahead, or a deactivated member; writes the audit event; does not duplicate it |
| `test/startup_maintenance_test.dart` | Opens the owed cycle; idempotent; reports a stuck member |
| `test/app_shell_refresh_test.dart` | Drives the real shell — button present, left of the theme toggle, tooltip "Reload", and tapping it **opens a billing cycle**, proving it does the work rather than repainting |

Verification beyond the suite: a 24-configuration matrix (join day 1/6/15/31 ×
pay day × the day the price rose) run against the real services. Before: every
configuration ended with a permanently unsettled cycle. After: all 24 end at
12 cycles for 12 months, `billed == paid`, nothing unsettled, nothing flagged.

## The second cause of "always due" — also fixed

A member who joined on the 6th, in an app opened on the 1st, was given a cycle
for **6 Dec – 6 Jan** — a month that ended the day they walked in — and read DUE
before they had been a member for an hour:

```
joined 2026-01-06 -> cycle 2025-12-06 to 2026-01-06
status on 3 Jan = MemberStatus.due
```

`BillingMaintenance._cycleCovering` falls through to `cycleContaining`
(`domain/billing_cycle.dart`) for a member with no cycles at all, and that backs
up to the previous occurrence of the anchor day whenever today falls earlier in
the month than the anchor. Right for somebody on the books for years; wrong for
somebody who joined this month. With `payDay == joinDay` it cost a thirteenth
cycle over twelve months lived — the same permanent arrears the re-pricing work
removed by a different route, reached from a different direction.

Triggered by a joining date set a few days ahead, which is ordinary at a gym
counter.

**Fix.** `cycleContaining` now takes `joiningDate` as a floor. A start earlier
than it means this is the member's opening cycle, so [firstCycleFor] builds it
instead. Reproduced first at both levels — the domain function and a member
driven through the real services — and the headline is
`test/pre_joining_cycle_test.dart`: twelve months lived, twelve cycles, nothing
outstanding. Before the fix that test read **13**.

Deliberately *not* changed: the member still reads DUE on a day before their
joining date, because they have enrolled and not paid, and the owner is meant to
collect. What was wrong was never the status — it was billing them for December.

## Telling the owner before it happens

Both routes could move money silently. Neither said anything at all.

### Edit Member — `ui/members/pricing_summary.dart`

A panel under the plan and fee fields: what the member is billed each cycle,
which of the plan price and the custom fee is winning, and — when the edit
changes it — what saving is about to do. It resolves the fee with the same
`customFee ?? planPrice` rule `repriceOpenCycles` uses, so the screen cannot
promise a number the repository would not write.

The wording is load-bearing:

> This month's bill and any later unpaid bill change from Rs. 1,500 to
> Rs. 2,000 when you save.
> Months already paid, or part-paid, keep the price that was charged at the time.

**"Future unpaid bills" would be wrong**, and wrong in the direction that costs
money. The change reaches the cycle the member is standing in (decision 5). An
owner told only about future bills collects the old fee for the month in front
of them, the leftover spills into a cycle opened early, and the treadmill starts
again. `test/pricing_ui_test.dart` asserts on the phrase "this month" for
exactly this reason.

It subscribes to the fee field with a `ValueListenableBuilder` rather than a
controller listener calling `setState`: `_prefill` writes to that controller
*during* build, and a `setState` from there throws.

### Plan Settings — `ui/settings/plan_price_change_dialog.dart`

Re-pricing a plan moves the open bill of every active member on it who has no
fee of their own — the furthest-reaching button in the app, previously the same
silent press as fixing a typo in a plan's name. Editing a price now asks:

> Change Monthly price? Rs. 1,500 → Rs. 2,500
> 23 members follow this price. Their current unpaid bill and any later one
> change to Rs. 2,500.
> 4 members are on a custom fee and are not affected.
> Months already paid, or part-paid, keep the price that was charged at the time.

The counts come from `SettingsRepository.planPricingImpact`, which asks the same
question `repriceOpenCyclesForPlan` acts on — members enrolled on the plan, not
deactivated, split by whether they hold an override — so the warning and the
work cannot drift apart. Renaming a plan, or creating one, shows nothing.

## Audit records

Deactivating one member was recorded; re-pricing the whole roster was not. Two
new actions, both `AuditCategory.billing`:

| Action | Written when |
|---|---|
| `billing.member_fee_changed` | the member's **resolved** fee moved — override added, changed or removed, or a plan switch that changes what they pay |
| `billing.plan_price_changed` | an existing plan's price moved (not a rename, not a new plan) |

Each carries the fee either side, how many cycles were re-priced, and who did
it. Resolved fees rather than raw columns on purpose: the three routes are one
event — "what this member is asked for each month has changed" — and a log split
by mechanism would not answer the question the owner actually asks.

`MemberRepository.update` records **outside** its transaction: the money change
is already committed and a log that cannot be written must not undo it.
`SettingsRepository` gained an `AuditRepository`, shared from `main()` rather
than built per-instance.

## Test matrix as it now stands

**768 passing.** New since the re-pricing work:

| File | Covers |
|---|---|
| `test/pre_joining_cycle_test.dart` | no cycle before the joining date; one month owed on joining, not two; **twelve months is twelve cycles**; a dormant member is still not back-filled; the domain clamp both ways |
| `test/fee_change_reprice_test.dart` (+5) | removing an override returns them to the plan price, and leaves a paid month alone; an override still wins after a plan change; dropping it on a plan change bills the new plan; six months across a plan switch settles at six cycles |
| `test/pricing_audit_test.dart` | both events, with the fee either side and the cycle count; **not** written for a rename, a new plan, or an edit that changed no price |
| `test/plan_pricing_impact_test.dart` | who follows the price, who holds an override, and that a member who has left counts as neither |
| `test/pricing_ui_test.dart` | both widgets, including the "this month" wording and the plan dialog's counts |
| `test/member_form_pricing_test.dart` | the wiring, on the real screen — it caught a dropdown overflowing its column and a `setState` during build, neither of which the isolated widget test could see |

## Gotchas for whoever is next

- `MemberRow.outstandingMinor` is **null**, not `0`, when nothing is owed. Assert
  `isNull`.
- The repo is **hand-formatted**. Do not run `dart format` — it rewrites most
  files.
- Money is integer minor units (paisa) everywhere. `formatMinorUnits(150000)`
  renders `"Rs. 1,500"` — with a comma, which matters when asserting on strings.
- Billing cycles belong to a **member**, never to the open enrolment. Use
  `membership_queries.dart`.
- The duplicate-cycle trigger only guards an identical `period_start`. Two
  *overlapping* cycles with different starts are still permitted.
- Widget tests of the member form need a desktop-sized surface. The binding
  defaults to 800x600 and the form's field rows do not fit in it.
