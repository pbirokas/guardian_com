/**
 * Functions per SDK deployen (statt `appwrite push functions`, das
 * buildSpecification/runtimeSpecification und deploymentRetention auf Default
 * zurücksetzt — siehe docs/security/collection-acl-hardening.md §5).
 *
 * - Bestehende Function: neues Deployment (tar.gz des Ordners functions/<id>),
 *   nach erfolgreichem Build explizit aktiviert (activate beim Upload greift
 *   auf Server 1.9 nicht zuverlässig). Einstellungen bleiben unverändert; weichen events/execute/
 *   timeout von appwrite.config.json ab, wird das nur ANGEZEIGT.
 * - Fehlende Function: wird mit den Werten aus appwrite.config.json angelegt;
 *   Spezifikation/Runtime übernimmt sie von --like=<functionId> (Default
 *   sync-conversation-permissions). Danach `node set-function-vars.js`.
 *
 * Standardmäßig Dry-Run (nur lesen).
 *
 * Nutzung (aus appwrite/, .env wie setup.js):
 *   node deploy-functions.js --only=self-service,conversation-action
 *   node deploy-functions.js --only=… --confirm=<projectId>
 */

import { config } from 'dotenv';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client, Functions } from 'node-appwrite';
import { InputFile } from 'node-appwrite/file';

config();

const here = dirname(fileURLToPath(import.meta.url));
const projectId = process.env.APPWRITE_PROJECT_ID;
const args = process.argv.slice(2);
const argValue = (n) => args.find((a) => a.startsWith(`--${n}=`))?.split('=')[1];
const confirmArg = argValue('confirm');
const CONFIRMED = confirmArg !== undefined && confirmArg === projectId;
const DRY = !CONFIRMED;
const ONLY = argValue('only')?.split(',').map((s) => s.trim()).filter(Boolean);
const LIKE = argValue('like') ?? 'sync-conversation-permissions';

if (confirmArg !== undefined && !CONFIRMED) {
  console.error(`✗ --confirm stimmt nicht mit APPWRITE_PROJECT_ID (${projectId}) überein. Abbruch.`);
  process.exit(1);
}
if (!ONLY || ONLY.length === 0) {
  console.error('✗ --only=<id,id,…> ist Pflicht (bewusst kein „alles deployen“).');
  process.exit(1);
}

const cfg = JSON.parse(readFileSync(join(here, 'appwrite.config.json'), 'utf8'));
const byId = new Map((cfg.functions ?? []).map((f) => [f.$id, f]));

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(projectId)
  .setKey(process.env.APPWRITE_API_KEY);
const functions = new Functions(client);

// Server 1.9 trennt Build-/Runtime-Spezifikation; SDK 14 kennt nur `specification`.
const specOf = (f) => f.specification ?? f.runtimeSpecification ?? f.buildSpecification;
const sorted = (a) => [...(a ?? [])].sort().join(',');

function pack(id) {
  const dir = join(here, 'functions', id);
  if (!existsSync(join(dir, 'src', 'main.js'))) throw new Error(`functions/${id}/src/main.js fehlt`);
  const outDir = mkdtempSync(join(tmpdir(), 'fn-'));
  // node_modules nicht mitschicken — der Build führt `npm install` aus.
  // Archiv über stdout und cwd statt Pfad-Argumenten: GNU-tar (Git-Bash) hält
  // `C:` sonst für einen Remote-Host.
  const tgz = execFileSync('tar', ['--exclude=node_modules', '-czf', '-', '.'],
    { cwd: dir, maxBuffer: 64 * 1024 * 1024 });
  writeFileSync(join(outDir, `${id}.tar.gz`), tgz);
  return join(outDir, `${id}.tar.gz`);
}

