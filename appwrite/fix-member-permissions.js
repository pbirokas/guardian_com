/**
 * One-time migration: update permissions on all existing member documents.
 *
 * Before this fix, member docs were created with Permission.read(Role.user(uid))
 * only, which prevented admins from reading them (401) and members from deleting
 * them (no delete permission → leaveOrganization fails).
 *
 * After this script every member doc has:
 *   - read:   Role.users()       → any logged-in user can see member info
 *   - update: Role.user(uid)     → only the member can update their own data
 *   - delete: Role.user(uid)     → member can leave (deleteDocument in leaveOrg)
 *
 * Usage:
 *   node fix-member-permissions.js
 *
 * Required env vars (same as setup.js):
 *   APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY
 */

import { config } from 'dotenv';
import { Client, Databases, Query, Permission, Role } from 'node-appwrite';

config();

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const db = new Databases(client);
const DB_ID = 'guardian';
const COL_MEMBERS = 'members';
const PAGE_SIZE = 100;

async function fixMemberPermissions() {
  console.log('Fixing member document permissions...\n');

  let cursor = null;
  let total = 0;
  let fixed = 0;
  let skipped = 0;
  let errors = 0;

  while (true) {
    const queries = [Query.limit(PAGE_SIZE)];
    if (cursor) queries.push(Query.cursorAfter(cursor));

    const result = await db.listDocuments(DB_ID, COL_MEMBERS, queries);
    const docs = result.documents;
    if (docs.length === 0) break;

    for (const doc of docs) {
      total++;
      const uid = doc.uid ?? doc.data?.uid;
      if (!uid) {
        console.warn(`  ~ ${doc.$id}: no uid field, skipping`);
        skipped++;
        continue;
      }

      const correctPerms = [
        Permission.read(Role.users()),
        Permission.update(Role.user(uid)),
        Permission.delete(Role.user(uid)),
      ];

      // Check if permissions are already correct
      const current = doc.$permissions ?? [];
      const hasReadUsers = current.includes(`read("users")`);
      const hasUpdateUser = current.includes(`update("user:${uid}")`);
      const hasDeleteUser = current.includes(`delete("user:${uid}")`);

      if (hasReadUsers && hasUpdateUser && hasDeleteUser) {
        skipped++;
        continue;
      }

      try {
        await db.updateDocument(DB_ID, COL_MEMBERS, doc.$id, {}, correctPerms);
        fixed++;
        console.log(`  ✓ ${doc.$id} (uid=${uid})`);
      } catch (e) {
        errors++;
        console.error(`  ✗ ${doc.$id}: ${e.message}`);
      }
    }

    if (docs.length < PAGE_SIZE) break;
    cursor = docs[docs.length - 1].$id;
  }

  console.log(`\nDone: ${total} total, ${fixed} fixed, ${skipped} already correct, ${errors} errors`);
}

fixMemberPermissions().catch(console.error);
