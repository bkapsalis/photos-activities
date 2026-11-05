/**
 * The content filter, against the Firestore and Storage emulators with a
 * stand-in model, so no AI call is made or paid for.
 *
 *   npm run test:emulator
 *
 * Skipped by plain `npm test`, which runs without emulators.
 */
import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { DocumentData, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

import { SafetyVerdict, TextVerdict } from "./analysis";
import { TextChecker } from "./model";
import {
  checkPost,
  discardPost,
  ModerationProblem,
  Notice,
  removedKey,
  removeFlaggedPhoto,
  RemovedPost,
  restorePost,
} from "./moderation";

const emulated =
  !!process.env.FIRESTORE_EMULATOR_HOST &&
  !!process.env.FIREBASE_STORAGE_EMULATOR_HOST;

const BUCKET = "demo-test.appspot.com";

const hateful: SafetyVerdict = {
  sexual: false,
  hate: true,
  violence: false,
  reason: "A swastika on a sign.",
};

/** A model that flags every message or none, and counts its calls. */
function fakeChecker(flag: boolean): TextChecker & { calls: number } {
  const verdict: TextVerdict = {
    sexual: false,
    hate: false,
    violence: false,
    harassment: flag,
    reason: flag ? "Insults a person." : "",
  };
  const check: TextChecker = async () => {
    checker.calls++;
    return {
      verdict,
      model: "fake",
      usage: { inputTokens: 1, outputTokens: 1, thinkingTokens: 0 },
    };
  };
  const checker = Object.assign(check, { calls: 0 });
  return checker;
}

describe("the content filter", { skip: !emulated }, () => {
  const app = emulated
    ? initializeApp({ projectId: "demo-test", storageBucket: BUCKET })
    : undefined;
  const db = () => getFirestore(app!);
  const imagePath = "photos/parks/p1.jpg";
  const image = () => getStorage(app!).bucket(BUCKET).file(imagePath);

  const setFilter = (on: boolean) =>
    db().doc("config/app").set({ contentFilter: on });

  async function addPhoto(commentCount = 0): Promise<DocumentData> {
    await image().save(Buffer.from([0xff, 0xd8, 0xff, 0xd9]), {
      contentType: "image/jpeg",
    });
    const photo = {
      imageUrl:
        `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/` +
        `${encodeURIComponent(imagePath)}?alt=media&token=t`,
      locationName: "Vasona Lake",
      userId: "u1",
      userName: "Pat",
      commentCount,
    };
    await db().doc("photos/p1").set(photo);
    await db().doc("photoAnalysis/p1").set({ status: "done", flagged: true });
    return photo;
  }

  async function addComment(text: string): Promise<DocumentData> {
    const comment = { userId: "u2", userName: "Sam", text };
    await db().doc("comments/p1/messages/c1").set(comment);
    await db()
      .doc("photos/p1")
      .update({ commentCount: 1 });
    return comment;
  }

  const read = async (path: string) => (await db().doc(path).get()).data();
  const removed = async (path: string) =>
    (await read(`blockedContent/${removedKey(path)}`)) as
      | RemovedPost
      | undefined;
  const notice = async (userId: string, path: string) =>
    (await read(`users/${userId}/notices/${removedKey(path)}`)) as
      | Notice
      | undefined;

  before(async () => {
    process.env.GCLOUD_PROJECT = "demo-test";
  });

  beforeEach(async () => {
    for (const name of [
      "photos",
      "comments",
      "chats",
      "photoAnalysis",
      "blockedContent",
      "users",
      "config",
    ]) {
      await db().recursiveDelete(db().collection(name));
    }
  });

  after(async () => {
    if (app) await deleteApp(app);
  });

  describe("photos", () => {
    it("leaves a flagged photo up while the filter is off", async () => {
      await addPhoto();

      assert.equal(await removeFlaggedPhoto("p1", hateful), false);
      assert.ok(await read("photos/p1"));
    });

    it("takes a flagged photo down, keeps a copy and tells its owner", async () => {
      await setFilter(true);
      const photo = await addPhoto();

      assert.equal(await removeFlaggedPhoto("p1", hateful), true);

      assert.equal(await read("photos/p1"), undefined);
      const record = await removed("photos/p1");
      assert.equal(record?.status, "removed");
      assert.equal(record?.kind, "photo");
      assert.deepEqual(record?.data, photo);
      assert.deepEqual(record?.flaggedFor, ["Hate"]);
      assert.equal(record?.reason, "A swastika on a sign.");
      const told = await notice("u1", "photos/p1");
      assert.equal(told?.restored, false);
      assert.equal(told?.seen, false);
      assert.equal(told?.preview, "Vasona Lake");
      // Kept for the moderator; the image file too, to put it back.
      assert.ok(await read("photoAnalysis/p1"));
      assert.equal((await image().exists())[0], true);
    });

    it("puts a photo back as it was, and tells its owner", async () => {
      await setFilter(true);
      const photo = await addPhoto();
      await removeFlaggedPhoto("p1", hateful);

      await restorePost(removedKey("photos/p1"));

      assert.deepEqual(await read("photos/p1"), photo);
      assert.equal((await removed("photos/p1"))?.status, "restored");
      assert.equal((await read("photoAnalysis/p1"))?.moderatorCleared, true);
      assert.equal((await notice("u1", "photos/p1"))?.restored, true);
      await assert.rejects(
        restorePost(removedKey("photos/p1")),
        (error) => error instanceof ModerationProblem,
      );
    });

    it("deletes a photo for good, image file and all", async () => {
      await setFilter(true);
      await addPhoto();
      await removeFlaggedPhoto("p1", hateful);

      await discardPost(removedKey("photos/p1"));

      assert.equal(await removed("photos/p1"), undefined);
      assert.equal(await read("photoAnalysis/p1"), undefined);
      assert.equal((await image().exists())[0], false);
    });
  });

  describe("comments and chat messages", () => {
    const commentRef = () => db().doc("comments/p1/messages/c1");

    it("checks nothing while the filter is off", async () => {
      await addPhoto();
      const comment = await addComment("You idiot");
      const checker = fakeChecker(true);

      const outcome = await checkPost(
        "comment",
        commentRef(),
        undefined,
        comment,
        checker,
      );

      assert.equal(outcome, "skipped");
      assert.equal(checker.calls, 0);
    });

    it("takes a flagged comment down and uncounts it", async () => {
      await setFilter(true);
      await addPhoto();
      const comment = await addComment("You idiot");

      const outcome = await checkPost(
        "comment",
        commentRef(),
        undefined,
        comment,
        fakeChecker(true),
      );

      assert.equal(outcome, "removed");
      assert.equal(await read("comments/p1/messages/c1"), undefined);
      assert.equal((await read("photos/p1"))?.commentCount, 0);
      const path = "comments/p1/messages/c1";
      assert.deepEqual((await removed(path))?.flaggedFor, ["Harassment"]);
      assert.equal((await notice("u2", path))?.preview, "You idiot");
    });

    it("keeps a fine comment, and skips writes that leave the words alone", async () => {
      await setFilter(true);
      await addPhoto();
      const comment = await addComment("Lovely spot");
      const checker = fakeChecker(false);

      assert.equal(
        await checkPost("comment", commentRef(), undefined, comment, checker),
        "kept",
      );
      assert.equal(
        await checkPost(
          "comment",
          commentRef(),
          comment,
          { ...comment, userName: "Sam Lee" },
          checker,
        ),
        "skipped",
      );
      assert.equal(
        await checkPost("comment", commentRef(), comment, undefined, checker),
        "skipped",
      );
      assert.equal(checker.calls, 1);
    });

    it("checks an edit that changes the words", async () => {
      await setFilter(true);
      await addPhoto();
      const comment = await addComment("Lovely spot");

      const outcome = await checkPost(
        "comment",
        commentRef(),
        comment,
        { ...comment, text: "You idiot" },
        fakeChecker(true),
      );

      assert.equal(outcome, "removed");
    });

    it("never checks the AI's own comments", async () => {
      await setFilter(true);
      const checker = fakeChecker(true);

      const outcome = await checkPost(
        "comment",
        commentRef(),
        undefined,
        { userId: "ai-naturalist", text: "Great Blue Heron" },
        checker,
      );

      assert.equal(outcome, "skipped");
      assert.equal(checker.calls, 0);
    });

    it("puts a comment back, counts it, and does not check it again", async () => {
      await setFilter(true);
      await addPhoto();
      const comment = await addComment("You idiot");
      await checkPost("comment", commentRef(), undefined, comment, fakeChecker(true));

      await restorePost(removedKey("comments/p1/messages/c1"));

      assert.deepEqual(await read("comments/p1/messages/c1"), comment);
      assert.equal((await read("photos/p1"))?.commentCount, 1);
      const checker = fakeChecker(true);
      assert.equal(
        await checkPost("comment", commentRef(), undefined, comment, checker),
        "skipped",
      );
      assert.equal(checker.calls, 0);
    });

    it("cannot put a comment back on a photo that is gone", async () => {
      await setFilter(true);
      await addPhoto();
      const comment = await addComment("You idiot");
      await checkPost("comment", commentRef(), undefined, comment, fakeChecker(true));
      await db().doc("photos/p1").delete();

      await assert.rejects(
        restorePost(removedKey("comments/p1/messages/c1")),
        (error) =>
          error instanceof ModerationProblem && error.kind === "notFound",
      );
    });

    it("takes a flagged chat message down", async () => {
      await setFilter(true);
      const ref = db().doc("chats/vasona_lake/messages/m1");
      const message = { userId: "u3", userName: "Lee", text: "You idiot" };
      await ref.set(message);

      const outcome = await checkPost(
        "chat",
        ref,
        undefined,
        message,
        fakeChecker(true),
      );

      assert.equal(outcome, "removed");
      assert.equal(await read(ref.path), undefined);
      assert.equal((await removed(ref.path))?.kind, "chat");
      assert.ok(await notice("u3", ref.path));
    });
  });
});
