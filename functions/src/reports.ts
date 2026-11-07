import { getFirestore, Timestamp } from "firebase-admin/firestore";

/**
 * How long a report is kept once the moderator has closed it, as the
 * privacy policy and the account-deletion page promise (web/privacy.html,
 * web/delete-account.html). Open reports stay until the moderator gets to
 * them.
 */
export const REPORT_RETENTION_DAYS = 365;

/** Reports closed before this moment have been kept long enough. */
export function retentionCutoff(now: Date): Date {
  return new Date(now.getTime() - REPORT_RETENTION_DAYS * 24 * 60 * 60 * 1000);
}

// A batch holds at most 500 writes.
const CHUNK = 500;

/** Deletes every report closed before [cutoff], and says how many. */
export async function deleteReportsClosedBefore(cutoff: Date): Promise<number> {
  const db = getFirestore();
  // Only a closed report has settledAt: the app sets it when the moderator
  // deletes the post or dismisses the report, and deleting an account sets
  // it on the open reports about that account.
  const old = await db
    .collection("reports")
    .where("settledAt", "<", Timestamp.fromDate(cutoff))
    .get();
  for (let i = 0; i < old.size; i += CHUNK) {
    const batch = db.batch();
    for (const doc of old.docs.slice(i, i + CHUNK)) batch.delete(doc.ref);
    await batch.commit();
  }
  return old.size;
}
