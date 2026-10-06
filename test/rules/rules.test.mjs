import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, addDoc, collection,
  increment, writeBatch, serverTimestamp, collectionGroup, query, where, getDocs,
} from 'firebase/firestore';
import { ref, uploadBytes, deleteObject, getBytes } from 'firebase/storage';

// Security rules tests for firestore.rules and storage.rules.
//
// Runs against the local Firebase emulators, never a real project:
//   cd test/rules && npm install && npm test
// `npm test` starts the emulators from the repo's firebase.json and runs this
// file; the emulator hosts come from the environment that sets up.
//
// The moderator account here must match the admin list in both rules files
// and lib/core/utils/permissions.dart.
const root = new URL('../../', import.meta.url);
const env = await initializeTestEnvironment({
  projectId: 'demo-rules',
  firestore: { rules: readFileSync(new URL('firestore.rules', root), 'utf8') },
  storage: { rules: readFileSync(new URL('storage.rules', root), 'utf8') },
});

const ADMIN = { email: 'bkapsalis@gmail.com', email_verified: true };
const alice = () => env.authenticatedContext('alice');
const bob = () => env.authenticatedContext('bob');
const guest = () => env.authenticatedContext('guest', { firebase: { sign_in_provider: 'anonymous' } });
const admin = () => env.authenticatedContext('bill', ADMIN);
const fakeAdmin = () => env.authenticatedContext('mallory', { email: 'bkapsalis@gmail.com', email_verified: false });
const anon = () => env.unauthenticatedContext();

const photo = (owner, extra = {}) => ({
  imageUrl: 'x', userId: owner, userName: owner, category: 'Museums - Historic Sites',
  locationName: 'Forbes Mill Museum', heartCount: 0, commentCount: 0, ...extra,
});

let pass = 0, fail = 0;
async function check(name, fn) {
  try { await fn(); pass++; console.log('  ok   ', name); }
  catch (e) { fail++; console.log('  FAIL ', name, '\n        ', e.message.split('\n')[0]); }
}
async function seed(fn) {
  await env.withSecurityRulesDisabled(async (c) => fn(c.firestore(), c.storage()));
}
async function reset() {
  await env.clearFirestore();
  await seed(async (db) => {
    await setDoc(doc(db, 'photos/p1'), photo('alice'));
    await setDoc(doc(db, 'photos/p2'), photo('bob'));
    await setDoc(doc(db, 'comments/p1/messages/c-bob'), { userId: 'bob', text: 'hi' });
    await setDoc(doc(db, 'comments/p1/messages/c-alice'), { userId: 'alice', text: 'yo' });
    await setDoc(doc(db, 'chats/loc1/messages/m-bob'), { userId: 'bob', text: 'hey' });
    await setDoc(doc(db, 'locations/loc1'), { name: 'Forbes Mill' });
  });
}

console.log('Firestore — reads');
await reset();
await check('anyone (signed out) can read photos', () => assertSucceeds(getDoc(doc(anon().firestore(), 'photos/p1'))));
await check('anyone can read comments', () => assertSucceeds(getDoc(doc(anon().firestore(), 'comments/p1/messages/c-bob'))));
await check('anyone can read location chat', () => assertSucceeds(getDoc(doc(anon().firestore(), 'chats/loc1/messages/m-bob'))));
await check('own-messages collection group query works', () =>
  assertSucceeds(getDocs(query(collectionGroup(bob().firestore(), 'messages'), where('userId', '==', 'bob')))));

