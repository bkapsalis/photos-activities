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

// Tokens carry the claims the app's names come from: `name` for a Google
// account, `email` for one registered with a password, neither for a guest.
const ADMIN = { email: 'bkapsalis@gmail.com', email_verified: true, name: 'Bill Kapsalis' };
const alice = () => env.authenticatedContext('alice', { name: 'Alice Lee' });
const bob = () => env.authenticatedContext('bob', { email: 'bob@example.com' });
const guest = () => env.authenticatedContext('g7xQ2', { firebase: { sign_in_provider: 'anonymous' } });
const admin = () => env.authenticatedContext('bill', ADMIN);
const fakeAdmin = () => env.authenticatedContext('mallory', { email: 'bkapsalis@gmail.com', email_verified: false });

// The names the app would sign each account's posts with.
const NAMES = { alice: 'Alice Lee', bob: 'bob', g7xQ2: 'Guest g7xQ', bill: 'Bill Kapsalis', mallory: 'Mallory' };
const author = (uid, name = NAMES[uid] ?? uid) => ({
  userId: uid, userName: name, userInitials: 'AB', userAvatarColor: 4283215696,
});
const anon = () => env.unauthenticatedContext();

// A photo as PhotoPost.toFirestore writes it.
const photo = (owner, extra = {}) => ({
  imageUrl: 'https://example.com/x.jpg', locationId: 'loc_1', locationName: 'Forbes Mill Museum',
  locationRegion: 'Los Gatos, CA', locationLat: null, locationLng: null,
  category: 'Museums - Historic Sites', ...author(owner), heartCount: 0, commentCount: 0,
  aspectRatio: 1.5, createdAt: serverTimestamp(), metadata: { hasLocation: false }, ...extra,
});

// A comment or chat message as the app writes it.
const post = (uid, extra = {}) => ({ ...author(uid), text: 'Lovely spot', timestamp: serverTimestamp(), ...extra });

// Liking a photo means adding your like document and counting it, in one
// batch, the way LikeService.setLiked does. Unliking reverses both.
function likeBatch(uid, photoId, { liked = true, likeId = uid, countBy } = {}) {
  const db = { alice, bob, g7xQ2: guest }[uid]().firestore();
  const b = writeBatch(db);
  const like = doc(db, `photos/${photoId}/likes/${likeId}`);
  if (liked) b.set(like, { userId: likeId, createdAt: serverTimestamp() });
  else b.delete(like);
  b.update(doc(db, `photos/${photoId}`), { heartCount: increment(countBy ?? (liked ? 1 : -1)) });
  return b.commit();
}

// Posting a comment means adding it and counting it on its photo, in one
// batch, the way FirestoreService.addComment does.
function commentBatch(ctx, photoId, data, countBy = 1) {
  const db = ctx.firestore();
  const b = writeBatch(db);
  b.set(doc(collection(db, `comments/${photoId}/messages`)), data);
  if (countBy) b.update(doc(db, `photos/${photoId}`), { commentCount: increment(countBy) });
  return b.commit();
}

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

// Uploads are closed unless config/app says otherwise; reset() clears it.
const openUploads = (open = true) => seed((db) => setDoc(doc(db, 'config/app'), { uploadsOpen: open }));

console.log('Firestore — uploads closed (the default)');
await check('anyone can read the upload switch', async () => {
  await openUploads(false);
  await assertSucceeds(getDoc(doc(anon().firestore(), 'config/app')));
});
await reset();
await check('with no switch, a user cannot create a photo', () => assertFails(addDoc(collection(alice().firestore(), 'photos'), photo('alice'))));
await check('with no switch, a guest cannot create a photo', () => assertFails(addDoc(collection(guest().firestore(), 'photos'), photo('g7xQ2'))));
await check('with no switch, admin can create a photo', () => assertSucceeds(addDoc(collection(admin().firestore(), 'photos'), photo('bill'))));
await check('unverified admin email cannot create a photo', () => assertFails(addDoc(collection(fakeAdmin().firestore(), 'photos'), photo('mallory'))));
await check('admin still cannot create a photo in someone else\'s name', () => assertFails(addDoc(collection(admin().firestore(), 'photos'), photo('alice'))));
await check('uploadsOpen: false keeps users out', async () => {
  await openUploads(false);
  await assertFails(addDoc(collection(alice().firestore(), 'photos'), photo('alice')));
});
await check('a user cannot open uploads', () => assertFails(setDoc(doc(alice().firestore(), 'config/app'), { uploadsOpen: true })));
await check('admin can open and close uploads', async () => {
  await assertSucceeds(setDoc(doc(admin().firestore(), 'config/app'), { uploadsOpen: true }));
  await assertSucceeds(setDoc(doc(admin().firestore(), 'config/app'), { uploadsOpen: false }));
});
await check('closed uploads still allow likes and comments', async () => {
  await assertSucceeds(likeBatch('bob', 'p1'));
  await assertSucceeds(commentBatch(guest(), 'p1', post('g7xQ2')));
});

