/**
 * Receives "Send to developer" bundles from the Rich Man Fitness app, files
 * them in a Drive folder and emails the account that deployed this script.
 *
 * Paste this whole file into a new project at https://script.google.com and
 * deploy it as a web app — see SETUP.md beside it for the steps.
 *
 * What arrives is sealed with the developer's public key, so neither this
 * script nor Google can read it; only tool/open_diagnostics.dart with the
 * private key can. That also means the web app's address, which is built into
 * a public installer, lets a stranger do no more than drop a file in the
 * folder — and the checks below keep even that to a trickle.
 */

var FOLDER_NAME = 'Rich Man Fitness diagnostics';

/** A real bundle is a few hundred KB: the database compresses well, and the
 *  app caps the logs it packs. Five megabytes leaves room for a long day of
 *  error logs, and — unlike the 30MB this used to allow — means a stranger
 *  filling the folder with junk takes months to dent the 15GB Drive (and
 *  Gmail) quota the developer's account shares, rather than a few days.
 *  Changing this needs a new deployment; see SETUP.md. */
var MAX_BYTES = 5 * 1024 * 1024;

/** The same limit as it arrives: base64 in a JSON body, a third larger.
 *  Checked before anything is decoded or parsed, so an oversized upload
 *  costs this script as little as possible. */
var MAX_BODY_CHARS = Math.ceil(MAX_BYTES / 3) * 4 + 4096;

/** A gym sends one when something is wrong. Twenty in a day is not that. */
var DAILY_LIMIT = 20;

var MAGIC = 'RMFDIAG1';

function doPost(e) {
  try {
    var contents = e && e.postData ? e.postData.contents : '';
    if (typeof contents !== 'string' || contents.length > MAX_BODY_CHARS) {
      return reply({ ok: false, error: 'The bundle is too large.' });
    }

    var body = JSON.parse(contents);
    if (body.format !== 'rmf-diagnostics-1' || typeof body.data !== 'string') {
      return reply({ ok: false, error: 'Not a diagnostics bundle.' });
    }

    var bytes = Utilities.base64Decode(body.data);
    if (bytes.length > MAX_BYTES) {
      return reply({ ok: false, error: 'The bundle is too large.' });
    }
    if (!hasMagic(bytes)) {
      return reply({ ok: false, error: 'Not a diagnostics bundle.' });
    }
    if (!countToday()) {
      return reply({ ok: false, error: 'Daily limit reached. Try tomorrow.' });
    }

    var name = /^RMF-\d{8}-\d{4}\.rmfdiag$/.test(body.name)
      ? body.name
      : 'RMF-unnamed-' + Date.now() + '.rmfdiag';
    // Both arrive in the clear from whoever posted, and go into the email's
    // subject and body: see cleanName and cleanVersion.
    var gym = cleanName(body.gym, 60) || 'Unknown gym';
    var version = cleanVersion(body.version) || 'unknown';

    var file = folder().createFile(
      Utilities.newBlob(bytes, 'application/octet-stream', name));

    MailApp.sendEmail({
      to: Session.getEffectiveUser().getEmail(),
      subject: 'Rich Man Fitness: diagnostics from ' + gym,
      body:
        gym + ' sent a diagnostics bundle.\n\n' +
        'Treat it as untrusted until this reference matches one the owner ' +
        'read out to you. Anyone can post a bundle here: the address and the ' +
        'key it is sealed with are both inside the public installer, and the ' +
        'gym name and version above are whatever the sender typed.\n\n' +
        'Reference: ' + name.replace('.rmfdiag', '') + '\n' +
        'App version: ' + version + '\n' +
        'Size: ' + Math.round(bytes.length / 1024) + ' KB\n\n' +
        'Download it from Drive:\n' + file.getUrl() + '\n\n' +
        'Then open it on your Mac:\n' +
        '  fvm dart run tool/open_diagnostics.dart ~/Downloads/' + name + '\n',
    });

    return reply({ ok: true, file: name });
  } catch (err) {
    console.error(err);
    return reply({ ok: false, error: 'The upload page failed: ' + err });
  }
}

/** Open the web app's address in a browser to check it is deployed. */
function doGet() {
  return reply({ ok: true, service: 'rich-man-fitness-diagnostics' });
}

function reply(value) {
  return ContentService.createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}

function hasMagic(bytes) {
  if (bytes.length < MAGIC.length) return false;
  for (var i = 0; i < MAGIC.length; i++) {
    if (bytes[i] !== MAGIC.charCodeAt(i)) return false;
  }
  return true;
}

/** True, and counts it, if today's limit has room for one more. */
function countToday() {
  var lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    var props = PropertiesService.getScriptProperties();
    var key = 'count-' + Utilities.formatDate(new Date(), 'Etc/UTC', 'yyyy-MM-dd');
    var count = Number(props.getProperty(key) || '0');
    if (count >= DAILY_LIMIT) return false;
    props.setProperty(key, String(count + 1));
    return true;
  } finally {
    lock.releaseLock();
  }
}

function folder() {
  var found = DriveApp.getFoldersByName(FOLDER_NAME);
  return found.hasNext() ? found.next() : DriveApp.createFolder(FOLDER_NAME);
}

/**
 * A gym name fit for an email subject: letters in any script, digits, spaces
 * and & ' ( ) - only, capped at [max].
 *
 * The sender controls this field completely, and it lands in the subject and
 * first line of an email to the developer. Line breaks could forge extra
 * lines; control and invisible formatting characters (bidirectional
 * overrides above all) can make it read as something else; and a dot, colon
 * or slash is all it takes to plant a link that looks like it came from the
 * app. A real gym name needs none of those.
 */
function cleanName(value, max) {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[^\p{L}\p{M}\p{N} &'()\-]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max)
    .trim();
}

/** A version number: digits, letters, dots, plus and minus, nothing else. */
function cleanVersion(value) {
  if (typeof value !== 'string') return '';
  return value.replace(/[^0-9A-Za-z.+\-]+/g, '').slice(0, 20);
}