console.log('Firestore — photos');
await check('signed-out user cannot create a photo', () => assertFails(addDoc(collection(anon().firestore(), 'photos'), photo('x'))));
await check('user can create a photo as themselves', () => assertSucceeds(addDoc(collection(alice().firestore(), 'photos'), photo('alice'))));
await check('guest can create a photo as themselves', () => assertSucceeds(addDoc(collection(guest().firestore(), 'photos'), photo('guest'))));
await check('cannot create a photo in someone else\'s name', () => assertFails(addDoc(collection(alice().firestore(), 'photos'), photo('bob'))));
await check('owner can edit details', () => assertSucceeds(updateDoc(doc(alice().firestore(), 'photos/p1'), { locationName: 'New', category: 'Hiking Areas', locationRegion: 'X' })));
await check('owner cannot give the photo away', () => assertFails(updateDoc(doc(alice().firestore(), 'photos/p1'), { userId: 'bob' })));
await check('non-owner cannot edit details', () => assertFails(updateDoc(doc(bob().firestore(), 'photos/p1'), { locationName: 'Hacked' })));
await check('non-owner can like (+1)', () => assertSucceeds(updateDoc(doc(bob().firestore(), 'photos/p1'), { heartCount: increment(1) })));
await check('non-owner cannot like by +5', () => assertFails(updateDoc(doc(bob().firestore(), 'photos/p1'), { heartCount: increment(5) })));
await check('non-owner cannot reset likes', () => assertFails(updateDoc(doc(bob().firestore(), 'photos/p1'), { heartCount: 0 })));
await check('non-owner cannot sneak an edit in with a like', () => assertFails(updateDoc(doc(bob().firestore(), 'photos/p1'), { heartCount: increment(1), locationName: 'Hacked' })));
await check('signed-out user cannot like', () => assertFails(updateDoc(doc(anon().firestore(), 'photos/p1'), { heartCount: increment(1) })));
await check('commentCount can move +1', () => assertSucceeds(updateDoc(doc(bob().firestore(), 'photos/p1'), { commentCount: increment(1) })));
await check('commentCount can move -1', () => assertSucceeds(updateDoc(doc(bob().firestore(), 'photos/p1'), { commentCount: increment(-1) })));
await check('commentCount cannot jump', () => assertFails(updateDoc(doc(bob().firestore(), 'photos/p1'), { commentCount: 99 })));
await check('like works on a photo with no heartCount field', async () => {
  await seed((db) => setDoc(doc(db, 'photos/old'), { userId: 'alice', imageUrl: 'x' }));
  await assertSucceeds(updateDoc(doc(bob().firestore(), 'photos/old'), { heartCount: increment(1) }));
});
await check('non-owner cannot delete', () => assertFails(deleteDoc(doc(bob().firestore(), 'photos/p1'))));
await check('owner can delete', () => assertSucceeds(deleteDoc(doc(alice().firestore(), 'photos/p1'))));

console.log('Firestore — admin');
await reset();
await check('admin can edit anyone\'s photo', () => assertSucceeds(updateDoc(doc(admin().firestore(), 'photos/p2'), { locationName: 'Fixed' })));
await check('unverified email is NOT admin', () => assertFails(updateDoc(doc(fakeAdmin().firestore(), 'photos/p2'), { locationName: 'Hacked' })));
await check('admin bulk delete of mixed owners in one batch', async () => {
  const db = admin().firestore();
  const b = writeBatch(db);
  b.delete(doc(db, 'photos/p1'));
  b.delete(doc(db, 'photos/p2'));
  await assertSucceeds(b.commit());
});
await reset();
await check('non-admin bulk delete with someone else\'s photo fails', async () => {
  const db = alice().firestore();
  const b = writeBatch(db); b.delete(doc(db, 'photos/p1')); b.delete(doc(db, 'photos/p2'));
  await assertFails(b.commit());
});
await check('only admin can write locations', async () => {
  await assertFails(setDoc(doc(alice().firestore(), 'locations/x'), { name: 'x' }));
  await assertSucceeds(setDoc(doc(admin().firestore(), 'locations/x'), { name: 'x' }));
});

