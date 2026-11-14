// Mock-Test der Rechte-Logik von conversation-action, self-service, sync-*, admin-member-action.
// node-appwrite wird durch eine In-Memory-Fake-DB ersetzt — nichts geht an den Server.
// Nutzung (aus appwrite/): node test-functions-mock.cjs
const Module = require('module');
const path = require('path');
const assert = require('assert');
const FN = process.argv[2] ?? path.join(__dirname, 'functions');

const store = {}; // col -> id -> doc
const teamsStore = {};
const col = (c) => (store[c] ??= {});
let idc = 0;
const match = (doc, q) => {
  if (q.t === 'equal') { const v = doc[q.a]; return q.v.some((x) => (Array.isArray(v) ? v.includes(x) : v === x)); }
  if (q.t === 'contains') return (doc[q.a] ?? []).some((x) => q.v.includes(x));
  if (q.t === 'notEqual') return doc[q.a] !== q.v[0];
  return true;
};
class Databases {
  async getDocument(_d, c, id) { const d = col(c)[id]; if (!d) { const e = new Error('nf'); e.code = 404; throw e; } return JSON.parse(JSON.stringify(d)); }
  async listDocuments(_d, c, qs = []) { const f = qs.filter((q) => ['equal', 'contains', 'notEqual'].includes(q.t)); const docs = Object.values(col(c)).filter((d) => f.every((q) => match(d, q))); return { total: docs.length, documents: JSON.parse(JSON.stringify(docs)) }; }
  async createDocument(_d, c, id, data, perms = []) { if (col(c)[id]) { const e = new Error('dup'); e.code = 409; throw e; } col(c)[id] = { $id: id, ...data, $permissions: perms }; return { ...col(c)[id] }; }
  async updateDocument(_d, c, id, data, perms) { const d = col(c)[id]; if (!d) { const e = new Error('nf'); e.code = 404; throw e; } Object.assign(d, data); if (perms) d.$permissions = perms; return { ...d }; }
  async deleteDocument(_d, c, id) { delete col(c)[id]; }
}
class Teams {
  async get(id) { if (!teamsStore[id]) { const e = new Error('nf'); e.code = 404; throw e; } return {}; }
  async create(id) { teamsStore[id] = new Set(); }
  async delete(id) { delete teamsStore[id]; }
  async listMemberships(id) { return { memberships: [...(teamsStore[id] ?? [])].map((u) => ({ userId: u, $id: `${id}:${u}` })) }; }
  async createMembership(id, _r, _e, uid) { teamsStore[id].add(uid); }
  async deleteMembership(id, mid) { teamsStore[id].delete(mid.split(':')[1]); }
}
class Users { async get(id) { return { email: `${id}@X.de`, name: `Name ${id}` }; } }
class Client { setEndpoint() { return this; } setProject() { return this; } setKey() { return this; } }
const Query = { equal: (a, v) => ({ t: 'equal', a, v: [].concat(v) }), contains: (a, v) => ({ t: 'contains', a, v: [].concat(v) }), notEqual: (a, v) => ({ t: 'notEqual', a, v: [].concat(v) }), limit: () => ({ t: 'limit' }), cursorAfter: () => ({ t: 'c' }) };
const Role = { user: (u) => `user:${u}`, team: (t) => `team:${t}`, users: () => 'users' };
const Permission = { read: (r) => `read("${r}")`, update: (r) => `update("${r}")`, delete: (r) => `delete("${r}")` };
const ID = { unique: () => `id${++idc}` };
class Storage {}
const fake = { Storage, Client, Databases, Teams, Users, Query, Role, Permission, ID };
const origLoad = Module._load;
Module._load = function (req, ...rest) { if (req === 'node-appwrite') return fake; if (req === './fcm') return { sendToUsers: async () => {} }; return origLoad.call(this, req, ...rest); };

const load = (n) => require(path.join(FN, n, 'src', 'main.js'));
const call = async (fn, caller, body, event) => {
  let out;
  const res = { json: (b, s = 200) => (out = { s, b }), empty: () => (out = { s: 204 }) };
  await fn({ req: { headers: { 'x-appwrite-user-id': caller, 'x-appwrite-event': event }, body }, res, log: () => {}, error: () => {} });
  return out;
};

