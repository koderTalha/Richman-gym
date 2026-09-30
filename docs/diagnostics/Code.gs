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

/** Far above a real bundle (a few hundred KB today) and far below the
 *  ~50MB an Apps Script request can carry. */
var MAX_BYTES = 30 * 1024 * 1024;

/** A gym sends one when something is wrong. Twenty in a day is not that. */
var DAILY_LIMIT = 20;

var MAGIC = 'RMFDIAG1';

function doPost(e) {
  try {
    var body = JSON.parse(e.postData.contents);
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
    var gym = clean(body.gym, 80) || 'Unknown gym';
    var version = clean(body.version, 20) || 'unknown';

    var file = folder().createFile(
      Utilities.newBlob(bytes, 'application/octet-stream', name));

    MailApp.sendEmail({
      to: Session.getEffectiveUser().getEmail(),
      subject: 'Rich Man Fitness: diagnostics from ' + gym,
      body:
        gym + ' sent a diagnostics bundle.\n\n' +
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

function clean(value, max) {
  return typeof value === 'string'
    ? value.replace(/[\r\n]+/g, ' ').trim().slice(0, max)
    : '';
}
