/**
 * Setzt die korrekten Berechtigungen für ein users-Dokument.
 * Wird benötigt wenn merge-oauth-account das Dokument ohne User-Permissions erstellt hat.
 *
 * Usage:
 *   node fix-user-permissions.js <UID>
 *
 * Beispiel:
 *   node fix-user-permissions.js 6a0a260ef1ad6e578bf7
 */

import { config } from 'dotenv';
import { Client, Databases, Permission, Role } from 'node-appwrite';

config();

const uid = process.argv[2];
if (!uid) {
  console.error('Usage: node fix-user-permissions.js <UID>');
  process.exit(1);
}

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const db = new Databases(client);

const perms = [
  Permission.read(Role.user(uid)),
  Permission.update(Role.user(uid)),
  Permission.delete(Role.user(uid)),
];

try {
  await db.updateDocument('guardian', 'users', uid, {}, perms);
  console.log(`✅ Permissions für users/${uid} gesetzt.`);
} catch (e) {
  console.error(`✗ Fehler: ${e.message}`);
  process.exit(1);
}
