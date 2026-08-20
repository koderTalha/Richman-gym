# Self-update — design

**Date:** 2026-08-20
**Status:** implemented in 1.1.0

The gym's computer runs a packaged Windows build that somebody installs by hand.
Every fix therefore reaches the owner only when a person remembers to download an
installer and run it, which in practice means the gym runs an old version
indefinitely. This adds an update path the app can drive itself.

## Constraints this had to fit

- **Zero recurring cost.** No update server, no hosting bill.
- **A till machine.** Nothing may close the app while somebody is mid-payment.
- **Nobody knows the administrator password.** The install cannot prompt for one.
- **The gym is offline sometimes.** A failed check is normal, not an error.

## What made this cheap

The distribution already in place turned out to be most of the answer:

| Already true | Why it matters |
|---|---|
| The repo is public | The releases API and asset downloads need no token, so there is no credential to embed in a desktop app |
| Releases are tagged `v1.0.3` with `RichManFitness-Setup-1.0.3.exe` | A predictable asset name to look for |
| `PrivilegesRequired=lowest` | A silent install raises no administrator prompt |
| Fixed `AppId` | A new version replaces the old one in place |
| `CloseApplications=yes` | The installer handles a running copy |

## Decisions

**One-click, not silent.** A banner offers the update; nothing installs without a
deliberate press. A till that closes itself mid-transaction would be worse than a
till running last month's build.

**Checked on startup, at most once a day.** The gym's PC is opened each morning,
so an update lands within a day of release without a working session ever being
interrupted. A manual *Check for updates* in Settings ignores the throttle.

**Rolled by hand rather than WinSparkle.** `auto_updater` would mean an appcast
XML, EdDSA key management and a native plugin, to reach a feed we already
publish. A small service over `http` fits the existing architecture and is
testable without a Windows machine.

**A backup is taken first, always.** The app's own daily snapshot runs *after* the
database is opened, i.e. after a new version's migration. The pre-update backup is
therefore the only copy that predates it. If it fails, the update is abandoned.

## Order of operations

Refusing at any step leaves the installed version untouched:

1. Take a backup with `VACUUM INTO` into the folder the restore UI already lists.
2. Download the installer to `updates/` under the app-support folder.
3. Verify SHA-256 against the digest published with the release. **Nothing
   unverified is ever executed**; a mismatch deletes the file.
4. Start the installer detached with `/VERYSILENT /NORESTART`, close the database,
   exit. The installer relaunches the app on the new version.

## Refusals

The check returns "no update" rather than guessing, for: an unparseable tag, a
pre-release tag, a version equal to or older than the installed one, a missing
installer asset, **a missing checksum asset**, a non-HTTPS URL, and a host that is
not GitHub. The last two matter because this URL becomes an executable running on
the gym's computer.

## Components

- `domain/app_version.dart` — numeric comparison. Text comparison sorts `1.0.10`
  below `1.0.9`, which would hide every release after the ninth patch.
- `services/update/update_service.dart` — check, download, verify, launch.
  Platform gate and process launcher injected, so every path is testable off
  Windows.
- `bloc/update_bloc.dart` — one state machine behind both UI surfaces.
- `ui/widgets/update_banner.dart` — a strip under the top bar.
- `ui/settings/update_card.dart` — installed version, manual check, release notes.
- Schema **v8**: `gymSettings.lastUpdateCheckAt` and `dismissedUpdateVersion`.
- `AuditCategory.update` — available / installing / verify failed / backup failed,
  so "why is the gym still on the old version" is a question the Logs screen
  answers.

## Release pipeline

Pushing `v1.1.0` builds the installer, computes its SHA-256 **from the very file
being uploaded**, and publishes the release with both. The build fails if the tag
and `pubspec.yaml` disagree — otherwise every gym PC would look for an asset that
does not exist and silently never update.

## Known limitation

The installed 1.0.3 has no updater in it, so it cannot update itself. One build
must be installed by hand; every release after that self-updates.
