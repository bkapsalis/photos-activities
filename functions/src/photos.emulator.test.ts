/**
 * Posting AI comments, against the Firestore and Storage emulators with a
 * stand-in model, so no AI call is made or paid for.
 *
 *   npm run test:emulator
 *
 * Skipped by plain `npm test`, which runs without emulators.
 */
import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

import { Animal } from "./analysis";
import { Analyzer } from "./model";
import {
  analyzePhoto,
  postAnimalComments,
  postAnimalCommentsBatch,
  StoredAnalysis,
} from "./photos";

const emulated =
  !!process.env.FIRESTORE_EMULATOR_HOST &&
  !!process.env.FIREBASE_STORAGE_EMULATOR_HOST;

const BUCKET = "demo-test.appspot.com";

const heron: Animal = {
  commonName: "Great Blue Heron",
  scientificName: "Ardea herodias",
  confidence: "high",
  description: "A tall grey-blue wading bird.",
};
const squirrel: Animal = {
  commonName: "Western Gray Squirrel",
  scientificName: "Sciurus griseus",
  confidence: "medium",
  description: "A large tree squirrel with a bushy tail.",
};

/** A model that sees [animals] in every photo, and counts its calls. */
function fakeModel(animals: Animal[]): Analyzer & { calls: number } {
  const look: Analyzer = async () => {
    model.calls++;
    return {
      analysis: {
        safety: { sexual: false, hate: false, violence: false, reason: "" },
        animals,
      },
      model: "fake",
      usage: { inputTokens: 1, outputTokens: 1, thinkingTokens: 0 },
    };
  };
  const model = Object.assign(look, { calls: 0 });
  return model;
}

const failingModel: Analyzer = async () => {
  throw new Error("model unavailable");
};

