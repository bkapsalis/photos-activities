import { DecodedIdToken, getAuth } from "firebase-admin/auth";
import {
  DocumentReference,
  FieldValue,
  getFirestore,
  QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

import { isModerator } from "./config";
import { discardPost } from "./moderation";
import { analysisRef, storageLocation } from "./photos";

/**
 * Deleting an account, which App Store guideline 5.1.1(v) and Google Play
 * require of an app people sign up to: everything the person put in, then
 * the account itself. The app's "Delete account" in Profile calls it
 * through deleteMyAccount.
 */

/** What deleting an account removed, for the log. */
export interface DeletedAccount {
  photos: number;
  comments: number;
  chatMessages: number;
  likes: number;
}

/**
 * How old a sign-in may be when deleting the account, as Firebase asks of
 * the app itself: someone who picks up an unlocked phone cannot delete the
 * owner's account without signing in as them.
 */
export const RECENT_SIGN_IN_SECONDS = 5 * 60;

/**
 * Why the account [token] belongs to may not be deleted now, worded for
 * its owner, or null if it may. A guest has nothing to sign in with again,
 * so any guest session will do.
 */
export function deletionRefusal(
  token: Pick<DecodedIdToken, "auth_time" | "firebase" | "email" | "email_verified">,
  nowSeconds: number,
): string | null {
  if (isModerator(token)) {
    return "A moderator's account cannot be deleted in the app: every photo " +
      "it posted would go with it. Take it off the moderator list first.";
  }
  const guest = token.firebase?.sign_in_provider === "anonymous";
  if (!guest && nowSeconds - token.auth_time > RECENT_SIGN_IN_SECONDS) {
    return "To keep your account safe, please sign in again, then delete it.";
  }
  return null;
}

const db = () => getFirestore();

// A batch holds at most 500 writes: each chunk's deletes plus a count
// update for every photo they touch.
const CHUNK = 250;

/** Deletes [uid]'s account and everything in it. Safe to run again. */
export async function deleteAccount(uid: string): Promise<DeletedAccount> {
  const photos = await deletePhotos(uid);

  // Comments and chat messages share the "messages" collection group.
  const messages = await db()
    .collectionGroup("messages")
    .where("userId", "==", uid)
    .get();
  const comments = messages.docs.filter((doc) =>
    doc.ref.path.startsWith("comments/"),
  );
  const chats = messages.docs.filter(
    (doc) => !doc.ref.path.startsWith("comments/"),
  );
  await deleteCounted(
    comments,
    (ref) => db().collection("photos").doc(ref.parent.parent!.id),
    "commentCount",
  );
  await deleteCounted(chats, () => null, null);

  const likes = await db()
    .collectionGroup("likes")
    .where("userId", "==", uid)
    .get();
  await deleteCounted(likes.docs, (ref) => ref.parent.parent, "heartCount");

  // Copies of their posts the content filter took down.
  const removed = await db()
    .collection("blockedContent")
    .where("authorId", "==", uid)
    .get();
  for (const record of removed.docs) await discardPost(record.id);

  await settleReports(uid);

  await db().collection("userSafety").doc(uid).delete();
  await db().collection("bannedUsers").doc(uid).delete();
  await db().recursiveDelete(db().collection("users").doc(uid));

  // Last, so that if anything above fails the person can simply try again.
  try {
    await getAuth().deleteUser(uid);
  } catch (error) {
    if ((error as { code?: string }).code !== "auth/user-not-found") {
      throw error;
    }
  }

  return {
    photos,
    comments: comments.length,
    chatMessages: chats.length,
    likes: likes.size,
  };
}

/**
 * The person's photos, each with its image file, comment thread, likes
 * and AI look: the same cleanup as deleting a photo in the app.
 */
async function deletePhotos(uid: string): Promise<number> {
  const photos = await db().collection("photos").where("userId", "==", uid).get();
  for (const photo of photos.docs) {
    const location = storageLocation(String(photo.get("imageUrl") ?? ""));
    if (location) {
      await getStorage()
        .bucket(location.bucket)
        .file(location.path)
        .delete({ ignoreNotFound: true });
    }
    await db().recursiveDelete(db().collection("comments").doc(photo.id));
    await analysisRef(photo.id).delete();
    // The photo and its likes subcollection.
    await db().recursiveDelete(photo.ref);
  }
  return photos.size;
}

/**
 * Deletes [docs] and takes each off [counter] on the photo [photoOf]
 * names, as the app does when someone deletes a comment or unlikes a
 * photo. Each chunk's deletes and count changes are one batch, so the
 * counts never drift from what is left.
 */
async function deleteCounted(
  docs: QueryDocumentSnapshot[],
  photoOf: (ref: DocumentReference) => DocumentReference | null,
  counter: "commentCount" | "heartCount" | null,
): Promise<void> {
  for (let i = 0; i < docs.length; i += CHUNK) {
    const chunk = docs.slice(i, i + CHUNK);
    const counts = new Map<string, number>();
    for (const doc of chunk) {
      const photo = photoOf(doc.ref);
      if (photo) counts.set(photo.path, (counts.get(photo.path) ?? 0) + 1);
    }
    const photos = counts.size
      ? await db().getAll(...[...counts.keys()].map((path) => db().doc(path)))
      : [];

    const batch = db().batch();
    for (const doc of chunk) batch.delete(doc.ref);
    for (const photo of photos) {
      // A photo deleted earlier left its likes and comments behind; there
      // is no count left to correct.
      if (photo.exists && counter) {
        batch.update(photo.ref, {
          [counter]: FieldValue.increment(-counts.get(photo.ref.path)!),
        });
      }
    }
    await batch.commit();
  }
}

/**
 * Reports they sent stay with the moderator, since they are about someone
 * else's post, but no longer say who sent them. Open reports about their
 * own posts are closed: those posts are gone.
 */
async function settleReports(uid: string): Promise<void> {
  const reports = db().collection("reports");
  const sent = await reports.where("reporterId", "==", uid).get();
  const about = await reports.where("authorId", "==", uid).get();
  const writes = [
    ...sent.docs.map((doc) => ({
      ref: doc.ref,
      change: { reporterId: FieldValue.delete() } as Record<string, unknown>,
    })),
    ...about.docs
      .filter((doc) => doc.get("status") === "open")
      .map((doc) => ({
        ref: doc.ref,
        change: {
          status: "accountDeleted",
          settledAt: FieldValue.serverTimestamp(),
        } as Record<string, unknown>,
      })),
  ];
  for (let i = 0; i < writes.length; i += CHUNK) {
    const batch = db().batch();
    for (const { ref, change } of writes.slice(i, i + CHUNK)) {
      batch.update(ref, change);
    }
    await batch.commit();
  }
}
