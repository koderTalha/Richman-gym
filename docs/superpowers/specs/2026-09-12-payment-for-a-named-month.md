# Recording a payment for a named month

Date: 2026-09-12
Status: implemented, all tests passing (780)

Assumes `2026-09-11-cycle-repricing-design.md`, which fixed how a fee change
reaches unissued bills. This is the other half: entering months the app was
never open for.

## The report

> "Current month is September. The member joined 1 January and paid to March.
> In April the fee went from 1500 to 2500. When I record April's payment of
> 2500, the system says it is an advance and dates it September — but I chose
> 1 April."

Reproduced exactly. The owner's reading of it was that revenue was being
computed from the current fee. It was not.

## What was actually happening

Three separate things, only one of them a defect.

**1. The payment date never chose the cycle, by design.** `payment_timing.dart`
is explicit: the day cash changed hands and the cycle it bought are different
facts and neither may be derived from the other. Money fills the oldest
unsettled cycle first. So no date typed into that box could send money to May.

**2. May to August had no cycles at all.** `BillingMaintenance` opens only the
cycle covering today, one per member per run, and deliberately skips gaps —
back-filling every missed month would invent debt the owner never recorded.
Opening the app on 1 July with a member paid to 1 May yields a July cycle only.
So the oldest unsettled cycle was September, and that is where the money went.
The ADVANCE badge was correct arithmetic on that: paid 1 May, cycle starts
1 Sep.

**3. The defect: there was no way to say which month a payment was for.**
`RecordPaymentService.call` has taken a `billingMonth` from the start, finds or
**creates** that month's cycle, and classifies timing against *that* cycle. It
is guarded by `reviewBillingMonth` and has a warnings dialog. All of it was
reachable from **Edit Payment** and from nowhere else.

So the owner's workaround — record it wrong, then edit it to the right month —
worked, and produced correct data. It also wrote a wrong row to the ledger on
the way to the right one.

## Why no fee-history table

The request was for `{fee, effectiveFrom, effectiveUntil}` records, on the
belief that revenue was applying one fee across all months. Audited and it is
not:

- `PaymentRepository.totalMinorBetween` is `SUM(payments.amountMinor)` over a
  date window. Revenue is what was collected.
- `MembershipPeriods.expectedAmountMinor` is a per-cycle fee snapshot. Billing
  is what was billed.
- A grep for `fee x months` arithmetic returns nothing. All 34 reads of
  `plan.priceMinor` are either UI showing the current price, or stamping a
  **new** cycle.

**The cycle row is already the fee history**, normalised per cycle rather than
per interval, and better for accounting: it records what was actually billed
rather than what a rate card says should have been. A second table would be a
second source of truth — and when it disagreed with a cycle about a past month,
any answer would be wrong somewhere. Its migration would also have to invent
`effectiveFrom` dates nobody recorded.

What was missing was never the fee history. It was the ability to create a
cycle for a month the app skipped.

The audit events added on 2026-09-11 (`billing.member_fee_changed`,
`billing.plan_price_changed`) give the queryable change log going forward,
without a second source of truth for billing.

## Implementation

### `RecordPaymentInput.expectedAmountMinor` (new, optional)

The one trap in back-entry. `call` created a missing cycle at
`feeOverrideMinor ?? plan.priceMinor` — **today's** fee. A gym typing up last
year's ledger after a price rise would have January conjured at 2500, paid
1500, and left permanently 1000 short. That is the artificial arrears the
billing design forbids, and re-pricing cannot rescue it: a cycle holding money
is never re-priced.

Consulted **only** when the month has no cycle. A month that already has one
keeps the price it was billed at — its price is not a later caller's to move.

### Record Payment dialog — a billing period selector

Two modes, and the default is unchanged:

- **Automatic** — oldest unpaid first, spilling forward. The counter flow.
  Nothing about it changed.
- **A named period** — settles that month alone, opening its cycle if missing.

Naming a month runs `BillingMonthChecker` on every change, not just on submit,
so the owner sees a refusal or a missing cycle while they can still act. The
rules are re-run at submit because the amount or month may have moved since.

- blocking findings (before joining) show as an error with no way through
- confirmations (earlier months unpaid, already paid, far future) go through
  the existing `confirmBillingWarnings`
- when the month has no cycle, a **Fee for this month** field appears,
  pre-filled with the current fee and editable

Recording resets to Automatic, so the next member at the counter is not
silently still on a back-dated month.

### Two pre-existing layout bugs, found by the tests

Both assert in debug and silently clip in release:

- the Payment method dropdown overflowed its column by 53px
- (on 2026-09-11) the Membership plan dropdown overflowed by 43px

Both fixed with `isExpanded: true` and an ellipsis.

## Tests

| File | Covers |
|---|---|
| `test/record_payment_billing_month_test.dart` | a month with no cycle is opened and settled; timing reads on-time not ADVANCE; a back-filled month is worth what it cost; without an override a new cycle still takes the current fee; **the owner's year — 1500 to March, 2500 from April, nine cycles, nothing owed, revenue 4500 + 2500x6**; the same month twice opens one cycle; an override is ignored when the cycle already exists |
| `test/record_payment_month_picker_test.dart` | the field exists and defaults to Automatic; Automatic still records through the oldest-unpaid path; naming a past month asks what it cost and settles that month; a month before joining is refused and leaves no cycle; clearing returns to Automatic |

## Gotchas for whoever is next

- Widget-testing a recorded payment needs `tester.runAsync` with a **3 second**
  delay: rendering the receipt is real file I/O the fake clock will not drive,
  and 500ms is not enough.
- The Record Payment dialog scrolls. `Confirm Payment` is laid out below the
  fold once a month is named, so a test must `ensureVisible` before tapping or
  the tap lands on the modal barrier — `warnIfMissed` prints a warning rather
  than failing, so it looks like the button simply did nothing.
- The repo is **hand-formatted**. Do not run `dart format`.
