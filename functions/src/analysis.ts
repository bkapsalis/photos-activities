import { Schema, Type } from "@google/genai";

/**
 * One look at a photo answers two questions at once, so each upload costs a
 * single model call: is it safe to show, and which animals are in it.
 */
export interface PhotoAnalysis {
  safety: SafetyVerdict;
  animals: Animal[];
}

/**
 * Recorded for every upload. Nothing acts on it yet: blocking comes with the
 * moderation switch, before uploads open to everyone.
 */
export interface SafetyVerdict {
  /** Nudity or sexual content. */
  sexual: boolean;
  /** Hate symbols, or signs and gestures attacking a group of people. */
  hate: boolean;
  /** Graphic violence, gore or serious injury. */
  violence: boolean;
  /**
   * Vertex AI's own filters stopped the image before the model could judge
   * it. Rare, and suspicious enough to count as flagged.
   */
  refused?: boolean;
  /** What was seen, when anything is flagged; otherwise empty. */
  reason: string;
}

export type Confidence = "high" | "medium" | "low";

export interface Animal {
  commonName: string;
  scientificName: string;
  confidence: Confidence;
  description: string;
}

/** Where the photo was taken, which narrows down the likely species. */
export interface PhotoContext {
  locationName?: string;
  locationRegion?: string;
  category?: string;
}

// A photo with more kinds of animal than this is a crowd scene; the rest
// would bury the thread.
const MAX_ANIMALS = 8;
// Well inside the 2000-character comment limit in firestore.rules, with
// room for the name line.
const MAX_DESCRIPTION = 1200;
const MAX_NAME = 100;
const MAX_REASON = 300;

/** The JSON shape the model must answer in (Vertex AI controlled output). */
export const RESPONSE_SCHEMA: Schema = {
  type: Type.OBJECT,
  properties: {
    safety: {
      type: Type.OBJECT,
      properties: {
        sexual: { type: Type.BOOLEAN },
        hate: { type: Type.BOOLEAN },
        violence: { type: Type.BOOLEAN },
        reason: { type: Type.STRING },
      },
      required: ["sexual", "hate", "violence", "reason"],
      propertyOrdering: ["sexual", "hate", "violence", "reason"],
    },
    animals: {
      type: Type.ARRAY,
      items: {
        type: Type.OBJECT,
        properties: {
          commonName: { type: Type.STRING },
          scientificName: { type: Type.STRING },
          confidence: {
            type: Type.STRING,
            format: "enum",
            enum: ["high", "medium", "low"],
          },
          description: { type: Type.STRING },
        },
        required: ["commonName", "scientificName", "confidence", "description"],
        propertyOrdering: [
          "commonName",
          "scientificName",
          "confidence",
          "description",
        ],
      },
    },
  },
  required: ["safety", "animals"],
  propertyOrdering: ["safety", "animals"],
};

/** The instructions sent with the photo. */
export function buildPrompt(context: PhotoContext): string {
  const place = [context.locationName, context.locationRegion]
    .map((part) => part?.trim())
    .filter((part) => part)
    .join(", ");
  const where = place
    ? `It was taken at ${place}, in the San Francisco Bay Area, California.`
    : "It was taken in the San Francisco Bay Area, California.";
  const category = context.category?.trim()
    ? ` The app files it under "${context.category.trim()}".`
    : "";

  return `You check photos for a photo-sharing app about fun places to visit in the San Francisco Bay Area. ${where}${category}

Answer two questions about the photo.

1. "safety": is it safe to show to everyone?
- "sexual": true if it shows nudity or sexual content. Swimwear, breastfeeding and classical art are not sexual.
- "hate": true if it shows a hate symbol (such as a swastika), or a sign, writing or gesture attacking people for their race, religion, ethnicity, nationality, sex, sexual orientation, gender identity or disability.
- "violence": true if it shows graphic violence, gore, serious injury or a dead person. Animals hunting or eating in nature are not violence.
- "reason": when anything is true, a few words on what you saw; otherwise "".

2. "animals": every kind of real, living animal you can see: birds, mammals, reptiles, amphibians, fish, insects, spiders and others, wild or domestic. Leave out people, and statues, drawings, toys, signs or pictures of animals. List each kind once, however many of it there are. If there are none, return an empty list.
- "commonName": its usual English name, such as "Anna's Hummingbird". For a pet or farm animal, the breed if it is clear, such as "Golden Retriever"; otherwise, such as "Domestic Dog".
- "scientificName": the species, such as "Calypte anna". If you cannot tell the species, give the genus followed by "sp.", such as "Larus sp.", and use a general common name, such as "Gull".
- "confidence": "high", "medium" or "low": how sure you are of the identification.
- "description": 3 or 4 plain sentences for a curious visitor: how to recognise it, what it eats or does, and where it lives, including in the Bay Area when that is relevant. Only facts you are sure of. Describe the kind of animal, not this photo.`;
}

