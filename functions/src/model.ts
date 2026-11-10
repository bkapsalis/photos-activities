import {
  FinishReason,
  GenerateContentResponse,
  GoogleGenAI,
  ThinkingLevel,
} from "@google/genai";

import {
  buildPrompt,
  buildTextPrompt,
  parseAnalysis,
  parseTextVerdict,
  PhotoAnalysis,
  PhotoContext,
  RESPONSE_SCHEMA,
  TEXT_RESPONSE_SCHEMA,
  TextVerdict,
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

export interface TextCheckResult {
  verdict: TextVerdict;
  model: string;
  usage: Usage;
}

/** Checks one comment or chat message; a parameter, like [Analyzer]. */
export type TextChecker = (text: string) => Promise<TextCheckResult>;

// Answers Vertex AI gives instead of a description when its own filters stop
// an image or a text. Either is treated as flagged rather than as an error.
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

  const usage = usageOf(response);
  const refusal = refusalOf(response);
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

/** [MODEL] on Vertex AI, checking one comment or chat message. */
export const checkTextWithGemini: TextChecker = async (text) => {
  const response = await genai().models.generateContent({
    model: MODEL,
    contents: [{ role: "user", parts: [{ text: buildTextPrompt(text) }] }],
    config: {
      responseMimeType: "application/json",
      responseSchema: TEXT_RESPONSE_SCHEMA,
      thinkingConfig: { thinkingLevel: ThinkingLevel.MINIMAL },
    },
  });

  const usage = usageOf(response);
  const refusal = refusalOf(response);
  if (refusal) {
    return {
      verdict: {
        sexual: false,
        hate: false,
        violence: false,
        harassment: false,
        refused: true,
        reason: `The model would not read it (${refusal}).`,
      },
      model: MODEL,
      usage,
    };
  }

  return { verdict: parseTextVerdict(response.text), model: MODEL, usage };
};

function usageOf(response: GenerateContentResponse): Usage {
  return {
    inputTokens: response.usageMetadata?.promptTokenCount ?? 0,
    outputTokens: response.usageMetadata?.candidatesTokenCount ?? 0,
    thinkingTokens: response.usageMetadata?.thoughtsTokenCount ?? 0,
  };
}

/** Why Vertex AI's own filters stopped the request, if they did. */
function refusalOf(response: GenerateContentResponse): string | undefined {
  return (
    response.promptFeedback?.blockReason ??
    [response.candidates?.[0]?.finishReason].find(
      (reason) => reason && REFUSALS.has(reason),
    )
  );
}
