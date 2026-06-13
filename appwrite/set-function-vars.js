/**
 * Setzt APPWRITE_API_KEY und APPWRITE_ENDPOINT als Environment-Variablen für alle Cloud Functions.
 *
 * Hintergrund: Appwrite injiziert APPWRITE_FUNCTION_API_ENDPOINT im Schedule-Trigger auf
 * localhost, was zu Connection-Fehlern führt. Stattdessen wird APPWRITE_ENDPOINT explizit
 * als Function-Variable gesetzt.
 *
 * Usage:
 *   node set-function-vars.js            (setzt/überschreibt bei allen Functions)
 *   node set-function-vars.js --dry-run  (zeigt nur was getan werden würde)
 *
 * Idempotent: existierende Variablen werden überschrieben (delete + create).
 */

import { config } from 'dotenv';
import { Client, Functions } from 'node-appwrite';

config();

const DRY_RUN = process.argv.includes('--dry-run');

const API_KEY_VALUE = process.env.APPWRITE_API_KEY;
const ENDPOINT_VALUE = process.env.APPWRITE_ENDPOINT;

if (!API_KEY_VALUE || !ENDPOINT_VALUE) {
  console.error('Fatal: APPWRITE_API_KEY or APPWRITE_ENDPOINT not set in environment');
  process.exit(1);
}

const client = new Client()
  .setEndpoint(ENDPOINT_VALUE)
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(API_KEY_VALUE);

const functions = new Functions(client);

const FUNCTION_IDS = [
  'cleanup-expired-announcements',
  'cleanup-expired-polls',
  'cleanup-old-messages',
  'daily-error-report',
  'get-child-summary',
  'merge-oauth-account',
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
  'mark-as-read',
  'admin-member-action',
];

const VARS_TO_SET = [
  { key: 'APPWRITE_API_KEY', value: API_KEY_VALUE },
  { key: 'APPWRITE_ENDPOINT', value: ENDPOINT_VALUE },
];

async function setVarForFunction(fnId) {
  let existingVars = [];
  try {
    const vars = await functions.listVariables(fnId);
    existingVars = vars.variables;
  } catch (e) {
    const code = e.code ?? e.status ?? '?';
    console.error(`  ✗ ${fnId}: listVariables failed — ${e.message} (code=${code})`);
    return false;
  }

  if (DRY_RUN) {
    for (const { key } of VARS_TO_SET) {
      const exists = existingVars.find((v) => v.key === key);
      console.log(`  [DRY] ${fnId}: would ${exists ? 'update' : 'create'} ${key}`);
    }
    return true;
  }

  try {
    for (const { key, value } of VARS_TO_SET) {
      const existing = existingVars.find((v) => v.key === key);
      if (existing) await functions.deleteVariable(fnId, existing.$id);
      await functions.createVariable(fnId, key, value);
    }
    console.log(`  ✓ ${fnId}: APPWRITE_API_KEY + APPWRITE_ENDPOINT set`);
    return true;
  } catch (e) {
    const code = e.code ?? e.status ?? '?';
    console.error(`  ✗ ${fnId}: ${e.message} (code=${code})`);
    return false;
  }
}

async function main() {
  console.log('=== set-function-vars ===');
  console.log(`Mode: ${DRY_RUN ? 'DRY RUN' : 'LIVE'}`);
  console.log(`Setting APPWRITE_API_KEY + APPWRITE_ENDPOINT for ${FUNCTION_IDS.length} functions...\n`);

  const results = [];
  for (const fnId of FUNCTION_IDS) {
    results.push(await setVarForFunction(fnId));
  }
  const ok = results.filter(Boolean).length;
  const fail = results.length - ok;

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
