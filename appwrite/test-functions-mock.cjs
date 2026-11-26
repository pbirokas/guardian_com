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
const deletedAuth = [];
class Users { async get(id) { return { email: `${id}@X.de`, name: `Name ${id}` }; } async delete(id) { deletedAuth.push(id); } }
class Client { setEndpoint() { return this; } setProject() { return this; } setKey() { return this; } }
const Query = { equal: (a, v) => ({ t: 'equal', a, v: [].concat(v) }), contains: (a, v) => ({ t: 'contains', a, v: [].concat(v) }), notEqual: (a, v) => ({ t: 'notEqual', a, v: [].concat(v) }), limit: () => ({ t: 'limit' }), cursorAfter: () => ({ t: 'c' }) };
const Role = { user: (u) => `user:${u}`, team: (t) => `team:${t}`, users: () => 'users' };
const Permission = { read: (r) => `read("${r}")`, update: (r) => `update("${r}")`, delete: (r) => `delete("${r}")` };
const ID = { unique: () => `id${++idc}` };
const files = {}; // fileId -> { $permissions }
class Storage { async getFile(_b, id) { if (!files[id]) { const e = new Error('nf'); e.code = 404; throw e; } return { $id: id, ...files[id] }; } async deleteFile(_b, id) { delete files[id]; } }
const executions = [];
class Functions { async createExecution(id, body, async) { executions.push({ id, body: JSON.parse(body), async }); return {}; } }
const fake = { Functions, Storage, Client, Databases, Teams, Users, Query, Role, Permission, ID };
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
  // inviteByEmail (Phase 3): Lookup serverseitig
  store.users.R = { $id: 'R', displayName: 'Rita', email: 'r@x.de' };
  store.users.K = { $id: 'K', displayName: 'Kim', email: 'k@x.de', isChild: true, verifiedParentUids: ['P'] };
  assert.equal((await call(ama, 'F', { action: 'inviteByEmail', orgId: 'o1', payload: { email: 'r@x.de' } })).s, 403);
  assert.equal((await call(ama, 'M', { action: 'inviteByEmail', orgId: 'o1', payload: { email: 'r@x.de', role: 'moderator' } })).s, 403);
  assert.equal((await call(ama, 'M', { action: 'inviteByEmail', orgId: 'o1', payload: { email: 'kein-mail' } })).s, 400);
  r = await call(ama, 'M', { action: 'inviteByEmail', orgId: 'o1', payload: { email: ' R@X.de ', role: 'member' } });
  assert.equal(r.s, 200); assert.equal(r.b.result, 'added'); assert.equal(r.b.targetName, 'Rita');
  assert.equal(r.b.email, undefined); assert.equal(store.members.o1_R.role, 'member');
  assert.equal((await call(ama, 'M', { action: 'inviteByEmail', orgId: 'o1', payload: { email: 'r@x.de' } })).s, 409);
  r = await call(ama, 'M', { action: 'inviteByEmail', orgId: 'o1', payload: { email: 'neu@x.de' } });
  assert.equal(r.b.result, 'invited'); const inv = Object.values(store.invitations)[0];
  assert.equal(inv.email, 'neu@x.de'); assert.equal(inv.invitedByUid, 'M'); assert.ok(inv.$permissions.includes('update("user:M")'));
  assert.equal((await call(ama, 'M', { action: 'inviteByEmail', orgId: 'o1', payload: { email: 'neu@x.de' } })).s, 409);
  assert.equal((await call(ama, 'M', { action: 'inviteByEmail', orgId: 'o1', payload: { email: 'k@x.de', role: 'member' } })).b.error, 'child_account_role_locked');
  assert.equal((await call(ama, 'M', { action: 'inviteByEmail', orgId: 'o1', payload: { email: 'k@x.de', role: 'child', guardianUids: ['stranger'] } })).s, 400);
  r = await call(ama, 'M', { action: 'inviteByEmail', orgId: 'o1', payload: { email: 'k@x.de', role: 'child', guardianUids: ['P'] } });
  assert.equal(r.b.result, 'consentRequested'); const cons = Object.values(store.org_invite_consents)[0];
  assert.deepEqual(cons.parentUids, ['P']); assert.ok(cons.$permissions.includes('update("user:P")'));
  assert.equal(store.members.o1_K, undefined);
  console.log('admin-member-action OK');

  // self-service sendClaim / listRelatives (Phase 3)
  store.users.P = { $id: 'P', displayName: 'Paula', email: 'p@x.de', verifiedChildUids: ['C', 'S'], fcmToken: 'tok' };
  store.users.C = { $id: 'C', isChild: true, displayName: 'C', email: 'c@x.de', verifiedParentUids: ['P', 'P2'], fcmToken: 'secret', membershipsJson: '[]' };
  store.users.P2 = { $id: 'P2', displayName: 'Pit', email: 'p2@x.de', verifiedChildUids: ['C'] };
  store.users.S = { $id: 'S', displayName: 'Spoof', email: 's@x.de', verifiedParentUids: [] }; // einseitig → unsichtbar
  r = await call(ss, 'P', { action: 'listRelatives' });
  assert.equal(r.s, 200); assert.deepEqual(r.b.children.map((c) => c.uid), ['C']);
  assert.equal(r.b.children[0].fcmToken, undefined); assert.equal(r.b.children[0].membershipsJson, undefined);
  assert.deepEqual(r.b.children[0].coParents, [{ uid: 'P2', displayName: 'Pit' }]);
  r = await call(ss, 'C', { action: 'listRelatives' }); assert.deepEqual(r.b.parents.map((p) => p.uid).sort(), ['P', 'P2']);
  store.claim_requests = {};
  assert.equal((await call(ss, 'P', { action: 'sendClaim', email: 'nobody@x.de' })).b.error, 'user_not_found');
  assert.equal((await call(ss, 'P', { action: 'sendClaim', email: 'P@x.de' })).b.error, 'cannot_claim_self');
  r = await call(ss, 'P', { action: 'sendClaim', email: 'R@x.de ' }); assert.equal(r.s, 200);
  const cl = store.claim_requests[r.b.requestId];
  assert.equal(cl.toUid, 'R'); assert.equal(cl.fromName, 'Paula'); assert.equal(cl.status, 'pending');
  assert.ok(!cl.$permissions.includes('update("user:P")') && cl.$permissions.includes('update("user:R")'));
  assert.equal(Object.keys(r.b).includes('toUid'), false);
  assert.equal((await call(ss, 'P', { action: 'sendClaim', email: 'r@x.de' })).b.error, 'already_exists');
  console.log('self-service Phase 3 OK');

  // ── delete-account ──────────────────────────────────────────────────────
  for (const k of Object.keys(store)) delete store[k];
  for (const k of Object.keys(teamsStore)) delete teamsStore[k];
  const da = load('delete-account');
  const DEL = 'Gelöschter Nutzer';
  const own = (u) => ['read("team:x")', `read("user:${u}")`, `update("user:${u}")`, `delete("user:${u}")`];
  const fileUrl = (id) => `https://h/v1/storage/buckets/b/files/${id}/view?project=p`;
  const m2 = (org, uid, role, extra = {}) => ({ $id: `${org}_${uid}`, orgId: org, uid, role, status: 'active', guardianUids: [], ...extra });
  store.users = {
    D: { $id: 'D', displayName: 'Dora', email: 'd@x.de', photoUrl: fileUrl('av1'), verifiedChildUids: [], verifiedParentUids: [] },
    C2: { $id: 'C2', isChild: true, verifiedParentUids: ['P'] },
    P: { $id: 'P', verifiedChildUids: ['C2'] },
    F: { $id: 'F', displayName: 'F' },
  };
  store.organizations = {
    o1: { $id: 'o1', name: 'Verein', adminUid: 'A', memberUids: ['A', 'B', 'D'] },
    o2: { $id: 'o2', name: 'Zwei', adminUid: 'D', memberUids: ['D', 'B'] },
    s1: { $id: 's1', name: 'Solo', adminUid: 'D', memberUids: ['D'] },
  };
  store.members = {
    o1_A: m2('o1', 'A', 'admin'), o1_B: m2('o1', 'B', 'member'), o1_D: m2('o1', 'D', 'member'),
    o1_K2: m2('o1', 'K2', 'child', { guardianUids: ['D'] }),
    o2_D: m2('o2', 'D', 'admin'), o2_B: m2('o2', 'B', 'member'),
    s1_D: m2('s1', 'D', 'admin'), s1_Z: m2('s1', 'Z', 'child', { status: 'pending' }),
  };

  // Sperren
  assert.deepEqual((await call(da, 'C2', { action: 'check' })).b.blockers, [{ code: 'childHasParents' }]);
  assert.deepEqual((await call(da, 'P', { action: 'check' })).b.blockers, [{ code: 'parentHasChildren' }]);
  r = await call(da, 'D', { action: 'check' });
  assert.deepEqual(r.b.blockers, [{ code: 'orgAdmin', orgId: 'o2', orgName: 'Zwei' }]); // s1: nur ausstehendes Kind
  r = await call(da, 'D', { action: 'start' }); assert.equal(r.s, 409); assert.equal(r.b.error, 'blocked');
  assert.equal(store.users.D.deletionStatus, undefined); assert.equal(executions.length, 0);
  // Interner Lauf ohne beantragte Löschung tut nichts; mit Nutzer-Header gibt es 'run' nicht
  await call(da, undefined, { action: 'run', uid: 'F' }); assert.ok(store.users.F);
  assert.equal((await call(da, 'F', { action: 'run', uid: 'D' })).s, 400);
  assert.equal((await call(da, undefined, { action: 'check' })).s, 401);
  // Admin übertragen → frei
  Object.assign(store.organizations.o2, { adminUid: 'B' }); store.members.o2_D.role = 'member'; store.members.o2_B.role = 'admin';
  assert.deepEqual((await call(da, 'D', { action: 'check' })).b.blockers, []);

  // Daten
  files.av1 = { $permissions: ['read("any")', 'delete("user:D")'] };
  files.f1 = { $permissions: ['read("any")', 'delete("user:D")'] };
  files.f2 = { $permissions: ['read("any")', 'delete("user:B")'] };
  files.g1img = { $permissions: ['read("any")', 'delete("user:D")'] };
  files.foreign = { $permissions: ['read("any")', 'delete("user:A")'] };
  store.conversations = {
    dm1: { $id: 'dm1', orgId: 'o1', isGroup: false, participantUids: ['D', 'B'] },
    g1: { $id: 'g1', orgId: 'o1', isGroup: true, participantUids: ['A', 'B', 'D', 'K2'], guardianUids: ['D'], pinnedMessageId: 'gD1', pinnedMessageText: 'hallo', lastMessage: 'tschüss' },
    sc1: { $id: 'sc1', orgId: 's1', isGroup: false, participantUids: ['D'] },
  };
  store.chat_messages = {
    mD1: { $id: 'mD1', convId: 'dm1', senderUid: 'D', text: 'geheim', imageUrl: fileUrl('f1'), sentAt: '2026-11-01T10:00:00Z', $permissions: own('D') },
    mB1: { $id: 'mB1', convId: 'dm1', senderUid: 'B', text: 'antwort', fileUrl: fileUrl('f2'), sentAt: '2026-11-01T10:01:00Z', $permissions: own('B') },
    gD1: { $id: 'gD1', convId: 'g1', senderUid: 'D', senderName: 'Dora', text: 'hallo', imageUrl: fileUrl('g1img'), imageUrls: [fileUrl('g1img'), fileUrl('foreign')], reactionsJson: '{"B":"👍"}', sentAt: '2026-11-02T10:00:00Z', $permissions: own('D') },
    gB1: { $id: 'gB1', convId: 'g1', senderUid: 'B', senderName: 'B', text: 'ok', replyToId: 'gD1', replyToText: 'hallo', replyToSenderName: 'Dora', reactionsJson: '{"D":"❤️","A":"👍"}', sentAt: '2026-11-02T10:01:00Z', $permissions: own('B') },
    gD2: { $id: 'gD2', convId: 'g1', senderUid: 'D', senderName: 'Dora', text: 'tschüss', sentAt: '2026-11-02T10:02:00Z', $permissions: own('D') },
    sys: { $id: 'sys', convId: 'g1', senderUid: 'D', senderName: 'Dora', type: 'system', systemActorName: 'Dora', systemTargetName: 'B', sentAt: '2026-11-02T09:00:00Z' },
    old: { $id: 'old', convId: 'gOld', senderUid: 'D', senderName: 'Dora', text: 'früher', sentAt: '2026-01-01T00:00:00Z', $permissions: own('D') },
    sm: { $id: 'sm', convId: 'sc1', senderUid: 'D', text: 'solo', sentAt: '2026-11-03T00:00:00Z' },
  };
  store.polls = {
    pD: { $id: 'pD', convId: 'g1', createdBy: 'D', votesJson: '{}' },
    pB: { $id: 'pB', convId: 'g1', createdBy: 'B', votesJson: '{"x":["D","A"],"y":["B"]}' },
  };
  store.read_receipts = { rr: { $id: 'rr', convId: 'g1', uid: 'D' }, rrB: { $id: 'rrB', convId: 'g1', uid: 'B' } };
  store.scheduled_messages = { s1m: { $id: 's1m', convId: 'g1', senderUid: 'D' }, sB: { $id: 'sB', convId: 'g1', senderUid: 'B' } };
  store.claim_requests = { cl1: { $id: 'cl1', fromUid: 'D', toUid: 'Y' }, cl2: { $id: 'cl2', fromUid: 'Y', toUid: 'D' } };
  store.invitations = {
    inv1: { $id: 'inv1', email: 'd@x.de', orgId: 'o1' },
    inv2: { $id: 'inv2', email: 'n@x.de', orgId: 'o1', invitedByUid: 'D', inviterName: 'Dora' },
  };
  store.org_invite_consents = {
    cs1: { $id: 'cs1', orgId: 'o9', childUid: 'X', parentUids: ['D'], status: 'pending' },
    cs2: { $id: 'cs2', orgId: 'o9', childUid: 'X2', parentUids: ['D', 'Q'], status: 'pending' },
    cs3: { $id: 'cs3', orgId: 'o1', childUid: 'X3', parentUids: ['Q'], invitedByUid: 'D', invitedByName: 'Dora' },
  };
  store.audit_log = { a1: { $id: 'a1', orgId: 'o1', actorUid: 'D', actorName: 'Dora' }, a2: { $id: 'a2', orgId: 'o1', actorUid: 'A', actorName: 'Anna' } };
  store.reports = {
    rp1: { $id: 'rp1', orgId: 'o1', msgId: 'gD1', messageSenderName: 'Dora', messageText: 'hallo' },
    rp2: { $id: 'rp2', orgId: 'o1', msgId: 'mD1', messageSenderName: 'Dora', messageText: 'geheim' },
    rp3: { $id: 'rp3', orgId: 'o1', msgId: 'gB1', messageSenderName: 'B', messageText: 'ok', reportedByUid: 'D' },
    rp4: { $id: 'rp4', orgId: 'o1', msgId: 'expired', messageSenderName: 'Dora', messageText: 'alt' },
    rp5: { $id: 'rp5', orgId: 'o1', msgId: 'expired2', messageSenderName: 'Bert', messageText: 'alt' },
  };
  store.announcements = { an1: { $id: 'an1', orgId: 'o1', authorUid: 'D', authorName: 'Dora', reactionsJson: '{"D":"🎉"}', rsvpJson: '{"D":"yes","A":"no"}' } };

  r = await call(da, 'D', { action: 'start' }); assert.equal(r.s, 200, JSON.stringify(r));
  assert.equal(store.users.D.deletionStatus, 'deleting');
  assert.deepEqual(executions.pop(), { id: 'delete-account', body: { action: 'run', uid: 'D' }, async: true });
  await call(da, undefined, { action: 'run', uid: 'D' });

  assert.deepEqual(deletedAuth, ['D']);
  assert.equal(store.users.D, undefined);
  assert.equal(store.members.o1_D, undefined); assert.equal(store.members.o2_D, undefined);
  assert.deepEqual(store.organizations.o1.memberUids, ['A', 'B']); assert.deepEqual(store.organizations.o2.memberUids, ['B']);
  assert.equal(store.organizations.s1, undefined); assert.equal(store.members.s1_Z, undefined);
  assert.equal(store.conversations.sc1, undefined); assert.equal(store.chat_messages.sm, undefined);
  assert.deepEqual(store.members.o1_K2.guardianUids, []);
  // 1:1-Chat komplett weg, inkl. Medien beider Seiten
  assert.equal(store.conversations.dm1, undefined); assert.equal(store.chat_messages.mD1, undefined); assert.equal(store.chat_messages.mB1, undefined);
  assert.equal(files.f1, undefined); assert.equal(files.f2, undefined);
  // Gruppe: Platzhalter, Zitate/Reaktionen/Stimmen/Pin/Vorschau bereinigt, ausgetreten
  const G = store.conversations.g1;
  assert.deepEqual(G.participantUids, ['A', 'B', 'K2']); assert.deepEqual(G.guardianUids, []);
  assert.equal(G.pinnedMessageId, null); assert.equal(G.lastMessage, '');
  const gD1 = store.chat_messages.gD1;
  assert.equal(gD1.text, ''); assert.equal(gD1.senderName, DEL); assert.equal(gD1.imageUrl, null); assert.deepEqual(gD1.imageUrls, []);
  assert.ok(gD1.deletedAt); assert.equal(gD1.reactionsJson, '{}');
  assert.equal(files.g1img, undefined); assert.ok(files.foreign, 'fremde Datei bleibt');
  assert.equal(store.chat_messages.gB1.replyToText, ''); assert.equal(store.chat_messages.gB1.replyToSenderName, DEL);
  assert.equal(store.chat_messages.gB1.reactionsJson, '{"A":"👍"}'); assert.equal(store.chat_messages.gB1.text, 'ok');
  assert.equal(store.chat_messages.sys.systemActorName, DEL); assert.equal(store.chat_messages.sys.systemTargetName, 'B');
  assert.equal(store.chat_messages.old.text, ''); assert.equal(store.chat_messages.old.senderName, DEL);
  assert.equal(store.polls.pD, undefined); assert.equal(store.polls.pB.votesJson, '{"x":["A"],"y":["B"]}');
  // Rest
  assert.deepEqual(Object.keys(store.read_receipts), ['rrB']); assert.deepEqual(Object.keys(store.scheduled_messages), ['sB']);
  assert.deepEqual(Object.keys(store.claim_requests), []);
  assert.equal(store.invitations.inv1, undefined); assert.equal(store.invitations.inv2.inviterName, DEL);
  assert.equal(store.org_invite_consents.cs1, undefined); assert.deepEqual(store.org_invite_consents.cs2.parentUids, ['Q']);
  assert.equal(store.org_invite_consents.cs3.invitedByName, DEL);
  assert.equal(store.audit_log.a1.actorName, DEL); assert.equal(store.audit_log.a2.actorName, 'Anna');
  assert.deepEqual([store.reports.rp1.messageSenderName, store.reports.rp1.messageText], [DEL, '']);
  assert.deepEqual([store.reports.rp2.messageSenderName, store.reports.rp2.messageText], [DEL, '']);
  assert.equal(store.reports.rp3.messageText, 'ok');
  assert.equal(store.reports.rp4.messageText, ''); assert.equal(store.reports.rp5.messageText, 'alt');
  assert.equal(store.announcements.an1.authorName, DEL); assert.equal(store.announcements.an1.reactionsJson, '{}');
  assert.equal(store.announcements.an1.rsvpJson, '{"A":"no"}');
  assert.equal(files.av1, undefined);
  // Wiederholter Lauf (z. B. Schedule) ist harmlos
  await call(da, undefined, { action: 'run', uid: 'D' }); assert.deepEqual(deletedAuth, ['D']);

  // Sperre greift zwischen start und Lauf → nichts gelöscht, Status 'blocked'
  store.users.E = { $id: 'E', displayName: 'E', email: 'e@x.de' };
  store.organizations.e1 = { $id: 'e1', name: 'E-Org', adminUid: 'E', memberUids: ['E'] };
  store.members.e1_E = m2('e1', 'E', 'admin');
  assert.equal((await call(da, 'E', { action: 'start' })).s, 200);
  store.members.e1_W = m2('e1', 'W', 'member');
  await call(da, undefined, { action: 'run', uid: 'E' });
  assert.equal(store.users.E.deletionStatus, 'blocked'); assert.ok(store.organizations.e1); assert.ok(store.members.e1_E);
  // Schedule setzt nur hängengebliebene Läufe fort
  store.users.H = { $id: 'H', displayName: 'H', deletionStatus: 'deleting', deletionRunAt: new Date().toISOString() };
  store.users.I = { $id: 'I', displayName: 'I', deletionStatus: 'deleting', deletionRunAt: '2026-01-01T00:00:00Z' };
  const sched = async () => { let o; await da({ req: { headers: { 'x-appwrite-trigger': 'schedule' }, body: '' }, res: { json: (b, s = 200) => (o = { s, b }) }, log: () => {}, error: () => {} }); return o; };
  assert.equal((await sched()).s, 200);
  assert.ok(store.users.H); assert.equal(store.users.I, undefined);
  console.log('delete-account OK');
})().catch((e) => { console.error('FAIL', e); process.exit(1); });