(async () => {
  // Org: A admin, M mod, P parent(member), C child (guardian P), F member
  store.organizations = { o1: { $id: 'o1', adminUid: 'A', memberUids: ['A', 'M', 'P', 'F'] } };
  const mem = (uid, role, extra = {}) => ({ $id: `o1_${uid}`, orgId: 'o1', uid, role, status: 'active', guardianUids: [], ...extra });
  store.members = { o1_A: mem('A', 'admin'), o1_M: mem('M', 'moderator'), o1_P: mem('P', 'member'), o1_C: mem('C', 'child', { guardianUids: ['P'] }), o1_F: mem('F', 'member') };
  store.users = { C: { $id: 'C', isChild: true, displayName: 'C' }, F: { $id: 'F', displayName: 'F' } };
  const ca = load('conversation-action');

  // Kind fragt F an → pending, guardianUids server-berechnet
  let r = await call(ca, 'C', { action: 'request', orgId: 'o1', targetUid: 'F' });
  assert.equal(r.s, 200, JSON.stringify(r)); const conv = r.b.conversation;
  assert.equal(conv.status, 'pending'); assert.deepEqual(conv.guardianUids, ['P']);
  assert.deepEqual(conv.$permissions, ['read("team:' + conv.$id + '")', 'read("user:C")']);
  // Kind darf nicht selbst genehmigen
  r = await call(ca, 'C', { action: 'approve', convId: conv.$id }); assert.equal(r.s, 403);
  // F (Teilnehmer, kein Guardian) auch nicht
  r = await call(ca, 'F', { action: 'approve', convId: conv.$id }); assert.equal(r.s, 403);
  // Guardian P darf
  r = await call(ca, 'P', { action: 'approve', convId: conv.$id }); assert.equal(r.s, 200);
  assert.equal(store.conversations[conv.$id].status, 'approved');
  // Kind darf nicht archivieren/Mitglieder ändern/Direkt anlegen/Gruppe
  assert.equal((await call(ca, 'C', { action: 'archive', convId: conv.$id })).s, 403);
  assert.equal((await call(ca, 'C', { action: 'createDirect', orgId: 'o1', targetUid: 'F' })).s, 403);
  assert.equal((await call(ca, 'F', { action: 'createGroup', orgId: 'o1', name: 'g', memberUids: ['F', 'C'] })).s, 403);
  // Guardian startet Direktchat mit eigenem Kind → approved
  r = await call(ca, 'P', { action: 'createDirect', orgId: 'o1', targetUid: 'C' }); assert.equal(r.b.conversation.status, 'approved');
  // Mod: Gruppe, Mitglied hinzufügen, entfernen, pin
  r = await call(ca, 'M', { action: 'createGroup', orgId: 'o1', name: ' G ', memberUids: ['M', 'F'] });
  const g = r.b.conversation; assert.equal(g.name, 'G'); assert.deepEqual(g.guardianUids, []);
  r = await call(ca, 'M', { action: 'addMembers', convId: g.$id, uids: ['C', 'nobody'] }); assert.equal(r.s, 400);
  r = await call(ca, 'M', { action: 'addMembers', convId: g.$id, uids: ['C'] }); assert.equal(r.s, 200);
  assert.deepEqual(store.conversations[g.$id].guardianUids, ['P']);
  r = await call(ca, 'M', { action: 'removeMember', convId: g.$id, uid: 'C' });
  assert.deepEqual(store.conversations[g.$id].guardianUids, []);
  store.chat_messages = { m1: { $id: 'm1', convId: g.$id, text: 'x'.repeat(200) } };
  r = await call(ca, 'M', { action: 'pin', convId: g.$id, msgId: 'm1' }); assert.equal(r.s, 200);
  assert.equal(store.conversations[g.$id].pinnedMessageText.length, 121);
  r = await call(ca, 'F', { action: 'pin', convId: g.$id, msgId: 'm1' }); assert.equal(r.s, 403);
  // personalName nur Direktchat-Teilnehmer
  assert.equal((await call(ca, 'M', { action: 'setPersonalName', convId: conv.$id, name: 'x' })).s, 403);
  assert.equal((await call(ca, 'F', { action: 'setPersonalName', convId: conv.$id, name: 'Kumpel' })).s, 200);
  assert.equal(store.conversations[conv.$id].personalNamesJson, '{"F":"Kumpel"}');
  // Duplikat-Anfrage
  assert.equal((await call(ca, 'F', { action: 'request', orgId: 'o1', targetUid: 'C' })).b.error, 'conversation_exists');
  // Fremder (kein Member) nichts
  assert.equal((await call(ca, 'X', { action: 'request', orgId: 'o1', targetUid: 'F' })).s, 403);
  console.log('conversation-action OK');

  // self-service
  const ss = load('self-service');
  r = await call(ss, 'N', { action: 'ensureUserDoc' }); assert.equal(r.b.user.email, 'n@x.de'); assert.deepEqual(r.b.user.$permissions, ['read("user:N")']);
  r = await call(ss, 'F', { action: 'updateProfile', displayName: ' Fritz ', role: 'admin', isChild: false });
  assert.equal(store.users.F.displayName, 'Fritz'); assert.equal(store.members.o1_F.displayName, 'Fritz'); assert.equal(store.members.o1_F.role, 'member');
  assert.equal((await call(ss, 'F', { action: 'updateProfile', displayName: 'a', photoUrl: 'http://evil/x.png' })).s, 400);
  assert.equal((await call(ss, 'F', { action: 'setMessageInterval', orgId: 'o1', interval: 'never' })).s, 200);
  assert.equal(store.members.o1_F.notificationsEnabled, false);
  assert.equal((await call(ss, 'F', { action: 'setChildAlertInterval', orgId: 'o2', interval: 'daily' })).s, 404);
  assert.equal((await call(ss, 'C', { action: 'createOrganization', name: 'x', tag: 'familie' })).s, 403);
  r = await call(ss, 'F', { action: 'createOrganization', name: 'Neu', tag: 'freunde' }); assert.equal(r.s, 200);
  const no = r.b.organization.$id; assert.equal(store.members[`${no}_F`].role, 'admin'); assert.deepEqual(store.members[`${no}_F`].$permissions, ['read("users")']);
  // Claims: Parent kann nicht selbst bestätigen
  store.claim_requests = { k1: { $id: 'k1', fromUid: 'P', toUid: 'F', status: 'pending' } };
  assert.equal((await call(ss, 'P', { action: 'respondClaim', requestId: 'k1', response: 'confirmed' })).s, 403);
  assert.equal((await call(ss, 'F', { action: 'respondClaim', requestId: 'k1', response: 'confirmed' })).s, 200);
  assert.equal((await call(ss, 'F', { action: 'respondClaim', requestId: 'k1', response: 'rejected' })).s, 409);
  console.log('self-service OK');

  // sync-conversation-permissions: Alt-App legt selbstgenehmigten Chat an
  const scp = load('sync-conversation-permissions');
  store.conversations.legacy = { $id: 'legacy', orgId: 'o1', participantUids: ['C', 'F'], status: 'approved', guardianUids: [], requestedBy: 'F', $permissions: ['read("user:C")', 'update("user:C")'] };
  await call(scp, 'C', { ...store.conversations.legacy }, 'databases.guardian.collections.conversations.documents.legacy.create');
  const L = store.conversations.legacy;
  assert.equal(L.status, 'pending'); assert.deepEqual(L.guardianUids, ['P']); assert.equal(L.requestedBy, 'C');
  assert.deepEqual(L.$permissions, ['read("team:legacy")']);
  assert.ok(teamsStore.legacy.has('P') && teamsStore.legacy.has('A') && teamsStore.legacy.has('M'));
  // Alt-ACL-Update entfernt Guardian → wird zurückgesetzt
  L.guardianUids = []; await call(scp, 'C', { ...L }, 'x.update'); assert.deepEqual(store.conversations.legacy.guardianUids, ['P']);
  // Kind legt Gruppe an → gelöscht
  store.conversations.lg = { $id: 'lg', orgId: 'o1', isGroup: true, participantUids: ['C', 'F'], status: 'approved', $permissions: ['update("user:C")'] };
  await call(scp, 'C', { ...store.conversations.lg }, 'x.create'); assert.equal(store.conversations.lg, undefined);
  console.log('sync-conversation-permissions OK');

  // sync-supervisor-team Guard
  const sst = load('sync-supervisor-team');
  store.members.o1_X = { $id: 'o1_X', orgId: 'o1', uid: 'X', role: 'admin', $permissions: ['read("users")', 'update("user:X")', 'delete("user:X")'] };
  await call(sst, 'X', { ...store.members.o1_X }, 'x.create'); assert.equal(store.members.o1_X, undefined);
  store.organizations.o9 = { $id: 'o9', adminUid: 'Z' };
  store.members.o9_Z = { $id: 'o9_Z', orgId: 'o9', uid: 'Z', role: 'admin', $permissions: ['read("users")', 'update("user:Z")', 'delete("user:Z")'] };
  await call(sst, 'Z', { ...store.members.o9_Z }, 'x.create'); assert.deepEqual(store.members.o9_Z.$permissions, ['read("users")']);
  console.log('sync-supervisor-team guard OK');

  // admin-member-action addMember: Mod kann keinen Mod/Admin anlegen, Client-memberData ignoriert
  const ama = load('admin-member-action');
  store.users.Q = { $id: 'Q', displayName: 'Q', email: 'q@x' };
  assert.equal((await call(ama, 'M', { action: 'addMember', orgId: 'o1', targetUid: 'Q', payload: { memberData: { role: 'moderator' } } })).s, 403);
  r = await call(ama, 'M', { action: 'addMember', orgId: 'o1', targetUid: 'Q', payload: { memberData: { role: 'member', status: 'active', guardianUids: ['X'], uid: 'evil' } } });
  assert.equal(r.s, 200); assert.equal(store.members.o1_Q.uid, 'Q'); assert.deepEqual(store.members.o1_Q.$permissions, ['read("users")']);
  assert.equal((await call(ama, 'M', { action: 'updateRole', orgId: 'o1', targetUid: 'A', payload: { newRole: 'member' } })).s, 403);
  assert.equal((await call(ama, 'M', { action: 'updateGuardians', orgId: 'o1', targetUid: 'C', payload: { guardianUids: ['stranger'] } })).s, 400);
  console.log('admin-member-action OK');
})().catch((e) => { console.error('FAIL', e); process.exit(1); });
