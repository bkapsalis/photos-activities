import {
  DocumentData,
  DocumentReference,
  FieldValue,
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

import {
  flaggedFor,
  isTextFlagged,
  SafetyVerdict,
  TextVerdict,
} from "./analysis";
import { AI_AUTHOR } from "./config";
import { TextChecker } from "./model";
import { analysisRef, storageLocation } from "./photos";

/**
 * The content filter: with config/app's contentFilter on, a photo, comment
 * or chat message the AI flags is taken down within seconds of being
 * posted. A copy waits in blockedContent for a moderator, who can put it
 * back or delete it for good, and the author is told.
 */

export type PostKind = "photo" | "comment" | "chat";

/** What blockedContent/{key} holds: a post the filter took down. */
export interface RemovedPost {
  kind: PostKind;
  /** Where the post was, and where putting it back recreates it. */
  path: string;
  /** The post as it was, to recreate it exactly. */
  data: DocumentData;
  authorId: string;
  authorName: string;
  /** What the AI objected to, such as ["Hate"]. */
  flaggedFor: string[];
  /** The AI's own few words on it, for the moderator. */
  reason: string;
  removedAt: Timestamp;
  status: "removed" | "restored";
  restoredAt?: Timestamp;
}

/**
 * What users/{uid}/notices/{key} holds: tells the author a post of theirs
 * was taken down, or later put back. Shown once by the app.
 */
export interface Notice {
  kind: PostKind;
  restored: boolean;
  flaggedFor: string[];
  /** Enough to recognise the post: its text, or a photo's place. */
  preview: string;
  createdAt: Timestamp;
  seen: boolean;
}

/** A request the moderator made that cannot be carried out. */
export class ModerationProblem extends Error {
  constructor(
    message: string,
    readonly kind: "notFound" | "conflict",
  ) {
    super(message);
  }
}

const db = () => getFirestore();

export const removedRef = (key: string) =>
  db().collection("blockedContent").doc(key);

const noticeRef = (userId: string, key: string) =>
  db().collection("users").doc(userId).collection("notices").doc(key);

/**
 * A post's blockedContent id, made from its path so that a trigger on the
 * post can find it: "comments/p1/messages/c1" is "comments_p1_messages_c1".
 */
export function removedKey(path: string): string {
  return path.replace(/\//g, "_");
}

/** Whether a moderator has switched the filter on. Off until set. */
export async function contentFilterOn(): Promise<boolean> {
  const config = await db().doc("config/app").get();
  return config.get("contentFilter") === true;
}

/** The photo a comment belongs to: comments/{photoId}/messages/{id}. */
function photoOfComment(comment: DocumentReference): DocumentReference {
  return db().collection("photos").doc(comment.parent.parent!.id);
}

function previewOf(kind: PostKind, data: DocumentData): string {
  const text =
    kind === "photo"
      ? String(data.locationName ?? "")
      : String(data.text ?? "");
  return text.length <= 200 ? text : `${text.slice(0, 199)}…`;
}

/**
 * Takes a post down: keeps a copy for the moderator, deletes it, uncounts a
 * comment on its photo, and tells the author. Returns false if the post was
 * already gone.
 */
export async function removePost(
  kind: PostKind,
  ref: DocumentReference,
  verdict: SafetyVerdict | TextVerdict,
): Promise<boolean> {
  const key = removedKey(ref.path);
  return db().runTransaction(async (tx) => {
    const post = await tx.get(ref);
    if (!post.exists) return false;
    const data = post.data()!;
    const photo = kind === "comment" ? await tx.get(photoOfComment(ref)) : null;

    const labels = flaggedFor(verdict);
    const authorId = String(data.userId ?? "");
    tx.set(removedRef(key), {
      kind,
      path: ref.path,
      data,
      authorId,
      authorName: String(data.userName ?? ""),
      flaggedFor: labels,
      reason: verdict.reason,
      removedAt: FieldValue.serverTimestamp(),
      status: "removed",
    });
    tx.delete(ref);
    if (photo?.exists) {
      tx.update(photo.ref, { commentCount: FieldValue.increment(-1) });
    }
    if (authorId) {
      tx.set(noticeRef(authorId, key), {
        kind,
        restored: false,
        flaggedFor: labels,
        preview: previewOf(kind, data),
        createdAt: FieldValue.serverTimestamp(),
        seen: false,
      });
    }
    return true;
  });
}

/**
 * Runs the filter over a comment or chat message that was just written:
 * new, or with its text changed. [before] and [after] are the document's
 * data either side of the write.
 */
export async function checkPost(
  kind: "comment" | "chat",
  ref: DocumentReference,
  before: DocumentData | undefined,
  after: DocumentData | undefined,
  check: TextChecker,
): Promise<"removed" | "kept" | "skipped"> {
  if (!after || after.userId === AI_AUTHOR.userId) return "skipped";
  const text = typeof after.text === "string" ? after.text : "";
  // Likes, renames and the like leave the words as they were.
  if (!text.trim() || before?.text === text) return "skipped";
  if (!(await contentFilterOn())) return "skipped";
  if (!before) {
    // A moderator putting a post back recreates it; it is not checked again.
    const removed = await removedRef(removedKey(ref.path)).get();
    if (removed.get("status") === "restored") return "skipped";
  }

  const { verdict } = await check(text);
  if (!isTextFlagged(verdict)) return "kept";
  return (await removePost(kind, ref, verdict)) ? "removed" : "skipped";
}

/**
 * Takes down a new photo the AI flagged, if the filter is on. Its analysis
 * stays: onPhotoDeleted keeps it for a photo in blockedContent, and with it
 * there a restored photo is not checked again.
 */
export async function removeFlaggedPhoto(
  photoId: string,
  safety: SafetyVerdict,
): Promise<boolean> {
  if (!(await contentFilterOn())) return false;
  return removePost("photo", db().collection("photos").doc(photoId), safety);
}

/**
 * A moderator's "Put back": recreates the post as it was, counts a comment
 * on its photo again, and tells the author.
 */
export async function restorePost(key: string): Promise<void> {
  await db().runTransaction(async (tx) => {
    const record = await tx.get(removedRef(key));
    if (!record.exists) {
      throw new ModerationProblem("That post is no longer in the list.", "notFound");
    }
    const removed = record.data() as RemovedPost;
    if (removed.status !== "removed") {
      throw new ModerationProblem("That post has already been put back.", "conflict");
    }
    const ref = db().doc(removed.path);
    const photo =
      removed.kind === "comment" ? await tx.get(photoOfComment(ref)) : null;
    if (photo && !photo.exists) {
      throw new ModerationProblem(
        "The photo that comment was on has been deleted.",
        "notFound",
      );
    }

    tx.create(ref, removed.data);
    if (photo) {
      tx.update(photo.ref, { commentCount: FieldValue.increment(1) });
    }
    if (removed.kind === "photo") {
      // Present, so onPhotoCreated leaves the restored photo alone.
      tx.set(
        analysisRef(ref.id),
        { moderatorCleared: true },
        { merge: true },
      );
    }
    tx.update(record.ref, {
      status: "restored",
      restoredAt: FieldValue.serverTimestamp(),
    });
    if (removed.authorId) {
      tx.set(noticeRef(removed.authorId, key), {
        kind: removed.kind,
        restored: true,
        flaggedFor: removed.flaggedFor,
        preview: previewOf(removed.kind, removed.data),
        createdAt: FieldValue.serverTimestamp(),
        seen: false,
      });
    }
  });
}

/**
 * A moderator's "Delete for good": drops the copy, and for a photo its
 * image file and analysis too.
 */
export async function discardPost(key: string): Promise<void> {
  const record = await removedRef(key).get();
  if (!record.exists) return;
  const removed = record.data() as RemovedPost;
  // A photo that was put back is live again: only the record goes.
  if (removed.kind === "photo" && removed.status === "removed") {
    const location = storageLocation(String(removed.data.imageUrl ?? ""));
    if (location) {
      await getStorage()
        .bucket(location.bucket)
        .file(location.path)
        .delete({ ignoreNotFound: true });
    }
    await analysisRef(db().doc(removed.path).id).delete();
  }
  await record.ref.delete();
}
