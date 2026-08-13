# Rich Man Fitness

Desktop software for running a gym: members, payments, receipts, and sending
those receipts to members on WhatsApp.

It replaces an Excel ledger and the manual work around it — recording a payment,
writing a receipt by hand, and sending it one message at a time.

## Why it is a desktop app

The gym owner is the only user, so the software never needs to be on the
internet. Running it on the gym's own computer means **no hosting bill, no
monthly fee, and member data never leaves the premises**. The whole dataset is a
single SQLite file that can be copied to a USB stick.

Sending receipts over the Meta WhatsApp Cloud API still works from a local
machine — it is an outbound HTTPS call, not a server that needs an address.

## The app

Everything lives in [`rmf_desktop/`](rmf_desktop/). See its
[README](rmf_desktop/README.md) for how to run it, how the code is laid out, and
**how to add a feature without losing the gym's data**.

```bash
cd rmf_desktop
flutter run -d macos     # or -d windows
```

## Building the Windows .exe

Pushing to `main` builds it automatically — see
[`.github/workflows/windows-build.yml`](.github/workflows/windows-build.yml).
Download the result from the run's **Artifacts** section.

Flutter cannot cross-compile Windows from macOS or Linux, which is why the build
runs on a GitHub-hosted Windows machine rather than a developer's laptop.

## Documentation

- [`docs/`](docs/) — the original design spec and implementation plan
- [`Gym Management Code Prompt.md`](Gym%20Management%20Code%20Prompt.md) — the
  original brief the project started from

Both describe an earlier web-based approach that was replaced by this desktop
app; they are kept for the requirements and business rules they capture, not as
a description of the current architecture.
