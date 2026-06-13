/**
 * Löscht ein verwaistes Member-Dokument das nach einem fehlgeschlagenen
 * leaveOrganization noch in der DB steht.
 *
 * Usage:
 *   node delete-stale-member.js <orgId> <uid>
 *
 * Beispiel:
 *   node delete-stale-member.js PGXevuLXgDkMGZ12lDOr fFXl5XPL2GMadraFUqZRrUCeX6N2
 */

import { config } from 'dotenv';
import { Client, Databases } from 'node-appwrite';

config();

const [,, orgId, uid] = process.argv;
if (!orgId || !uid) {
  console.error('Usage: node delete-stale-member.js <orgId> <uid>');
  process.exit(1);
}

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const db = new Databases(client);
const memberId = `${orgId}_${uid}`;

console.log(`Deleting member document: ${memberId}`);
try {
  await db.deleteDocument('guardian', 'members', memberId);
  console.log('✓ Deleted successfully');
} catch (e) {
  if (e.code === 404) {
    console.log('~ Document not found (already deleted)');
  } else {
    console.error(`✗ Error: ${e.message}`);
  }
}
