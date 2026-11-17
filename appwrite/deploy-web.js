/**
 * Baut die Flutter-Web-App und spielt sie als neues Deployment der
 * Appwrite-Site `guardian-web` (https://app.guardian-com.de) ein.
 *
 * Ablauf:
 *   1. Build-Nummer = Anzahl der Git-Commits (`git rev-list --count HEAD`) —
 *      dieselbe Regel wie der Android-versionCode (build.gradle.kts), damit
 *      „Über die App“ im Web dieselbe Build-Nummer zeigt wie in der Android-App.
 *      Versionsname kommt wie gewohnt aus pubspec.yaml.
 *   2. `build/web` löschen und `flutter build web --release` mit dieser
 *      Build-Nummer ausführen (sauberer Build: neue Dateien in `web/` landen
 *      bei inkrementellen Builds sonst nicht immer in `build/web`).
 *   3. `build/web` als tar.gz packen und per Sites-API hochladen (in 5-MB-Teilen,
 *      wie die Appwrite-SDKs es tun).
 *   4. Warten, bis das Deployment „ready“ ist, und es ausdrücklich aktivieren
 *      (beim CLI-Upload griff `--activate` nicht zuverlässig).
 *   5. Prüfen, dass https://app.guardian-com.de/version.json die neue
 *      Build-Nummer ausliefert.
 *
 * Nutzung (aus `appwrite/`):
 *   node deploy-web.js                 # bauen + hochladen + aktivieren
 *   node deploy-web.js --dry-run       # nur bauen und packen, nichts hochladen
 *   node deploy-web.js --skip-build    # vorhandenes build/web hochladen
 *   node deploy-web.js --site-id=xyz   # andere Site (Standard: guardian-web)
 *   npm run deploy-web                 # = node deploy-web.js
 *
 * Voraussetzung: `.env` mit APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID und
 * APPWRITE_DEPLOY_KEY — ein eigener API-Key nur mit den Scopes `sites.read` +
 * `sites.write` (bewusst getrennt vom Functions-Key APPWRITE_API_KEY, der diese
 * Rechte nicht braucht). Fehlt er, wird APPWRITE_API_KEY versucht. Flutter im PATH,
 * `tar` im PATH (ab Windows 10 vorhanden), Node.js ≥ 18.
 */

import { config } from 'dotenv';
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, readFileSync, rmSync, statSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

config();

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..');
const APP_DIR = join(REPO, 'guardian_app');
const BUILD_DIR = join(APP_DIR, 'build', 'web');
const PUBLIC_URL = 'https://app.guardian-com.de';
const CHUNK_SIZE = 5 * 1024 * 1024;

const args = process.argv.slice(2);
const flag = (name) => args.includes(`--${name}`);
const opt = (name, fallback) => {
  const hit = args.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
};

const DRY_RUN = flag('dry-run');
const SKIP_BUILD = flag('skip-build');
const SITE_ID = opt('site-id', 'guardian-web');

const { APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID } = process.env;
const DEPLOY_KEY = process.env.APPWRITE_DEPLOY_KEY || process.env.APPWRITE_API_KEY;

function fail(msg) {
  console.error(`\n✗ ${msg}`);
  process.exit(1);
}

function git(...gitArgs) {
  return execFileSync('git', gitArgs, { cwd: REPO, encoding: 'utf8' }).trim();
}

// ── 1. Version bestimmen ─────────────────────────────────────────────────────
const buildNumber = git('rev-list', '--count', 'HEAD');
const commit = git('rev-parse', '--short', 'HEAD');
const branch = git('rev-parse', '--abbrev-ref', 'HEAD');
const pubspec = readFileSync(join(APP_DIR, 'pubspec.yaml'), 'utf8');
const versionName = (pubspec.match(/^version:\s*([^+\s]+)/m) || [])[1] || '?';
const dirty = git('status', '--porcelain', '--', 'guardian_app').length > 0;

console.log(`Web-Deploy: Version ${versionName} (Build ${buildNumber}), Commit ${commit} auf ${branch}`);
if (branch !== 'main') console.warn(`⚠ Nicht auf main (sondern ${branch}).`);
if (dirty) {
  console.warn('⚠ guardian_app/ hat nicht committete Änderungen — sie landen im Build,');
  console.warn('  die Build-Nummer entspricht aber nur dem letzten Commit.');
}

if (!DRY_RUN && (!APPWRITE_ENDPOINT || !APPWRITE_PROJECT_ID || !DEPLOY_KEY)) {
  fail('APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID und APPWRITE_DEPLOY_KEY müssen in appwrite/.env stehen.');
}

// ── 2. Bauen ─────────────────────────────────────────────────────────────────
if (SKIP_BUILD) {
  if (!existsSync(BUILD_DIR)) fail(`--skip-build, aber ${BUILD_DIR} existiert nicht.`);
  console.log('\n→ Build übersprungen (vorhandenes build/web).');
} else {
  console.log('\n→ flutter build web …');
  rmSync(BUILD_DIR, { recursive: true, force: true });
  // Unter Windows ist `flutter` eine .bat-Datei und braucht eine Shell; als
  // ein String übergeben (feste Argumente, keine Nutzereingaben).
  const flutterCmd =
    `flutter build web --release --no-wasm-dry-run --build-number=${buildNumber}`;
  const res = process.platform === 'win32'
    ? spawnSync(flutterCmd, { cwd: APP_DIR, stdio: 'inherit', shell: true })
    : spawnSync('flutter', flutterCmd.split(' ').slice(1), { cwd: APP_DIR, stdio: 'inherit' });
  if (res.status !== 0) fail('flutter build web ist fehlgeschlagen.');
}

