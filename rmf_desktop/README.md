# Rich Man Fitness — Desktop App

A local-first Flutter desktop application for managing gym members, recording
payments, generating receipts, and sending them over WhatsApp.

No server, no hosting, no monthly cost: the app talks directly to a SQLite file
on the machine it runs on.

## Requirements

- Flutter 3.38.5 (Dart 3.10.4) — the version this project is pinned to via fvm
- No database server, no Docker, no Node

## Running

```bash
flutter run -d macos     # or -d windows on a Windows machine
```

## Code generation (Drift)

The database classes in `lib/data/database.g.dart` are generated from the table
definitions in `lib/data/tables.dart`. After changing a table, regenerate:

```bash
dart run build_runner build --force-jit
```

**`--force-jit` is required, not optional.** On Dart 3.10.4, build_runner 2.15.1
compiles the build script with `dart compile aot-snapshot`, which refuses to run
when any package in the dependency graph declares a native build hook. Two of
ours do (`sqlite3` via drift, and `objective_c` via path_provider on macOS), so
the default AOT path fails with a bare "Failed to compile build script".
`--force-jit` uses the JIT path instead and works.

The clean fix is Dart >= 3.11, where build_runner 2.15.2+ switches to
`dart build`. Once this project moves to a newer Flutter, drop the flag.

## Layout

```
lib/
  domain/      Pure business rules — no I/O, fully unit tested
                 member_status.dart    derived PAID/DUE/EXPIRED/INACTIVE
                 billing_period.dart   billing cycle maths
                 receipt_number.dart   RMF-2026-000184 formatting
                 money.dart            PKR formatting, integer minor units
                 phone.dart            E.164 normalization
  data/        Drift database
                 tables.dart           schema (hand written)
                 database.g.dart       generated — do not edit
test/
  domain_test.dart   39 tests covering every rule in domain/
```

## Design notes

**Money is stored as integer minor units (paisa)**, never floating point, so
amounts cannot drift through rounding.

**Payment status is never stored.** Whether a member is paid or due is derived
from whether a `Payment` row exists for the `MembershipPeriod` covering today.
There is deliberately no editable "status" column to fall out of sync.

**Nothing financial is deleted.** Members are soft-deactivated
(`deactivatedAt`); payments and receipts are immutable once written.

**A WhatsApp failure never rolls back a payment.** Payment, billing period and
receipt are written in one transaction; the WhatsApp send happens after that
transaction commits, and each attempt is recorded as its own row so failures
stay visible and retryable.

## Adding a feature without losing the gym's data

The owner's database lives outside the app, in their user data folder — not
beside the executable. Installing a new build replaces the program only; the
data is untouched. What has to be handled deliberately is a **schema change**.

When a release adds, removes or alters a column or table:

1. Change `lib/data/tables.dart`.
2. Increment `schemaVersion` in `lib/data/database.dart`.
3. Add a step to `onUpgrade` guarded by the previous version:

   ```dart
   if (from < 5) {
     await m.addColumn(members, members.dateOfBirth);
   }
   ```

   Use `addColumn` to add, `alterTable(TableMigration(table))` to change or drop
   a column (SQLite cannot drop one in place; drift rebuilds the table), and
   `deleteTable('name')` to remove a table.

4. **Add the new version to the loop in `test/migration_test.dart`** and run it.
   That test builds a database in the old shape, fills it with a member, a
   payment, a receipt and the admin login, opens it with the new code, and checks
   every one of them survived — including that the receipt counter did not reset
   and reissue a number already given to a member.

Never edit a migration that has already shipped: someone's installed copy has
already run it. Add a new step instead.

### Why the tests matter here

A broken migration does not crash — it silently drops rows. By the time anyone
notices, the backup that still had the data has usually been rotated away. The
migration tests are the only thing standing between a schema change and losing
a year of the gym's payment history.

### Belt and braces

An automatic backup is taken on launch (once a day, seven kept), so upgrading
leaves a restorable copy of the previous state. Take a manual backup to a USB
stick before installing a new version on the owner's machine anyway.

## Testing

```bash
flutter test
flutter analyze
```