console.log('Firestore — photos (uploads open)');
await reset();
await openUploads();
await check('signed-out user cannot create a photo', () => assertFails(addDoc(collection(anon().firestore(), 'photos'), photo('x'))));
await check('user can create a photo as themselves', () => assertSucceeds(addDoc(collection(alice().firestore(), 'photos'), photo('alice'))));
await check('guest can create a photo as themselves', () => assertSucceeds(addDoc(collection(guest().firestore(), 'photos'), photo('g7xQ2'))));
await check('cannot create a photo in someone else\'s name', () => assertFails(addDoc(collection(alice().firestore(), 'photos'), photo('bob'))));
await check('a new photo cannot start with likes', () => assertFails(addDoc(collection(alice().firestore(), 'photos'), photo('alice', { heartCount: 50 }))));
await check('a new photo cannot carry its own date', () => assertFails(addDoc(collection(alice().firestore(), 'photos'), photo('alice', { createdAt: new Date('2020-01-01') }))));
await check('a new photo cannot add fields the app does not write', () => assertFails(addDoc(collection(alice().firestore(), 'photos'), photo('alice', { featured: true }))));
await check('a new photo cannot be signed with another name', () => assertFails(addDoc(collection(alice().firestore(), 'photos'), photo('alice', { userName: 'Bill Kapsalis' }))));
await check('owner cannot set their own like count', () => assertFails(updateDoc(doc(alice().firestore(), 'photos/p1'), { heartCount: 99 })));
await check('owner can edit details', () => assertSucceeds(updateDoc(doc(alice().firestore(), 'photos/p1'), { locationName: 'New', category: 'Hiking Areas', locationRegion: 'X' })));
await check('owner cannot give the photo away', () => assertFails(updateDoc(doc(alice().firestore(), 'photos/p1'), { userId: 'bob' })));
await check('non-owner cannot edit details', () => assertFails(updateDoc(doc(bob().firestore(), 'photos/p1'), { locationName: 'Hacked' })));
await check('anyone signed in can like once', () => assertSucceeds(likeBatch('bob', 'p1')));
await check('a second like by the same person fails', () => assertFails(likeBatch('bob', 'p1')));
await check('they can unlike, which takes the count back down', () => assertSucceeds(likeBatch('bob', 'p1', { liked: false })));
await check('cannot unlike a photo you have not liked', () => assertFails(likeBatch('alice', 'p2', { liked: false })));
await check('the count cannot move without a like document', () => assertFails(updateDoc(doc(bob().firestore(), 'photos/p1'), { heartCount: increment(1) })));
await check('a like document cannot be added without counting it', async () => {
  const db = bob().firestore();
  await assertFails(setDoc(doc(db, 'photos/p2/likes/bob'), { userId: 'bob', createdAt: serverTimestamp() }));
});
await check('cannot like on someone else\'s behalf', () => assertFails(likeBatch('bob', 'p2', { likeId: 'alice' })));
await check('a like cannot count for two', () => assertFails(likeBatch('alice', 'p2', { countBy: 2 })));
await check('a guest can like too', () => assertSucceeds(likeBatch('g7xQ2', 'p2')));
await check('you can see your own like, not other people\'s', async () => {
  await assertSucceeds(getDoc(doc(guest().firestore(), 'photos/p2/likes/g7xQ2')));
  await assertFails(getDoc(doc(alice().firestore(), 'photos/p2/likes/g7xQ2')));
});
await check('the app can list your own likes across photos', () =>
  assertSucceeds(getDocs(query(collectionGroup(guest().firestore(), 'likes'), where('userId', '==', 'g7xQ2')))));
await check('nobody can list someone else\'s likes', () =>
  assertFails(getDocs(query(collectionGroup(bob().firestore(), 'likes'), where('userId', '==', 'g7xQ2')))));
await check('the photo owner can list its likes, to clear them', () =>
  assertSucceeds(getDocs(collection(bob().firestore(), 'photos/p2/likes'))));
await check('nobody else can list a photo\'s likes', () =>
  assertFails(getDocs(collection(alice().firestore(), 'photos/p2/likes'))));
await check('the photo owner can clear its likes when deleting it', () =>
  assertSucceeds(deleteDoc(doc(bob().firestore(), 'photos/p2/likes/g7xQ2'))));