console.log('Firestore — comments & chat');
await reset();
await check('user can comment as themselves', () => assertSucceeds(addDoc(collection(bob().firestore(), 'comments/p1/messages'), { userId: 'bob', text: 'x', timestamp: serverTimestamp() })));
await check('cannot comment as someone else', () => assertFails(addDoc(collection(bob().firestore(), 'comments/p1/messages'), { userId: 'alice', text: 'x' })));
await check('signed-out user cannot comment', () => assertFails(addDoc(collection(anon().firestore(), 'comments/p1/messages'), { userId: 'x', text: 'x' })));
await check('author can edit their comment', () => assertSucceeds(updateDoc(doc(bob().firestore(), 'comments/p1/messages/c-bob'), { text: 'edited' })));
await check('others cannot edit a comment', () => assertFails(updateDoc(doc(alice().firestore(), 'comments/p2/messages/c-bob'), { text: 'x' })));
await check('photo owner can delete others\' comments on their photo', () => assertSucceeds(deleteDoc(doc(alice().firestore(), 'comments/p1/messages/c-bob'))));
await reset();
await check('third party cannot delete a comment', async () => {
  await seed((db) => setDoc(doc(db, 'comments/p2/messages/c-alice'), { userId: 'alice', text: 'x' }));
  await assertFails(deleteDoc(doc(env.authenticatedContext('carol').firestore(), 'comments/p2/messages/c-alice')));
});
await check('author can delete own comment', () => assertSucceeds(deleteDoc(doc(bob().firestore(), 'comments/p1/messages/c-bob'))));
await check('author can rename themselves on their messages (guest upgrade)', () =>
  assertSucceeds(updateDoc(doc(bob().firestore(), 'chats/loc1/messages/m-bob'), { userName: 'Bob', userInitials: 'B', userAvatarColor: 1 })));
await check('cannot rename someone else\'s chat message', () =>
  assertFails(updateDoc(doc(alice().firestore(), 'chats/loc1/messages/m-bob'), { userName: 'x' })));
await check('chat message must be sent as self', () => assertFails(addDoc(collection(alice().firestore(), 'chats/loc1/messages'), { userId: 'bob', text: 'x' })));

console.log('Storage');
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
const meta = (uid) => ({ contentType: 'image/jpeg', customMetadata: uid ? { ownerUid: uid } : {} });
await env.clearStorage();
await check('signed-out user cannot upload', () => assertFails(uploadBytes(ref(anon().storage(), 'photos/museums/a.jpg'), jpeg, meta('x'))));
await check('upload tagged as self succeeds', () => assertSucceeds(uploadBytes(ref(alice().storage(), 'photos/museums/a.jpg'), jpeg, meta('alice'))));
await check('upload without owner tag fails', () => assertFails(uploadBytes(ref(alice().storage(), 'photos/museums/b.jpg'), jpeg, meta(null))));
await check('upload tagged as someone else fails', () => assertFails(uploadBytes(ref(alice().storage(), 'photos/museums/c.jpg'), jpeg, meta('bob'))));
await check('non-image upload fails', () => assertFails(uploadBytes(ref(alice().storage(), 'photos/museums/d.jpg'), jpeg, { contentType: 'text/html', customMetadata: { ownerUid: 'alice' } })));
await check('anyone can read a photo file', () => assertSucceeds(getBytes(ref(anon().storage(), 'photos/museums/a.jpg'))));
await check('others cannot delete the file', () => assertFails(deleteObject(ref(bob().storage(), 'photos/museums/a.jpg'))));
await check('owner can delete their file', () => assertSucceeds(deleteObject(ref(alice().storage(), 'photos/museums/a.jpg'))));
await check('untagged legacy file: owner cannot, admin can delete', async () => {
  await env.withSecurityRulesDisabled((c) => uploadBytes(ref(c.storage(), 'photos/museums/legacy.jpg'), jpeg, { contentType: 'image/jpeg' }));
  await assertFails(deleteObject(ref(alice().storage(), 'photos/museums/legacy.jpg')));
  await assertSucceeds(deleteObject(ref(admin().storage(), 'photos/museums/legacy.jpg')));
});
await check('outside photos/ is closed', () => assertFails(uploadBytes(ref(alice().storage(), 'other/x.jpg'), jpeg, meta('alice'))));

await env.cleanup();
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
