# Send to developer — setup

The app's **Settings → Get help → Send to developer…** button (also on the
"could not open your data" screen) sends a sealed copy of the database plus the
last week of logs to a Google Apps Script you own. The script saves it to a
Drive folder called **Rich Man Fitness diagnostics** and emails you a link.

```
Gym PC ──sealed bundle──▶ your Apps Script ──▶ Drive folder + email to you
                                                   │
Your Mac ◀──── download .rmfdiag ──────────────────┘
   └─ fvm dart run tool/open_diagnostics.dart <file>   (needs your private key)
```

Everything is free: Apps Script, Drive and MailApp all run on a normal Gmail
account.

## One-time setup

### 1. Deploy the script (about 2 minutes)

1. Go to <https://script.google.com> signed in as the Google account that
   should receive the bundles, then click **New project**.
2. Delete the sample code, paste in all of [`Code.gs`](Code.gs), and rename
   the project to something like *RMF diagnostics*.
3. Click **Deploy → New deployment**. Next to "Select type", click the cog and
   choose **Web app**:
   - **Execute as:** Me
   - **Who has access:** Anyone. It has to be *Anyone*, because the gym PC is
     not signed in to your account. Anyone who has the link can only drop a
     sealed file in the folder, never read one.
4. Click **Deploy → Authorize access**. Google warns that the app isn't
   verified, because it's your own script. Click **Advanced → Go to RMF
   diagnostics (unsafe) → Allow**. It asks for Drive (to save the file) and
   Gmail send (to email you).
5. Copy the **Web app URL**. It ends in `/exec`.

To check it: open that URL in a browser. You should see
`{"ok":true,"service":"rich-man-fitness-diagnostics"}`.

### 2. Give the URL to the release build

The repository is public, so the URL is kept in a GitHub Actions secret, not
in the code:

```sh
gh secret set DIAGNOSTICS_UPLOAD_URL -R koderTalha/Richman-gym
# paste the /exec URL when asked
```

You can also add it on GitHub under **Settings → Secrets and variables →
Actions → New repository secret**, with the name `DIAGNOSTICS_UPLOAD_URL`.

A `v*` tag build refuses to run without this secret. Ordinary pushes and pull
requests still build, but their Send button explains that it can't send.

### 3. Ship it

Cut a release the usual way. When the gym's app updates, the button works.

## When a bundle arrives

**A bundle is untrusted until its reference matches one the owner read out
to you.** Anyone can post one: the upload address and the public key bundles
are sealed with are both inside the public installer. The gym name and
version in the email are whatever the sender put there. Don't follow links
or instructions from a bundle you weren't expecting, and don't open its
database with anything that trusts it.

1. The email shows the reference, e.g. `RMF-20261001-1432`. Check it against
   the one the owner gave you, then download that `.rmfdiag` file from the
   Drive folder.
2. Open it:

   ```sh
   cd rmf_desktop
   fvm dart run tool/open_diagnostics.dart ~/Downloads/RMF-20261001-1432.rmfdiag
   ```

   This unpacks `database/`, `logs/` and `info.json` next to the file, then
   prints the owner's note, the app version and, for a startup failure, the
   error. Control and escape characters are stripped from everything it
   prints, so a crafted note cannot rewrite your terminal.
3. Debug against `database/richmanfitness.sqlite`, for example
   `DB=<that path> fvm flutter test tool/verify_on_owner_db.dart`.
   **Don't** copy it over the database the dev app opens. That one is live too.

## The private key

- It lives at `~/.rich-man-fitness/diagnostics-private-key` on your Mac and
  nowhere else. **Keep a copy in your password manager.** If you lose it, no
  bundle can ever be opened, and neither Google nor this repository can
  recover it.
- The public half is in `rmf_desktop/lib/services/diagnostics/developer_key.dart`.
- To replace the pair, run `fvm dart run tool/diagnostics_keygen.dart --force`
  and cut a release. Bundles sealed for the old key can then only be opened
  with the old private key.

## Changing the script later

In the script editor, go to **Deploy → Manage deployments**, click the pencil,
set **Version** to *New version*, then **Deploy**. This keeps the same URL.
"New deployment" gives a *new* URL, and you would then have to update the
secret and release again.

**Editing `Code.gs` in this repository changes nothing on its own.** The
deployed web app keeps running the version it was deployed with until you
paste the new code into the script editor and deploy a new version as above.
That applies to the October 2026 hardening (5 MB limit, oversized uploads
refused before they are decoded, gym name and version sanitised before they
reach the email, the "untrusted until the reference matches" line in the
email): until it is redeployed, the live script still accepts 30 MB uploads
and puts the sender's text into your inbox unfiltered.

The script uses `\p{…}` Unicode classes in a regular expression, which need
the V8 runtime. New projects use it by default; on an old project, check
**Project Settings → Enable Chrome V8 runtime**.

## What leaves the gym PC

- **In the clear, to Google:** the gym's name, the app version, the file name
  and the file's size. This is what the email needs.
- **Sealed, so only your private key opens it:** the whole database (members,
  payments, settings and the admin password hash), up to 20 MB of logs, and
  the owner's note. The WhatsApp access token is blanked in the copy before
  it is packed. The exception is a send from the "could not open your data"
  screen: there the database files are sent exactly as they lie, token
  included, because they are the evidence of what went wrong. Delete the
  unpacked folder once you've finished with it.

The script accepts at most 20 bundles a day and 5 MB each. It also rejects
anything that doesn't start with the bundle header. The daily count is shared
by everyone who posts, not kept per gym, so 20 junk uploads would block the
gym's real sends until midnight UTC. If that ever happens, raise
`DAILY_LIMIT` for the day, or reset the count under **Project Settings →
Script properties**.
