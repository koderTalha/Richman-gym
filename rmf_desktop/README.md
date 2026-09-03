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
                 app_version.dart      numeric version comparison
  data/        Drift database
                 tables.dart           schema (hand written)
                 database.g.dart       generated — do not edit
  services/
    whatsapp/  message_texts.dart          every message a member is sent
               whatsapp_client.dart        the provider interface
               meta_client.dart            Meta WhatsApp Cloud API
               member_welcome_service.dart the one-off welcome message
    update/    update_service.dart         check, verify, install
               update_cache.dart           the last answer GitHub gave
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

**A new member is welcomed once, after they are saved.** Adding a member by
hand sends them the welcome message in
`services/whatsapp/member_welcome_service.dart` — after the member row is
committed, never inside it, and never at the cost of the member if the send
fails. It happens exactly once per member: the audit log is the durable record
that it already went out, and an in-process guard covers the seconds before that
row exists. **Importing from Excel deliberately sends nothing** — nobody wants
five hundred messages fired at once, so the importer writes members directly
rather than through the form's path.

**Every message a member receives is written in one file**,
`services/whatsapp/message_texts.dart`. The gym's name comes from the settings
row, so renaming the gym renames it in every message.

**WhatsApp credentials are configuration, not code.** They live in the settings
row and are edited in Settings → WhatsApp; no token, phone number id or business
account id is compiled into the app or written to a log. There is no `.env` file
because the owner installs a packaged app and has no terminal to edit one in.

## Updating itself

The app asks GitHub once a day for `releases/latest`, and only offers a release
that is newer, correctly tagged, has both an installer and a published SHA-256,
and points at GitHub's own hosts. Two rules keep that from going quiet:

- **A check counts as done only when GitHub answered the question.** A timeout,
  a rate limit or an HTTP error leaves the once-a-day marker alone, so the next
  launch tries again instead of the gym hearing nothing until tomorrow. Within a
  session a failure is not retried for 30 minutes, so a rebuilding screen cannot
  hammer the API.
- **The answer is cached, not just the fact that it was asked.** The raw payload
  and its ETag are kept in `update_check.json` beside the database. Reopening the
  app the same day shows the waiting update again without a request, and the
  request that is made is conditional — a 304 costs no rate limit at all. The
  raw payload is re-read against the installed version each time, so the banner
  disappears by itself once the update has been applied.

Updates are Windows-only and are disabled outright if the installed version
cannot be read from the executable: every release looks newer than an unknown
version, and this code downloads and runs what it decides is newer.

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
