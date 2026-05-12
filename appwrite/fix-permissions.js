/**
 * One-time script: enable documentSecurity on all existing Appwrite collections.
 *
 * Run ONCE against the live instance after updating setup.js.
 * Safe to re-run (idempotent).
 *
 * Usage:
 *   node fix-permissions.js
 *
 * Required env vars (same as setup.js):
 *   APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY
 */

import { config } from 'dotenv';
import { Client, Databases } from 'node-appwrite';

config();

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const db = new Databases(client);
const DB_ID = 'guardian';

const collections = [
  { id: 'users',              name: 'Users' },
  { id: 'organizations',      name: 'Organizations' },
  { id: 'members',            name: 'Members' },
  { id: 'conversations',      name: 'Conversations' },
  { id: 'messages',           name: 'Messages' },
  { id: 'polls',              name: 'Polls' },
  { id: 'claim_requests',     name: 'ClaimRequests' },
  { id: 'scheduled_messages', name: 'ScheduledMessages' },
  { id: 'announcements',      name: 'Announcements' },
  { id: 'invitations',        name: 'Invitations' },
  { id: 'org_invite_consents', name: 'OrgInviteConsents' },
  { id: 'reports',            name: 'Reports' },
];

async function main() {
  console.log('Enabling documentSecurity on all collections...\n');
  for (const col of collections) {
    try {
      const current = await db.getCollection(DB_ID, col.id);
      await db.updateCollection(DB_ID, col.id, col.name, current.$permissions, true);
      console.log(`✓ ${col.id}`);
    } catch (e) {
      if (e.code === 404) {
        console.log(`~ ${col.id}: not found, skipping`);
      } else {
        console.error(`✗ ${col.id}: ${e.message}`);
      }
    }
  }
  console.log('\nDone. All existing documents without explicit permissions are now inaccessible');
  console.log('to clients (Cloud Functions with API key are unaffected).');
}

main().catch(console.error);