await check('non-owner cannot like by +5', () => assertFails(updateDoc(doc(bob().firestore(), 'photos/p1'), { heartCount: increment(5) })));
await check('non-owner cannot reset likes', () => assertFails(updateDoc(doc(bob().firestore(), 'photos/p1'), { heartCount: 0 })));
await check('non-owner cannot sneak an edit in with a like', () => assertFails(updateDoc(doc(bob().firestore(), 'photos/p1'), { heartCount: increment(1), locationName: 'Hacked' })));
await check('signed-out user cannot like', () => assertFails(updateDoc(doc(anon().firestore(), 'photos/p1'), { heartCount: increment(1) })));
await check('commentCount can move +1', () => assertSucceeds(updateDoc(doc(bob().firestore(), 'photos/p1'), { commentCount: increment(1) })));
await check('commentCount can move -1', () => assertSucceeds(updateDoc(doc(bob().firestore(), 'photos/p1'), { commentCount: increment(-1) })));
await check('commentCount cannot jump', () => assertFails(updateDoc(doc(bob().firestore(), 'photos/p1'), { commentCount: 99 })));
await check('like works on a photo with no heartCount field', async () => {
  await seed((db) => setDoc(doc(db, 'photos/old'), { userId: 'alice', imageUrl: 'x' }));
  await assertSucceeds(likeBatch('bob', 'old'));
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
await check('user can comment as themselves', () => assertSucceeds(commentBatch(bob(), 'p1', post('bob'))));
await check('cannot comment as someone else', () => assertFails(commentBatch(bob(), 'p1', post('alice'))));
await check('signed-out user cannot comment', () => assertFails(addDoc(collection(anon().firestore(), 'comments/p1/messages'), { userId: 'x', text: 'x' })));
await check('a comment must be counted on its photo in the same write', () => assertFails(commentBatch(bob(), 'p1', post('bob'), 0)));
await check('a comment cannot be signed with the moderator\'s name', () => assertFails(commentBatch(bob(), 'p1', post('bob', { userName: 'Bill Kapsalis' }))));
await check('a guest comments under their own guest name', () => assertSucceeds(commentBatch(guest(), 'p1', post('g7xQ2'))));
await check('a guest cannot use another guest\'s name', () => assertFails(commentBatch(guest(), 'p1', post('g7xQ2', { userName: 'Guest zzzz' }))));
await check('the moderator signs as themselves', () => assertSucceeds(commentBatch(admin(), 'p1', post('bill'))));
await check('a comment cannot be empty', () => assertFails(commentBatch(bob(), 'p1', post('bob', { text: '   ' }))));
await check('a comment cannot be longer than 2000 characters', () => assertFails(commentBatch(bob(), 'p1', post('bob', { text: 'x'.repeat(2001) }))));
await check('a comment of exactly 2000 characters is fine', () => assertSucceeds(commentBatch(bob(), 'p1', post('bob', { text: 'x'.repeat(2000) }))));
await check('comment text must be text', () => assertFails(commentBatch(bob(), 'p1', post('bob', { text: 42 }))));
await check('a comment cannot carry its own time', () => assertFails(commentBatch(bob(), 'p1', post('bob', { timestamp: new Date('2030-01-01') }))));
await check('a comment cannot start with likes', () => assertFails(commentBatch(bob(), 'p1', post('bob', { heartCount: 9 }))));
await check('a comment cannot add fields the app does not write', () => assertFails(commentBatch(bob(), 'p1', post('bob', { isMe: true }))));
await check('an author cannot change who wrote a comment or when', async () => {
  await assertFails(updateDoc(doc(bob().firestore(), 'comments/p1/messages/c-bob'), { userId: 'alice' }));
  await assertFails(updateDoc(doc(bob().firestore(), 'comments/p1/messages/c-bob'), { timestamp: new Date('2030-01-01') }));
});
await check('an edit cannot make a comment empty', () => assertFails(updateDoc(doc(bob().firestore(), 'comments/p1/messages/c-bob'), { text: '' })));
await check('an author cannot rename their posts to someone else', () => assertFails(updateDoc(doc(bob().firestore(), 'comments/p1/messages/c-bob'), { userName: 'Bill Kapsalis', userInitials: 'BK', userAvatarColor: 1 })));
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
  assertSucceeds(updateDoc(doc(bob().firestore(), 'chats/loc1/messages/m-bob'), { userName: 'bob', userInitials: 'B', userAvatarColor: 1 })));
await check('cannot rename someone else\'s chat message', () =>
  assertFails(updateDoc(doc(alice().firestore(), 'chats/loc1/messages/m-bob'), { userName: 'x' })));
await check('chat message must be sent as self', () => assertFails(addDoc(collection(alice().firestore(), 'chats/loc1/messages'), { userId: 'bob', text: 'x' })));
await check('a chat message as the app writes it is accepted', () => assertSucceeds(addDoc(collection(alice().firestore(), 'chats/loc1/messages'), post('alice', { reactionCount: 0 }))));
await check('a chat message cannot carry the old isMe flag', () => assertFails(addDoc(collection(alice().firestore(), 'chats/loc1/messages'), post('alice', { isMe: true }))));
await check('a chat message cannot be signed with another name', () => assertFails(addDoc(collection(alice().firestore(), 'chats/loc1/messages'), post('alice', { userName: 'bob' }))));

console.log('Storage');
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
const meta = (uid) => ({ contentType: 'image/jpeg', customMetadata: uid ? { ownerUid: uid } : {} });
await env.clearStorage();
await reset();
await check('with no switch, a user cannot upload', () => assertFails(uploadBytes(ref(alice().storage(), 'photos/museums/a.jpg'), jpeg, meta('alice'))));
await check('with no switch, admin can upload', () => assertSucceeds(uploadBytes(ref(admin().storage(), 'photos/museums/admin.jpg'), jpeg, meta('bill'))));
await check('uploadsOpen: false keeps users out of Storage', async () => {
  await openUploads(false);
  await assertFails(uploadBytes(ref(alice().storage(), 'photos/museums/a.jpg'), jpeg, meta('alice')));
});
await openUploads();
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
