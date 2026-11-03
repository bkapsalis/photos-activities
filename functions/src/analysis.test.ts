import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  animalCommentText,
  BadModelAnswer,
  buildPrompt,
  isFlagged,
  parseAnalysis,
} from "./analysis";
import { storageLocation } from "./photos";

const safe = { sexual: false, hate: false, violence: false, reason: "" };

const hummingbird = {
  commonName: "Anna's Hummingbird",
  scientificName: "Calypte anna",
  confidence: "high",
  description: "A small hummingbird with a rose-pink throat.",
};

describe("parseAnalysis", () => {
  it("reads a well-formed answer", () => {
    const result = parseAnalysis(
      JSON.stringify({ safety: safe, animals: [hummingbird] }),
    );
    assert.deepEqual(result, { safety: safe, animals: [hummingbird] });
  });

  it("rejects an answer that is not JSON or is missing a part", () => {
    assert.throws(() => parseAnalysis("Sorry, I can't help."), BadModelAnswer);
    assert.throws(() => parseAnalysis(undefined), BadModelAnswer);
    assert.throws(
      () => parseAnalysis(JSON.stringify({ animals: [] })),
      BadModelAnswer,
    );
    assert.throws(
      () =>
        parseAnalysis(
          JSON.stringify({ safety: { ...safe, sexual: "no" }, animals: [] }),
        ),
      BadModelAnswer,
    );
  });

  it("drops animals without a name or description, and repeats", () => {
    const result = parseAnalysis(
      JSON.stringify({
        safety: safe,
        animals: [
          hummingbird,
          { ...hummingbird, commonName: "Anna's hummingbird" },
          { ...hummingbird, scientificName: "Sciurus griseus", commonName: "" },
          { ...hummingbird, scientificName: "Ardea alba", description: " " },
          "a deer",
        ],
      }),
    );
    assert.deepEqual(
      result.animals.map((animal) => animal.commonName),
      ["Anna's Hummingbird"],
    );
  });

  it("caps the list and the length of what it keeps", () => {
    const many = Array.from({ length: 12 }, (_, i) => ({
      ...hummingbird,
      scientificName: `Species ${i}`,
      description: "x".repeat(5000),
    }));
    const result = parseAnalysis(JSON.stringify({ safety: safe, animals: many }));
    assert.equal(result.animals.length, 8);
    assert.equal(result.animals[0].description.length, 1200);
  });

  it("treats an unknown confidence as low", () => {
    const result = parseAnalysis(
      JSON.stringify({
        safety: safe,
        animals: [{ ...hummingbird, confidence: "certain" }],
      }),
    );
    assert.equal(result.animals[0].confidence, "low");
  });
});

describe("isFlagged", () => {
  it("is false for a safe photo and true for any concern", () => {
    assert.equal(isFlagged(safe), false);
    assert.equal(isFlagged({ ...safe, hate: true }), true);
    assert.equal(isFlagged({ ...safe, refused: true }), true);
  });
});

describe("animalCommentText", () => {
  it("names the animal, then describes it", () => {
    assert.equal(
      animalCommentText({ ...hummingbird, confidence: "high" }),
      "Anna's Hummingbird (Calypte anna)\n\n" +
        "A small hummingbird with a rose-pink throat.",
    );
  });

  it("hedges a low-confidence identification", () => {
    assert.match(
      animalCommentText({ ...hummingbird, confidence: "low" }),
      /^Possibly Anna's Hummingbird \(Calypte anna\)/,
    );
  });
});

describe("buildPrompt", () => {
  it("says where the photo was taken", () => {
    const prompt = buildPrompt({
      locationName: "Vasona Lake",
      locationRegion: "Los Gatos",
      category: "Parks",
    });
    assert.match(prompt, /taken at Vasona Lake, Los Gatos, in the San Francisco/);
    assert.match(prompt, /files it under "Parks"/);
  });

  it("copes with no location", () => {
    assert.match(buildPrompt({}), /taken in the San Francisco Bay Area/);
  });
});

describe("storageLocation", () => {
  it("reads the bucket and path from a download URL", () => {
    assert.deepEqual(
      storageLocation(
        "https://firebasestorage.googleapis.com/v0/b/photos-activities-dev." +
          "firebasestorage.app/o/photos%2Fhiking-areas%2F1791815870807_2.jpg" +
          "?alt=media&token=abc",
      ),
      {
        bucket: "photos-activities-dev.firebasestorage.app",
        path: "photos/hiking-areas/1791815870807_2.jpg",
      },
    );
  });

  it("is null for anything else", () => {
    assert.equal(storageLocation("https://example.com/a.jpg"), null);
    assert.equal(storageLocation("not a url"), null);
    assert.equal(storageLocation(""), null);
  });
});
