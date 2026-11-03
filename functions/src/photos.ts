import {
  DocumentData,
  FieldValue,
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

import { Animal, animalCommentText, isFlagged, SafetyVerdict } from "./analysis";
import { AI_AUTHOR, MAX_INLINE_IMAGE_BYTES } from "./config";
import { Analyzer, ImageData, Usage } from "./model";

/**
 * What photoAnalysis/{photoId} holds: the AI's look at a photo, kept apart
 * from the photo itself because only moderators may read the safety verdict
 * (see firestore.rules).
 */
export interface StoredAnalysis {
  status: "done" | "failed";
  model: string;
  analyzedAt: Timestamp;
  safety?: SafetyVerdict;
  flagged?: boolean;
  animals?: Animal[];
  usage?: Usage;
  /** Why it failed, for status "failed". */
  error?: string;
  /** Set once the animals have been posted as comments (even none). */
  animalComments?: {
    postedAt: Timestamp;
    count: number;
    commentIds: string[];
  };
}

/** What happened when a moderator asked for a photo's animals. */
export interface AnimalCommentsOutcome {
  status: "posted" | "noAnimals" | "alreadyPosted";
  count: number;
  names: string[];
}

/** A photo that is gone, or a URL the server cannot read the image from. */
export class PhotoProblem extends Error {
  constructor(
    message: string,
    readonly kind: "notFound" | "unreadable" | "tooLarge",
  ) {
    super(message);
  }
}

const db = () => getFirestore();
const photoRef = (photoId: string) => db().collection("photos").doc(photoId);
export const analysisRef = (photoId: string) =>
  db().collection("photoAnalysis").doc(photoId);
const commentsRef = (photoId: string) =>
  db().collection("comments").doc(photoId).collection("messages");

/**
 * The bucket and object path inside a Firebase Storage download URL, which
 * is what PhotoPost.imageUrl holds:
 * https://firebasestorage.googleapis.com/v0/b/BUCKET/o/ENCODED_PATH?alt=media&token=...
 * Null for anything else.
 */
export function storageLocation(
  imageUrl: string,
): { bucket: string; path: string } | null {
  let url: URL;
  try {
    url = new URL(imageUrl);
  } catch {
    return null;
  }
  if (url.hostname !== "firebasestorage.googleapis.com") return null;
  const match = /^\/v0\/b\/([^/]+)\/o\/(.+)$/.exec(url.pathname);
  if (!match) return null;
  try {
    return { bucket: match[1], path: decodeURIComponent(match[2]) };
  } catch {
    return null;
  }
}

/** Reads a photo's image file straight from Storage. */
async function loadImage(imageUrl: string): Promise<ImageData> {
  const location = storageLocation(imageUrl);
  if (!location) {
    throw new PhotoProblem("The image is not in Firebase Storage.", "unreadable");
  }
  const file = getStorage().bucket(location.bucket).file(location.path);
  const [metadata] = await file.getMetadata();
  if (Number(metadata.size ?? 0) > MAX_INLINE_IMAGE_BYTES) {
    throw new PhotoProblem("The image is too large to send.", "tooLarge");
  }
  const [bytes] = await file.download();
  return { bytes, mimeType: metadata.contentType ?? "image/jpeg" };
}

/**
 * Has the model look at a photo and saves what it found. A failure is saved
 * too, so it can be seen and retried, and is then thrown.
 */
export async function analyzePhoto(
  photoId: string,
  photo: DocumentData,
  analyze: Analyzer,
): Promise<StoredAnalysis> {
  let stored: StoredAnalysis;
  try {
    const image = await loadImage(String(photo.imageUrl ?? ""));
    const { analysis, model, usage } = await analyze(image, {
      locationName: photo.locationName,
      locationRegion: photo.locationRegion,
      category: photo.category,
    });
    stored = {
      status: "done",
      model,
      analyzedAt: Timestamp.now(),
      safety: analysis.safety,
      flagged: isFlagged(analysis.safety),
      animals: analysis.animals,
      usage,
    };
  } catch (error) {
    // Merged, like a success below, so a record of comments already posted
    // is never lost.
    await analysisRef(photoId).set(
      {
        status: "failed",
        model: "",
        analyzedAt: Timestamp.now(),
        error: error instanceof Error ? error.message : String(error),
      } satisfies StoredAnalysis,
      { merge: true },
    );
    throw error;
  }
  // A re-check replaces the findings but keeps any record of comments
  // already posted, so they are never posted twice.
  await analysisRef(photoId).set(
    { ...stored, error: FieldValue.delete() },
    { merge: true },
  );
  return stored;
}

/**
 * Posts one AI comment per animal in the photo, looking at it first if that
 * has not happened yet. Runs at most once per photo: a second request, or
 * two at once, gets "alreadyPosted".
 */
export async function postAnimalComments(
  photoId: string,
  analyze: Analyzer,
): Promise<AnimalCommentsOutcome> {
  const photo = await photoRef(photoId).get();
  if (!photo.exists) {
    throw new PhotoProblem("That photo no longer exists.", "notFound");
  }
  const existing = (await analysisRef(photoId).get()).data() as
    | StoredAnalysis
    | undefined;
  if (existing?.animalComments) return alreadyPosted(existing);
  if (existing?.status !== "done") {
    await analyzePhoto(photoId, photo.data()!, analyze);
  }

  return db().runTransaction(async (tx) => {
    const [analysisSnap, photoSnap] = await Promise.all([
      tx.get(analysisRef(photoId)),
      tx.get(photoRef(photoId)),
    ]);
    if (!photoSnap.exists) {
      throw new PhotoProblem("That photo no longer exists.", "notFound");
    }
    const analysis = analysisSnap.data() as StoredAnalysis;
    if (analysis.animalComments) return alreadyPosted(analysis);

    const animals = analysis.animals ?? [];
    const commentIds: string[] = [];
    for (const animal of animals) {
      const comment = commentsRef(photoId).doc();
      commentIds.push(comment.id);
      tx.create(comment, {
        ...AI_AUTHOR,
        text: animalCommentText(animal),
        timestamp: FieldValue.serverTimestamp(),
        heartCount: 0,
        // What the app reads to badge the comment and lay it out. People
        // cannot write either field: firestore.rules list what a comment
        // may hold.
        ai: true,
        animal,
      });
    }
    if (animals.length > 0) {
      // As the app does for a person's comment: the count on the photo
      // moves in the same write as the thread.
      tx.update(photoRef(photoId), {
        commentCount: FieldValue.increment(animals.length),
      });
    }
    tx.update(analysisRef(photoId), {
      animalComments: {
        postedAt: FieldValue.serverTimestamp(),
        count: animals.length,
        commentIds,
      },
    });
    return {
      status: animals.length > 0 ? "posted" : "noAnimals",
      count: animals.length,
      names: animals.map((animal) => animal.commonName),
    };
  });
}

function alreadyPosted(analysis: StoredAnalysis): AnimalCommentsOutcome {
  return {
    status: "alreadyPosted",
    count: analysis.animalComments?.count ?? 0,
    names: (analysis.animals ?? []).map((animal) => animal.commonName),
  };
}

export interface BatchOutcome {
  /** Photos handled in this call. */
  checked: number;
  commentsAdded: number;
  /** Photos in this call that could not be checked. */
  failed: number;
  /** Photos still waiting after this call. */
  remaining: number;
  /**
   * Photos whose check has failed, this call's included. Batches leave them
   * out; the per-photo button retries them.
   */
  failedTotal: number;
}

/**
 * Posts the animals for the next [limit] photos that have not had theirs
 * posted. The app calls it again until nothing remains, showing progress,
 * so no single call runs into the function's time limit.
 *
 * Photos whose check failed before are left out, so one bad image cannot
 * stall the run; the per-photo button retries them.
 */
export async function postAnimalCommentsBatch(
  limit: number,
  analyze: Analyzer,
): Promise<BatchOutcome> {
  const photos = await db().collection("photos").select().get();
  if (photos.empty) {
    return {
      checked: 0,
      commentsAdded: 0,
      failed: 0,
      remaining: 0,
      failedTotal: 0,
    };
  }
  const analyses = await db().getAll(
    ...photos.docs.map((doc) => analysisRef(doc.id)),
    { fieldMask: ["status", "animalComments"] },
  );

  const waiting: string[] = [];
  let failedEarlier = 0;
  analyses.forEach((snap, i) => {
    const analysis = snap.data() as StoredAnalysis | undefined;
    if (analysis?.animalComments) return;
    if (analysis?.status === "failed") {
      failedEarlier++;
      return;
    }
    waiting.push(photos.docs[i].id);
  });

  const batch = waiting.slice(0, limit);
  let commentsAdded = 0;
  let failed = 0;
  await inParallel(batch, 4, async (photoId) => {
    try {
      const outcome = await postAnimalComments(photoId, analyze);
      if (outcome.status === "posted") commentsAdded += outcome.count;
    } catch {
      // analyzePhoto saved the failure, which keeps it out of later batches.
      failed++;
    }
  });

  return {
    checked: batch.length,
    commentsAdded,
    failed,
    remaining: waiting.length - batch.length,
    failedTotal: failedEarlier + failed,
  };
}

/** Runs [work] over [items], at most [width] at a time. */
async function inParallel<T>(
  items: T[],
  width: number,
  work: (item: T) => Promise<void>,
): Promise<void> {
  let next = 0;
  const lanes = Array.from({ length: Math.min(width, items.length) }, async () => {
    while (next < items.length) await work(items[next++]);
  });
  await Promise.all(lanes);
}
