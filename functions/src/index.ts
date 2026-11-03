/**
 * Cloud Functions for Bill's Bay Area Fun Activities.
 *
 * Every new photo gets one AI look (onPhotoCreated), which records whether
 * it is safe to show and which animals are in it. Moderators then post the
 * animals as "AI Naturalist" comments, one photo at a time
 * (describeAnimals) or for every photo (describeAnimalsBatch).
 */
import { initializeApp } from "firebase-admin/app";
import * as logger from "firebase-functions/logger";
import { setGlobalOptions } from "firebase-functions/v2";
import {
  onDocumentCreated,
  onDocumentDeleted,
} from "firebase-functions/v2/firestore";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";

import { ADMIN_EMAILS, REGION } from "./config";
import { analyzeWithGemini } from "./model";
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
      logger.info("Checked new photo", {
        photoId,
        flagged: analysis.flagged,
        animals: analysis.animals?.map((animal) => animal.commonName),
        usage: analysis.usage,
      });
    } catch (error) {
      // Saved on the analysis already; the moderator's button retries it.
      logger.error("Could not check new photo", { photoId, error });
    }
  },
);

/** Clears a deleted photo's analysis, which nothing else would remove. */
export const onPhotoDeleted = onDocumentDeleted(
  { document: "photos/{photoId}", region: REGION },
  async (event) => {
    await analysisRef(event.params.photoId).delete();
  },
);

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
      throw asHttpsError(error, photoId);
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
 * Only moderators may spend money on the model. Matched as firestore.rules
 * match them: on a verified email.
 */
function requireModerator(request: CallableRequest): void {
  const token = request.auth?.token;
  const email = String(token?.email ?? "").toLowerCase();
  if (token?.email_verified !== true || !ADMIN_EMAILS.includes(email)) {
    throw new HttpsError("permission-denied", "Only a moderator can do this.");
  }
}

function asHttpsError(error: unknown, photoId: string): HttpsError {
  if (error instanceof HttpsError) return error;
  if (error instanceof PhotoProblem) {
    return new HttpsError(
      error.kind === "notFound" ? "not-found" : "failed-precondition",
      error.message,
    );
  }
  logger.error("Could not describe animals", { photoId, error });
  return new HttpsError(
    "unavailable",
    "The AI could not look at this photo just now. Please try again.",
  );
}
