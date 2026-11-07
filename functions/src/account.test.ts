import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  deletionRefusal,
  moderatorDeletionRefusal,
  RECENT_SIGN_IN_SECONDS,
} from "./account";

const now = 1_800_000_000;

function token(
  provider: string,
  signedInSecondsAgo: number,
  email = "pat@example.com",
) {
  return {
    auth_time: now - signedInSecondsAgo,
    firebase: { sign_in_provider: provider, identities: {} },
    email,
    email_verified: true,
  };
}

describe("deletionRefusal", () => {
  it("lets someone who just signed in again delete their account", () => {
    assert.equal(deletionRefusal(token("google.com", 30), now), null);
    assert.equal(deletionRefusal(token("apple.com", 30), now), null);
    assert.equal(deletionRefusal(token("password", 30), now), null);
  });

  it("asks for a fresh sign-in once the last one is old", () => {
    const refusal = deletionRefusal(
      token("google.com", RECENT_SIGN_IN_SECONDS + 1),
      now,
    );
    assert.match(refusal ?? "", /sign in again/);
  });

  it("lets a guest delete at any time, having nothing to sign in with", () => {
    assert.equal(deletionRefusal(token("anonymous", 86_400, ""), now), null);
  });

  it("keeps the moderator's account, and its photos", () => {
    const refusal = deletionRefusal(
      token("google.com", 30, "BKapsalis@gmail.com"),
      now,
    );
    assert.match(refusal ?? "", /moderator/);
  });

  it("does not take an unverified moderator email for the moderator", () => {
    const unverified = {
      ...token("password", 30, "bkapsalis@gmail.com"),
      email_verified: false,
    };
    assert.equal(deletionRefusal(unverified, now), null);
  });
});

describe("moderatorDeletionRefusal", () => {
  it("lets a moderator delete anyone else's account", () => {
    const user = { email: "pat@example.com", emailVerified: true };
    assert.equal(moderatorDeletionRefusal(user), null);
  });

  it("keeps the moderator's own account, and its photos", () => {
    const user = { email: "BKapsalis@gmail.com", emailVerified: true };
    assert.match(moderatorDeletionRefusal(user) ?? "", /moderator/);
  });

  it("does not take an unverified moderator email for the moderator", () => {
    const user = { email: "bkapsalis@gmail.com", emailVerified: false };
    assert.equal(moderatorDeletionRefusal(user), null);
  });
});