/** Thrown when the model's answer is not the JSON that was asked for. */
export class BadModelAnswer extends Error {}

/**
 * Checks and tidies the model's JSON answer. Throws [BadModelAnswer] when it
 * is not the requested shape, so nothing half-read is ever posted.
 */
export function parseAnalysis(text: string | undefined): PhotoAnalysis {
  let raw: unknown;
  try {
    raw = JSON.parse(text ?? "");
  } catch {
    throw new BadModelAnswer("The answer was not JSON.");
  }
  if (!isObject(raw) || !isObject(raw.safety) || !Array.isArray(raw.animals)) {
    throw new BadModelAnswer("The answer is missing safety or animals.");
  }

  const s = raw.safety;
  if (
    typeof s.sexual !== "boolean" ||
    typeof s.hate !== "boolean" ||
    typeof s.violence !== "boolean"
  ) {
    throw new BadModelAnswer("The safety answer is not three yes/no values.");
  }
  const safety: SafetyVerdict = {
    sexual: s.sexual,
    hate: s.hate,
    violence: s.violence,
    reason: clip(typeof s.reason === "string" ? s.reason : "", MAX_REASON),
  };

  const animals: Animal[] = [];
  const seen = new Set<string>();
  for (const item of raw.animals) {
    if (!isObject(item)) continue;
    const commonName = clip(stringOf(item.commonName), MAX_NAME);
    const scientificName = clip(stringOf(item.scientificName), MAX_NAME);
    const description = clip(stringOf(item.description), MAX_DESCRIPTION);
    // An animal without a name or a description is of no use as a comment.
    if (!commonName || !description) continue;
    // "List each kind once" is a request, not a guarantee.
    const key = (scientificName || commonName).toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    animals.push({
      commonName,
      scientificName,
      confidence: confidenceOf(item.confidence),
      description,
    });
    if (animals.length === MAX_ANIMALS) break;
  }

  return { safety, animals };
}

/** Whether anything in the verdict would get the photo blocked. */
export function isFlagged(safety: SafetyVerdict): boolean {
  return (
    safety.sexual || safety.hate || safety.violence || safety.refused === true
  );
}

/**
 * The comment text for one animal. It reads complete on its own: an app
 * version from before AI comments shows only this.
 */
export function animalCommentText(animal: Animal): string {
  const name =
    animal.confidence === "low"
      ? `Possibly ${animal.commonName}`
      : animal.commonName;
  const scientific = animal.scientificName ? ` (${animal.scientificName})` : "";
  return `${name}${scientific}\n\n${animal.description}`;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringOf(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function confidenceOf(value: unknown): Confidence {
  return value === "high" || value === "medium" ? value : "low";
}

function clip(text: string, max: number): string {
  const trimmed = text.trim();
  return trimmed.length <= max ? trimmed : `${trimmed.slice(0, max - 1)}…`;
}
