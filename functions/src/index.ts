/**
 * Cloud Functions for Bill's Bay Area Fun Activities.
 *
 * Every new photo gets one AI look (onPhotoCreated), which records whether
 * it is safe to show and which animals are in it. Moderators then post the
 * animals as "AI Naturalist" comments, one photo at a time
 * (describeAnimals) or for every photo (describeAnimalsBatch).
 *
 * With the content filter on, a flagged photo is taken down, and so is a
 * flagged comment or chat message (checkComment, checkChatMessage).
 * Moderators review what was taken down, and put it back or delete it for
 * good (restoreRemovedPost, discardRemovedPost).
 *
 * Anyone may delete their own account and everything in it
 * (deleteMyAccount).
 */
import { initializeApp } from "firebase-admin/app";
import * as logger from "firebase-functions/logger";
import { setGlobalOptions } from "firebase-functions/v2";
import {
  Change,
  DocumentSnapshot,
  FirestoreEvent,
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";

import { deleteAccount, deletionRefusal } from "./account";
import { isModerator, REGION } from "./config";
import { analyzeWithGemini, checkTextWithGemini } from "./model";
import {
  checkPost,
  discardPost,
  ModerationProblem,
  removedKey,
  removedRef,
  removeFlaggedPhoto,
  restorePost,
} from "./moderation";
import {
  analysisRef,
  analyzePhoto,
  PhotoProblem,
  postAnimalComments,
  postAnimalCommentsBatch,
} from "./photos";

initializeApp();

// A ceiling on cost as much as on load: nothing here needs more than a few
// copies running at once.
setGlobalOptions({ region: REGION, maxInstances: 5, memory: "512MiB" });

/** Looks at each new photo as soon as it is posted. */
export const onPhotoCreated = onDocumentCreated(
  // The region again: a global option has been known not to reach
  // Firestore triggers (firebase-functions issue 1502).
  { document: "photos/{photoId}", region: REGION, timeoutSeconds: 120 },
  async (event) => {
    const photo = event.data?.data();
    if (!photo) return;
    const photoId = event.params.photoId;
    // Events can arrive twice; one look per photo is enough.
    if ((await analysisRef(photoId).get()).exists) return;
    try {
      const analysis = await analyzePhoto(photoId, photo, analyzeWithGemini);
      const removed =
        analysis.flagged === true &&
        (await removeFlaggedPhoto(photoId, analysis.safety!));
      logger.info("Checked new photo", {
        photoId,
        flagged: analysis.flagged,
        removed,
        animals: analysis.animals?.map((animal) => animal.commonName),
        usage: analysis.usage,
      });
    } catch (error) {
      // Saved on the analysis already; the moderator's button retries it.
      logger.error("Could not check new photo", { photoId, error });
    }
  },
);

/**
 * Clears a deleted photo's analysis, which nothing else would remove,
 * unless the filter took the photo down: the moderator reviewing it reads
 * the analysis, and it keeps a restored photo from being checked again.
 */
export const onPhotoDeleted = onDocumentDeleted(
  { document: "photos/{photoId}", region: REGION },
  async (event) => {
    const photoId = event.params.photoId;
    const removed = await removedRef(removedKey(`photos/${photoId}`)).get();
    if (removed.get("status") === "removed") return;
    await analysisRef(photoId).delete();
  },
);

type WriteEvent = FirestoreEvent<Change<DocumentSnapshot> | undefined>;

/**
 * Runs the filter over a written comment or chat message. A failure leaves
 * the post up: a filter that cannot reach the AI must not silence everyone.
 */
async function checkWrittenPost(
  kind: "comment" | "chat",
  event: WriteEvent,
): Promise<void> {
  const change = event.data;
  if (!change) return;
  const path = change.after.ref.path;
  try {
    const outcome = await checkPost(
      kind,
      change.after.ref,
      change.before.data(),
      change.after.data(),
      checkTextWithGemini,
    );
    if (outcome === "removed") logger.info("Took down a post", { path });
  } catch (error) {
    logger.error("Could not check a post", { path, error });
  }
}

export const checkComment = onDocumentWritten(
  { document: "comments/{photoId}/messages/{commentId}", region: REGION },
  (event) => checkWrittenPost("comment", event),
);

export const checkChatMessage = onDocumentWritten(
  { document: "chats/{locationId}/messages/{messageId}", region: REGION },
  (event) => checkWrittenPost("chat", event),
);

/** A moderator's "Put back" on a post the filter took down. */
export const restoreRemovedPost = onCall(async (request) => {
  requireModerator(request);
  const key = removedPostKey(request);
  try {
    await restorePost(key);
  } catch (error) {
    throw asHttpsError(error, key);
  }
  return { ok: true };
});

/** A moderator's "Delete for good" on a post the filter took down. */
export const discardRemovedPost = onCall(async (request) => {
  requireModerator(request);
  const key = removedPostKey(request);
  try {
    await discardPost(key);
  } catch (error) {
    throw asHttpsError(error, key);
  }
  return { ok: true };
});

function removedPostKey(request: CallableRequest): string {
  const key = request.data?.key;
  // A blockedContent id: a path with its slashes made underscores.
  if (typeof key !== "string" || !/^[A-Za-z0-9_-]{1,700}$/.test(key)) {
    throw new HttpsError("invalid-argument", "Which post?");
  }
  return key;
}

/** A moderator's "More info about the animals" on one photo. */
export const describeAnimals = onCall(
  { timeoutSeconds: 120 },
  async (request) => {
    requireModerator(request);
    const photoId = request.data?.photoId;
    if (typeof photoId !== "string" || !photoId) {
      throw new HttpsError("invalid-argument", "Which photo?");
    }
    try {
      return await postAnimalComments(photoId, analyzeWithGemini);
    } catch (error) {
      throw asHttpsError(
        error,
        photoId,
        "The AI could not look at this photo just now. Please try again.",
      );
    }
  },
);

/**
 * A moderator's "Check all photos for animals": the next few photos per
 * call, which the app repeats until none remain.
 */
export const describeAnimalsBatch = onCall(
  { timeoutSeconds: 300 },
  async (request) => {
    requireModerator(request);
    const limit = Number(request.data?.limit ?? 12);
    if (!Number.isInteger(limit) || limit < 1 || limit > 40) {
      throw new HttpsError("invalid-argument", "limit must be 1 to 40.");
    }
    return postAnimalCommentsBatch(limit, analyzeWithGemini);
  },
);

/**
 * "Delete account" in the app's Profile: everything the caller put in,
 * then the account itself. The app has them sign in again first.
 */
export const deleteMyAccount = onCall(
  { timeoutSeconds: 300 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Please sign in first.");
    }
    const refusal = deletionRefusal(request.auth.token, Date.now() / 1000);
    if (refusal) throw new HttpsError("failed-precondition", refusal);
    const uid = request.auth.uid;
    try {
      const deleted = await deleteAccount(uid);
      logger.info("Deleted an account", { uid, ...deleted });
    } catch (error) {
      logger.error("Could not delete an account", { uid, error });
      throw new HttpsError(
        "unavailable",
        "Your account could not be deleted just now. Please try again.",
      );
    }
    return { ok: true };
  },
);

/**
 * Only moderators may spend money on the model. Matched as firestore.rules
 * match them: on a verified email.
 */
function requireModerator(request: CallableRequest): void {
  if (!isModerator(request.auth?.token)) {
    throw new HttpsError("permission-denied", "Only a moderator can do this.");
  }
}

/**
 * What the app is told when a moderator's request fails: the problems the
 * code expects in their own words, anything else as [fallback].
 */
function asHttpsError(
  error: unknown,
  id: string,
  fallback = "That could not be done just now. Please try again.",
): HttpsError {
  if (error instanceof HttpsError) return error;
  if (error instanceof PhotoProblem || error instanceof ModerationProblem) {
    return new HttpsError(
      error.kind === "notFound" ? "not-found" : "failed-precondition",
      error.message,
    );
  }
  logger.error("Could not carry out a moderator's request", { id, error });
  return new HttpsError("unavailable", fallback);
}
