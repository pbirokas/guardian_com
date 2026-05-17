/**
 * Setzt APPWRITE_API_KEY als Environment-Variable für alle Cloud Functions.
 *
 * Hintergrund: Appwrite v1.9.0 injiziert den API Key nicht automatisch.
 * Die Funktion braucht ihn um Datenbank-Operationen mit API-Key-Auth
 * (statt User-Session) auszuführen — sonst 401 bei documentSecurity:true.
 *
 * Usage:
 *   node set-function-vars.js            (setzt/überschreibt bei allen Functions)
 *   node set-function-vars.js --dry-run  (zeigt nur was getan werden würde)
 *
 * Idempotent: existierende Variable wird überschrieben (delete + create).
 */

import { config } from 'dotenv';
import { Client, Functions } from 'node-appwrite';

config();

const DRY_RUN = process.argv.includes('--dry-run');

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const functions = new Functions(client);

const FUNCTION_IDS = [
  'cleanup-expired-announcements',
  'cleanup-expired-polls',
  'cleanup-old-messages',
  'get-child-summary',
  'on-child-org-invite',
  'on-claim-confirmed',
  'on-claim-request',
  'on-member-guardians-changed',
  'on-new-announcement',
  'on-new-conversation-request',
  'on-new-invitation',
  'on-new-message',
  'on-new-report',
  'on-org-admin-transferred',
  'on-parent-consent',
  'on-poll-vote',
  'process-my-invitations',
  'revoke-connection',
];

const API_KEY_VALUE = process.env.APPWRITE_API_KEY;

async function setVarForFunction(fnId) {
  // Bestehende Variablen auflisten um Duplikate zu vermeiden
  let existingVarId = null;
  try {
    const vars = await functions.listVariables(fnId);
    const existing = vars.variables.find((v) => v.key === 'APPWRITE_API_KEY');
    if (existing) existingVarId = existing.$id;
  } catch (e) {
    console.error(`  ✗ ${fnId}: listVariables failed — ${e.message}`);
    return false;
  }

  if (DRY_RUN) {
    console.log(`  [DRY] ${fnId}: would ${existingVarId ? 'update' : 'create'} APPWRITE_API_KEY`);
    return true;
  }

  try {
    if (existingVarId) {
      // Delete first (handles secret→non-secret transition)
      await functions.deleteVariable(fnId, existingVarId);
    }
    await functions.createVariable(fnId, 'APPWRITE_API_KEY', API_KEY_VALUE);
    console.log(`  ✓ ${fnId}: ${existingVarId ? 're-created' : 'created'}`);
    return true;
  } catch (e) {
    console.error(`  ✗ ${fnId}: ${e.message}`);
    return false;
  }
}

async function main() {
  console.log('=== set-function-vars ===');
  console.log(`Mode: ${DRY_RUN ? 'DRY RUN' : 'LIVE'}`);
  console.log(`Setting APPWRITE_API_KEY for ${FUNCTION_IDS.length} functions...\n`);

  let ok = 0;
  let fail = 0;
  for (const fnId of FUNCTION_IDS) {
    const success = await setVarForFunction(fnId);
    success ? ok++ : fail++;
  }

  console.log(`\nDone: ${ok} OK, ${fail} failed`);
  if (!DRY_RUN && ok > 0) {
    console.log('\nIMPORTANT: Functions müssen neu deployed werden damit die Variable greift:');
    console.log('  appwrite push function');
  }
}

main().catch((e) => {
  console.error('Fatal:', e.message);
  process.exit(1);
});