async function main() {
  console.log(`=== deploy-functions — Projekt ${projectId} — ${DRY ? 'DRY RUN' : 'LIVE'} ===\n`);
  let like = null;
  for (const id of ONLY) {
    const want = byId.get(id);
    if (!want) {
      console.error(`✗ ${id}: nicht in appwrite.config.json`);
      continue;
    }
    let live = null;
    try {
      live = await functions.get(id);
    } catch (e) {
      if (e.code !== 404) throw e;
    }

    if (!live) {
      like ??= await functions.get(LIKE);
      console.log(`+ ${id}: fehlt → anlegen (runtime ${like.runtime}, spec ${specOf(like)}, ` +
        `execute [${want.execute}], events [${want.events}], timeout ${want.timeout})`);
      if (!DRY) {
        await functions.create(id, want.name, like.runtime, want.execute, want.events,
          want.schedule || undefined, want.timeout, true, true, want.entrypoint, want.commands,
          undefined, undefined, undefined, undefined, undefined, undefined, undefined,
          undefined, undefined, undefined, specOf(like));
        console.log('    ✓ angelegt — Spezifikation in der Console prüfen; Variablen: node set-function-vars.js');
      }
    } else {
      const diffs = [];
      if (sorted(live.events) !== sorted(want.events)) diffs.push(`events live [${live.events}] ≠ config [${want.events}]`);
      if (sorted(live.execute) !== sorted(want.execute)) diffs.push(`execute live [${live.execute}] ≠ config [${want.execute}]`);
      if (live.timeout !== want.timeout) diffs.push(`timeout live ${live.timeout} ≠ config ${want.timeout}`);
      console.log(`~ ${id}: neues Deployment (aktiv jetzt: ${live.deploymentId ?? live.deployment ?? '–'})`);
      for (const d of diffs) console.log(`    ! ${d} (wird NICHT geändert)`);
      const vars = await functions.listVariables(id);
      const keys = vars.variables.map((v) => v.key);
      for (const k of ['APPWRITE_API_KEY', 'APPWRITE_ENDPOINT']) {
        if (!keys.includes(k)) console.log(`    ! Variable ${k} fehlt — node set-function-vars.js`);
      }
    }

    const file = pack(id);
    if (DRY) {
      console.log(`    (Dry-Run) Paket gebaut: ${file}`);
      continue;
    }
    const dep = await functions.createDeployment(id, InputFile.fromPath(file, `${id}.tar.gz`), true,
      want.entrypoint, want.commands);
    const prev = live?.deploymentId ?? live?.deployment ?? '–';
    console.log(`    ✓ Deployment ${dep.$id} hochgeladen (Rollback = vorige Deployment ${prev} aktivieren)`);
    await activateWhenReady(id, dep.$id);
  }
}

// `activate: true` beim Upload greift auf Server 1.9.x nicht zuverlässig
// (2026-11-25: beide Builds `ready`, aber die alte Version blieb aktiv — wie
// bei deploy-web.js). Deshalb auf den Build warten und explizit aktivieren.
// Per fetch mit Timeout: SDK 14 kennt `PATCH /functions/{id}/deployment` nicht.
async function activateWhenReady(id, depId) {
  const ep = process.env.APPWRITE_ENDPOINT.replace(/\/$/, '');
  const headers = {
    'Content-Type': 'application/json',
    'X-Appwrite-Project': projectId,
    'X-Appwrite-Key': process.env.APPWRITE_API_KEY,
  };
  const call = async (method, path, body) => {
    const r = await fetch(ep + path, {
      method, headers, body: body && JSON.stringify(body), signal: AbortSignal.timeout(30000),
    });
    const json = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(`${method} ${path}: ${r.status} ${json.message ?? ''}`);
    return json;
  };
  const deadline = Date.now() + 10 * 60 * 1000;
  let status = '';
  while (Date.now() < deadline) {
    status = (await call('GET', `/functions/${id}/deployments/${depId}`)).status;
    if (status === 'ready' || status === 'failed') break;
    await new Promise((r) => setTimeout(r, 5000));
  }
  if (status !== 'ready') {
    console.error(`    ✗ Build ${status || 'unbekannt'} — NICHT aktiviert (alte Version bleibt aktiv)`);
    return;
  }
  const fn = await call('GET', `/functions/${id}`);
  if (fn.deploymentId !== depId) await call('PATCH', `/functions/${id}/deployment`, { deploymentId: depId });
  const after = await call('GET', `/functions/${id}`);
  console.log(after.deploymentId === depId
    ? `    ✓ aktiv: ${depId}`
    : `    ✗ Aktivieren fehlgeschlagen (aktiv: ${after.deploymentId}) — in der Console aktivieren`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