const builtVersion = JSON.parse(readFileSync(join(BUILD_DIR, 'version.json'), 'utf8'));
if (String(builtVersion.build_number) !== buildNumber && !SKIP_BUILD) {
  fail(`build/web/version.json meldet Build ${builtVersion.build_number}, erwartet ${buildNumber}.`);
}
for (const required of ['index.html', 'main.dart.js', 'pica.min.js', 'manifest.json']) {
  if (!existsSync(join(BUILD_DIR, required))) fail(`build/web/${required} fehlt.`);
}

// ── 3. Packen ────────────────────────────────────────────────────────────────
const archive = join(mkdtempSync(join(tmpdir(), 'guardian-web-')), 'guardian-web.tar.gz');
console.log(`\n→ Packe build/web → ${archive}`);
// Unter Windows das System-tar (bsdtar) nehmen: das GNU-tar aus Git Bash hält
// „C:\…“ für einen entfernten Host und bricht ab.
const winTar = join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'tar.exe');
const tarBin = process.platform === 'win32' && existsSync(winTar) ? winTar : 'tar';
execFileSync(tarBin, ['-czf', archive, '-C', BUILD_DIR, '.'], { stdio: 'inherit' });
const size = statSync(archive).size;
console.log(`  ${(size / 1024 / 1024).toFixed(1)} MB`);

if (DRY_RUN) {
  console.log('\n✓ Dry-Run: gebaut und gepackt, nichts hochgeladen.');
  process.exit(0);
}

// ── 4. Hochladen (chunked) ───────────────────────────────────────────────────
const api = (path) => `${APPWRITE_ENDPOINT.replace(/\/$/, '')}${path}`;
const baseHeaders = {
  'X-Appwrite-Project': APPWRITE_PROJECT_ID,
  'X-Appwrite-Key': DEPLOY_KEY,
};

async function call(method, path, body) {
  const res = await fetch(api(path), {
    method,
    headers: { ...baseHeaders, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status} ${data.message ?? ''}`);
  return data;
}

const site = await call('GET', `/sites/${SITE_ID}`).catch((e) =>
  fail(`Site „${SITE_ID}“ nicht abrufbar (${e.message}). Braucht APPWRITE_DEPLOY_KEY mit den Scopes sites.read + sites.write.`),
);
const previousDeployment = site.deploymentId;
console.log(`\n→ Lade hoch nach Site „${site.name}“ (aktiv bisher: ${previousDeployment || '–'})`);

const bytes = readFileSync(archive);
let deploymentId = null;
for (let start = 0; start < size; start += CHUNK_SIZE) {
  const end = Math.min(start + CHUNK_SIZE, size);
  const form = new FormData();
  form.append('code', new Blob([bytes.subarray(start, end)]), 'guardian-web.tar.gz');
  form.append('activate', 'true');
  const headers = { ...baseHeaders };
  if (size > CHUNK_SIZE) headers['Content-Range'] = `bytes ${start}-${end - 1}/${size}`;
  if (deploymentId) headers['x-appwrite-id'] = deploymentId;

  const res = await fetch(api(`/sites/${SITE_ID}/deployments`), { method: 'POST', headers, body: form });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) fail(`Upload fehlgeschlagen (${res.status}): ${data.message ?? ''}`);
  deploymentId = data.$id;
  console.log(`  ${Math.round((end / size) * 100)} %`);
}
console.log(`  Deployment ${deploymentId}`);

// ── 5. Auf „ready“ warten und aktivieren ─────────────────────────────────────
console.log('\n→ Warte auf Verarbeitung …');
const deadline = Date.now() + 10 * 60 * 1000;
let status = '';
while (Date.now() < deadline) {
  const dep = await call('GET', `/sites/${SITE_ID}/deployments/${deploymentId}`);
  if (dep.status !== status) {
    status = dep.status;
    console.log(`  Status: ${status}`);
  }
  if (status === 'ready') break;
  if (status === 'failed' || status === 'canceled') {
    fail(`Deployment ${status}. Build-Logs in der Console: Sites → ${site.name} → Deployments.`);
  }
  await new Promise((r) => setTimeout(r, 3000));
}
if (status !== 'ready') fail('Zeitüberschreitung: Deployment nach 10 Minuten nicht „ready“.');

const after = await call('GET', `/sites/${SITE_ID}`);
if (after.deploymentId !== deploymentId) {
  console.log('→ Aktiviere Deployment …');
  await call('PATCH', `/sites/${SITE_ID}/deployment`, { deploymentId });
}
console.log(`  Aktiv: ${deploymentId}`);

// ── 6. Live prüfen ───────────────────────────────────────────────────────────
console.log(`\n→ Prüfe ${PUBLIC_URL}/version.json …`);
let live = null;
for (let i = 0; i < 10; i++) {
  try {
    const res = await fetch(`${PUBLIC_URL}/version.json?t=${Date.now()}`, { cache: 'no-store' });
    live = await res.json();
    if (String(live.build_number) === buildNumber) break;
  } catch (_) {
    // Netzwerk/DNS (z. B. Pi-hole-Cache) — erneut versuchen
  }
  await new Promise((r) => setTimeout(r, 3000));
}
if (live && String(live.build_number) === buildNumber) {
  console.log(`\n✓ Live: Version ${live.version} (Build ${live.build_number}) unter ${PUBLIC_URL}`);
} else {
  console.warn(`\n⚠ Deployment ist aktiv, aber ${PUBLIC_URL}/version.json meldet noch`);
  console.warn(`  ${live ? `Build ${live.build_number}` : 'keine Antwort'} — evtl. Cache/DNS. Im Browser neu laden prüfen.`);
  console.warn(`  Rollback: in der Console das vorherige Deployment (${previousDeployment || '–'}) aktivieren.`);
}
