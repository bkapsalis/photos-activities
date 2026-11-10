/**
 * Deleting old reports, against the Firestore emulator.
 *
 *   npm run test:emulator
 *
 * Skipped by plain `npm test`, which runs without emulators.
 */
import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

import { deleteReportsClosedBefore, retentionCutoff } from "./reports";

const emulated = !!process.env.FIRESTORE_EMULATOR_HOST;

describe("deleting old reports", { skip: !emulated }, () => {
  const app = emulated ? initializeApp({ projectId: "demo-test" }) : undefined;
  const db = () => getFirestore(app!);

  const now = new Date("2027-11-06T12:00:00Z");
  const daysAgo = (days: number) =>
    Timestamp.fromMillis(now.getTime() - days * 24 * 60 * 60 * 1000);

  before(async () => {
    process.env.GCLOUD_PROJECT = "demo-test";
  });

  beforeEach(async () => {
    await db().recursiveDelete(db().collection("reports"));
  });

  after(async () => {
    if (app) await deleteApp(app);
  });

  it("deletes reports closed over a year ago, and nothing else", async () => {
    const reports = db().collection("reports");
    await reports.doc("waiting").set({ status: "open" });
    await reports.doc("waitingLong").set({ status: "open" });
    await reports.doc("dismissedOld").set({
      status: "dismissed",
      settledAt: daysAgo(400),
    });
    await reports.doc("deletedOld").set({
      status: "deleted",
      settledAt: daysAgo(366),
    });
    await reports.doc("accountGoneOld").set({
      status: "accountDeleted",
      settledAt: daysAgo(500),
    });
    await reports.doc("dismissedRecently").set({
      status: "dismissed",
      settledAt: daysAgo(364),
    });

    assert.equal(await deleteReportsClosedBefore(retentionCutoff(now)), 3);

    const left = (await reports.get()).docs.map((doc) => doc.id).sort();
    assert.deepEqual(left, ["dismissedRecently", "waiting", "waitingLong"]);
  });
});
