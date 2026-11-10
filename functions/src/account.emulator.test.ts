/**
 * Deleting an account, against the Auth, Firestore and Storage emulators.
 *
 *   npm run test:emulator
 *
 * Skipped by plain `npm test`, which runs without emulators.
 */
import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

import { deleteAccount, findAccount } from "./account";

const emulated =
  !!process.env.FIRESTORE_EMULATOR_HOST &&
  !!process.env.FIREBASE_STORAGE_EMULATOR_HOST &&
  !!process.env.FIREBASE_AUTH_EMULATOR_HOST;

const BUCKET = "demo-test.appspot.com";

describe("deleting an account", { skip: !emulated }, () => {
  const app = emulated
    ? initializeApp({ projectId: "demo-test", storageBucket: BUCKET })
    : undefined;
  const db = () => getFirestore(app!);
  const auth = () => getAuth(app!);
  const imagePath = "photos/parks/p1.jpg";
  const image = () => getStorage(app!).bucket(BUCKET).file(imagePath);

  const read = async (path: string) => (await db().doc(path).get()).data();
  const set = (path: string, data: Record<string, unknown>) =>
    db().doc(path).set(data);

  /**
   * Pat (u1), whose account is deleted, and Sam (u2), who stays: each has
   * a photo, comments, likes and a chat message, and they have reported
   * each other.
   */
  async function seed(): Promise<void> {
    await auth().createUser({
      uid: "u1",
      email: "pat@example.com",
      password: "emulator-only",
      displayName: "Pat",
    });
    await auth().createUser({ uid: "u2" });
    await image().save(Buffer.from([0xff, 0xd8, 0xff, 0xd9]), {
      contentType: "image/jpeg",
    });

    // Pat's photo, which Sam has liked and commented on.
    await set("photos/p1", {
      userId: "u1",
      imageUrl:
        `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/` +
        `${encodeURIComponent(imagePath)}?alt=media&token=t`,
      heartCount: 1,
      commentCount: 1,
    });
    await set("photos/p1/likes/u2", { userId: "u2" });
    await set("comments/p1/messages/c1", { userId: "u2", text: "Lovely" });
    await set("photoAnalysis/p1", { status: "done" });

    // Sam's photo, which both have liked and commented on.
    await set("photos/p2", { userId: "u2", heartCount: 2, commentCount: 2 });
    await set("photos/p2/likes/u1", { userId: "u1" });
    await set("photos/p2/likes/u2", { userId: "u2" });
    await set("comments/p2/messages/c2", { userId: "u1", text: "Nice" });
    await set("comments/p2/messages/c3", { userId: "u2", text: "Thanks" });

    // A like left behind on a photo deleted long ago.
    await set("photos/p9/likes/u1", { userId: "u1" });

    await set("chats/vasona_lake/messages/m1", { userId: "u1", text: "Hi" });
    await set("chats/vasona_lake/messages/m2", { userId: "u2", text: "Hey" });

    await set("reports/sentByPat", {
      reporterId: "u1",
      authorId: "u2",
      path: "comments/p2/messages/c3",
      status: "open",
    });
    await set("reports/aboutPat", {
      reporterId: "u2",
      authorId: "u1",
      path: "chats/vasona_lake/messages/m1",
      status: "open",
    });
    await set("reports/dismissed", {
      reporterId: "u2",
      authorId: "u1",
      path: "comments/p2/messages/c2",
      status: "dismissed",
    });

    await set("blockedContent/comments_p2_messages_c9", {
      kind: "comment",
      path: "comments/p2/messages/c9",
      authorId: "u1",
      status: "removed",
      data: { userId: "u1", text: "You idiot" },
    });
    await set("userSafety/u1", { blocked: {}, hidden: [] });
    await set("userSafety/u2", { blocked: { u1: { name: "Pat" } } });
    await set("bannedUsers/u1", { name: "Pat" });
    await set("users/u1/notices/n1", { kind: "comment", seen: false });
  }

  before(async () => {
    process.env.GCLOUD_PROJECT = "demo-test";
  });

  beforeEach(async () => {
    for (const name of [
      "photos",
      "comments",
      "chats",
      "photoAnalysis",
      "reports",
      "blockedContent",
      "userSafety",
      "bannedUsers",
      "users",
    ]) {
      await db().recursiveDelete(db().collection(name));
    }
    for (const uid of ["u1", "u2"]) {
      await auth().deleteUser(uid).catch(() => undefined);
    }
  });

  after(async () => {
    if (app) await deleteApp(app);
  });

  it("removes everything they put in, and the account", async () => {
    await seed();

    const deleted = await deleteAccount("u1");

    assert.deepEqual(deleted, {
      photos: 1,
      comments: 1,
      chatMessages: 1,
      likes: 2,
    });
    // Their photo, with its file, likes, thread and AI look.
    assert.equal(await read("photos/p1"), undefined);
    assert.equal(await read("photos/p1/likes/u2"), undefined);
    assert.equal(await read("comments/p1/messages/c1"), undefined);
    assert.equal(await read("photoAnalysis/p1"), undefined);
    assert.equal((await image().exists())[0], false);
    // Their comment, like and chat message, and their own records.
    assert.equal(await read("comments/p2/messages/c2"), undefined);
    assert.equal(await read("photos/p2/likes/u1"), undefined);
    assert.equal(await read("photos/p9/likes/u1"), undefined);
    assert.equal(await read("chats/vasona_lake/messages/m1"), undefined);
    assert.equal(await read("blockedContent/comments_p2_messages_c9"), undefined);
    assert.equal(await read("userSafety/u1"), undefined);
    assert.equal(await read("bannedUsers/u1"), undefined);
    assert.equal(await read("users/u1/notices/n1"), undefined);
    await assert.rejects(
      auth().getUser("u1"),
      (error: { code?: string }) => error.code === "auth/user-not-found",
    );
  });

  it("leaves everyone else's posts, with their counts corrected", async () => {
    await seed();

    await deleteAccount("u1");

    const photo = await read("photos/p2");
    assert.equal(photo?.heartCount, 1);
    assert.equal(photo?.commentCount, 1);
    assert.ok(await read("photos/p2/likes/u2"));
    assert.ok(await read("comments/p2/messages/c3"));
    assert.ok(await read("chats/vasona_lake/messages/m2"));
    assert.ok(await read("userSafety/u2"));
    // No photo is made up for the like left on a deleted one.
    assert.equal(await read("photos/p9"), undefined);
    assert.ok(await auth().getUser("u2"));
  });

  it("keeps their reports for the moderator without their name", async () => {
    await seed();

    await deleteAccount("u1");

    const sent = await read("reports/sentByPat");
    assert.equal(sent?.status, "open");
    assert.equal(sent?.reporterId, undefined);
    assert.equal((await read("reports/aboutPat"))?.status, "accountDeleted");
    assert.equal((await read("reports/dismissed"))?.status, "dismissed");
  });

  it("can be run again after a failure partway", async () => {
    await seed();
    await deleteAccount("u1");

    assert.deepEqual(await deleteAccount("u1"), {
      photos: 0,
      comments: 0,
      chatMessages: 0,
      likes: 0,
    });
  });

  it("finds an account by its email, with what is in it", async () => {
    await seed();

    const pat = await findAccount("pat@example.com");

    assert.equal(pat?.uid, "u1");
    assert.equal(pat?.name, "Pat");
    assert.deepEqual(pat?.signInWith, ["password"]);
    assert.ok(pat?.createdAt);
    // A photo; a comment and a chat message; two likes, one of them left
    // on a photo deleted long ago.
    assert.equal(pat?.photos, 1);
    assert.equal(pat?.messages, 2);
    assert.equal(pat?.likes, 2);
  });

  it("finds nothing for an address no account uses", async () => {
    await seed();
    assert.equal(await findAccount("nobody@example.com"), null);
  });
});
