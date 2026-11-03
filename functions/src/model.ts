import { FinishReason, GoogleGenAI, ThinkingLevel } from "@google/genai";

import {
  buildPrompt,
  parseAnalysis,
  PhotoAnalysis,
  PhotoContext,
  RESPONSE_SCHEMA,
} from "./analysis";
import { MODEL, VERTEX_LOCATION } from "./config";

export interface ImageData {
  bytes: Buffer;
  mimeType: string;
}

/** Tokens billed for one call, kept with the result to compare models. */
export interface Usage {
  inputTokens: number;
  outputTokens: number;
  thinkingTokens: number;
}

export interface ModelResult {
  analysis: PhotoAnalysis;
  model: string;
  usage: Usage;
}

/** Looks at one photo. A parameter so tests can stand in for the model. */
export type Analyzer = (
  image: ImageData,
  context: PhotoContext,
) => Promise<ModelResult>;

// Answers Vertex AI gives instead of a description when its own filters stop
// an image. Such an image is treated as flagged rather than as an error.
const REFUSALS = new Set<string>([
  FinishReason.SAFETY,
  FinishReason.PROHIBITED_CONTENT,
  FinishReason.BLOCKLIST,
  FinishReason.SPII,
  FinishReason.IMAGE_SAFETY,
  FinishReason.IMAGE_PROHIBITED_CONTENT,
]);

let client: GoogleGenAI | undefined;

// Made on first use, not when the file loads: deploying loads this file on a
// machine with no Google Cloud credentials.
function genai(): GoogleGenAI {
  client ??= new GoogleGenAI({
    vertexai: true,
    project: process.env.GCLOUD_PROJECT,
    location: VERTEX_LOCATION,
  });
  return client;
}

/** [MODEL] on Vertex AI, billed to this Firebase project's Google account. */
export const analyzeWithGemini: Analyzer = async (image, context) => {
  const response = await genai().models.generateContent({
    model: MODEL,
    contents: [
      {
        role: "user",
        parts: [
          {
            inlineData: {
              mimeType: image.mimeType,
              data: image.bytes.toString("base64"),
            },
          },
          { text: buildPrompt(context) },
        ],
      },
    ],
    config: {
      responseMimeType: "application/json",
      responseSchema: RESPONSE_SCHEMA,
      // Thinking is billed as output; naming and screening need little of it.
      thinkingConfig: { thinkingLevel: ThinkingLevel.MINIMAL },
    },
  });

  const usage: Usage = {
    inputTokens: response.usageMetadata?.promptTokenCount ?? 0,
    outputTokens: response.usageMetadata?.candidatesTokenCount ?? 0,
    thinkingTokens: response.usageMetadata?.thoughtsTokenCount ?? 0,
  };

  const refusal =
    response.promptFeedback?.blockReason ??
    [response.candidates?.[0]?.finishReason].find(
      (reason) => reason && REFUSALS.has(reason),
    );
  if (refusal) {
    return {
      analysis: {
        safety: {
          sexual: false,
          hate: false,
          violence: false,
          refused: true,
          reason: `The model would not look at it (${refusal}).`,
        },
        animals: [],
      },
      model: MODEL,
      usage,
    };
  }

  return { analysis: parseAnalysis(response.text), model: MODEL, usage };
};