describe("posting AI comments", { skip: !emulated }, () => {
  const app = emulated
    ? initializeApp({ projectId: "demo-test", storageBucket: BUCKET })
    : undefined;
  const db = () => getFirestore(app!);

  /** A photo whose image is in the Storage emulator, as uploads are. */
  async function addPhoto(id: string, commentCount = 0): Promise<void> {
    const path = `photos/parks/${id}.jpg`;
    await getStorage(app!)
      .bucket(BUCKET)
      .file(path)
      .save(Buffer.from([0xff, 0xd8, 0xff, 0xd9]), {
        contentType: "image/jpeg",
      });
    await db()
      .collection("photos")
      .doc(id)
      .set({
        imageUrl:
          `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/` +
          `${encodeURIComponent(path)}?alt=media&token=t`,
        locationName: "Vasona Lake",
        category: "Parks",
        commentCount,
      });
  }

  const comments = (id: string) =>
    db().collection("comments").doc(id).collection("messages").get();

  /** A moderator deleting the AI's comment on [animal], as the app does. */
  async function deleteComment(id: string, animal: string): Promise<void> {
    const match = (await comments(id)).docs.find(
      (doc) => doc.data().animal?.commonName === animal,
    );
    await match!.ref.delete();
    await db()
      .collection("photos")
      .doc(id)
      .update({ commentCount: FieldValue.increment(-1) });
  }
  const photo = async (id: string) =>
    (await db().collection("photos").doc(id).get()).data()!;
  const analysis = async (id: string) =>
    (await db().collection("photoAnalysis").doc(id).get()).data() as
      | StoredAnalysis
      | undefined;

  before(async () => {
    process.env.GCLOUD_PROJECT = "demo-test";
  });

  beforeEach(async () => {
    await db().recursiveDelete(db().collection("photos"));
    await db().recursiveDelete(db().collection("comments"));
    await db().recursiveDelete(db().collection("photoAnalysis"));
  });

  after(async () => {
    if (app) await deleteApp(app);
  });

  it("posts one badged comment per animal and counts them", async () => {
    await addPhoto("p1", 2);
    const model = fakeModel([heron, squirrel]);

    const outcome = await postAnimalComments("p1", model);

    assert.deepEqual(outcome, {
      status: "posted",
      count: 2,
      names: ["Great Blue Heron", "Western Gray Squirrel"],
    });
    const posted = (await comments("p1")).docs.map((doc) => doc.data());
    assert.equal(posted.length, 2);
    for (const comment of posted) {
      assert.equal(comment.userId, "ai-naturalist");
      assert.equal(comment.userName, "AI Naturalist");
      assert.equal(comment.ai, true);
      assert.equal(comment.heartCount, 0);
    }
    assert.ok(
      posted.some((c) => c.text.startsWith("Great Blue Heron (Ardea herodias)")),
    );
    assert.equal((await photo("p1")).commentCount, 4);
    assert.equal((await analysis("p1"))?.animalComments?.count, 2);
  });

  it("never posts twice, even when asked twice at once", async () => {
    await addPhoto("p1");
    const model = fakeModel([heron]);

    const outcomes = await Promise.all([
      postAnimalComments("p1", model),
      postAnimalComments("p1", model),
    ]);
    const again = await postAnimalComments("p1", model);

    assert.deepEqual(
      outcomes.map((o) => o.status).sort(),
      ["alreadyPosted", "posted"],
    );
    assert.equal(again.status, "alreadyPosted");
    assert.equal((await comments("p1")).size, 1);
    assert.equal((await photo("p1")).commentCount, 1);
  });

  it("brings back a deleted comment from a fresh look", async () => {
    await addPhoto("p1");
    const model = fakeModel([heron, squirrel]);
    await postAnimalComments("p1", model);

    // Asked again with every comment there: nothing to do, nothing paid.
    const unchanged = await postAnimalComments("p1", model);
    assert.equal(unchanged.status, "alreadyPosted");
    assert.equal(model.calls, 1);

    await deleteComment("p1", "Great Blue Heron");
    const outcome = await postAnimalComments("p1", model);

    assert.deepEqual(outcome, {
      status: "posted",
      count: 1,
      names: ["Great Blue Heron"],
    });
    assert.equal(model.calls, 2);
    const names = (await comments("p1")).docs.map(
      (doc) => doc.data().animal.commonName,
    );
    assert.deepEqual(names.sort(), ["Great Blue Heron", "Western Gray Squirrel"]);
    assert.equal((await photo("p1")).commentCount, 2);
    assert.equal((await analysis("p1"))?.animalComments?.count, 2);
    assert.equal(
      (await postAnimalComments("p1", model)).status,
      "alreadyPosted",
    );
  });

  it("brings a deleted comment back only once when asked twice at once", async () => {
    await addPhoto("p1");
    const model = fakeModel([heron]);
    await postAnimalComments("p1", model);
    await deleteComment("p1", "Great Blue Heron");

    const outcomes = await Promise.all([
      postAnimalComments("p1", model),
      postAnimalComments("p1", model),
    ]);

    assert.deepEqual(
      outcomes.map((o) => o.status).sort(),
      ["alreadyPosted", "posted"],
    );
    assert.equal((await comments("p1")).size, 1);
    assert.equal((await photo("p1")).commentCount, 1);
  });

  it("says so when a fresh look finds nothing new", async () => {
    await addPhoto("p1");
    await postAnimalComments("p1", fakeModel([heron, squirrel]));
    await deleteComment("p1", "Western Gray Squirrel");

    const outcome = await postAnimalComments("p1", fakeModel([heron]));

    assert.deepEqual(outcome, {
      status: "alreadyPosted",
      count: 1,
      names: ["Great Blue Heron"],
    });
    assert.equal((await comments("p1")).size, 1);
    assert.equal((await analysis("p1"))?.animalComments?.count, 1);
  });

  it("looks again at a photo where it found no animals", async () => {
    await addPhoto("p1");
    await postAnimalComments("p1", fakeModel([]));

    const outcome = await postAnimalComments("p1", fakeModel([heron]));

    assert.equal(outcome.status, "posted");
    assert.equal((await comments("p1")).size, 1);
  });

  it("reuses the upload-time look instead of asking the model again", async () => {
    await addPhoto("p1");
    const model = fakeModel([heron]);
    await analyzePhoto("p1", await photo("p1"), model);

    await postAnimalComments("p1", model);

    assert.equal(model.calls, 1);
    assert.equal((await comments("p1")).size, 1);
  });

  it("records a photo with no animals as done, without comments", async () => {
    await addPhoto("p1");

    const outcome = await postAnimalComments("p1", fakeModel([]));

    assert.equal(outcome.status, "noAnimals");
    assert.equal((await comments("p1")).size, 0);
    assert.equal((await photo("p1")).commentCount, 0);
    assert.equal((await analysis("p1"))?.animalComments?.count, 0);
  });

  it("saves a failure and posts nothing", async () => {
    await addPhoto("p1");

    await assert.rejects(postAnimalComments("p1", failingModel), /unavailable/);

    assert.equal((await analysis("p1"))?.status, "failed");
    assert.equal((await comments("p1")).size, 0);
  });

  it("works through every photo in batches, skipping failures", async () => {
    for (const id of ["a", "b", "c", "d", "e"]) await addPhoto(id);
    await postAnimalComments("a", fakeModel([heron]));
    await assert.rejects(postAnimalComments("b", failingModel));
    const model = fakeModel([squirrel]);

    const first = await postAnimalCommentsBatch(2, model);
    const second = await postAnimalCommentsBatch(2, model);

    assert.deepEqual(first, {
      checked: 2,
      commentsAdded: 2,
      failed: 0,
      remaining: 1,
      failedTotal: 1,
    });
    assert.deepEqual(second, {
      checked: 1,
      commentsAdded: 1,
      failed: 0,
      remaining: 0,
      failedTotal: 1,
    });
    assert.equal((await comments("b")).size, 0);
    // The per-photo button retries a failed photo.
    assert.equal((await postAnimalComments("b", model)).status, "posted");
  });
});
