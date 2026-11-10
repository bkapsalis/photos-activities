import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { REPORT_RETENTION_DAYS, retentionCutoff } from "./reports";

describe("retentionCutoff", () => {
  it("is a year before now", () => {
    assert.equal(REPORT_RETENTION_DAYS, 365);
    assert.equal(
      retentionCutoff(new Date("2027-11-06T12:00:00Z")).toISOString(),
      "2026-11-06T12:00:00.000Z",
    );
  });
});
