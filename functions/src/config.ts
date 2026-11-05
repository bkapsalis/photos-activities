/**
 * Settings for the AI photo checks. Changing the model is this one line,
 * then `firebase deploy --only functions`.
 *
 * Gemini 3.5 Flash-Lite first; the bake-off against Claude Haiku 5.5 (also
 * sold through Vertex AI) comes once real photos have been through it.
 */
export const MODEL = "gemini-3.5-flash-lite";

/** Where Vertex AI runs the model. Gemini 3.5 is served from "global". */
export const VERTEX_LOCATION = "global";

/**
 * Where the functions run: next to the Firestore database (us-west1), so a
 * trigger does not cross regions to reach it.
 */
export const REGION = "us-west1";

/**
 * Moderators. Mirrors firestore.rules, storage.rules and
 * lib/core/utils/permissions.dart; keep all four lists in sync.
 */
export const ADMIN_EMAILS = ["bkapsalis@gmail.com"];

/** Whether a caller's ID token is a moderator's: a verified listed email. */
export function isModerator(
  token: { email?: string; email_verified?: boolean } | undefined,
): boolean {
  const email = String(token?.email ?? "").toLowerCase();
  return token?.email_verified === true && ADMIN_EMAILS.includes(email);
}

/**
 * The author on every AI comment. No Firebase account has this uid, so no
 * person can post as it; the app badges comments carrying it.
 */
export const AI_AUTHOR = {
  userId: "ai-naturalist",
  userName: "AI Naturalist",
  userInitials: "AI",
  // AppColors.ai: a teal no person's avatar is given
  // (UserProfile._colorForUid), as the ARGB int the app stores.
  userAvatarColor: 0xff00897b,
} as const;

/**
 * Vertex AI takes images inline up to 7 MB. Uploads are compressed to
 * 1600px and are far smaller; the rare one kept at full size is skipped.
 */
export const MAX_INLINE_IMAGE_BYTES = 7 * 1024 * 1024;
