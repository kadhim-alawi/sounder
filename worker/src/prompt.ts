/**
 * The Model settings and the System_Prompt for `POST /expand` (REQ-EXPAND-8).
 *
 * Adapted from spike 3. Pure: no I/O, clock or logging (REQ-LOG-3).
 */

/** Workers AI model used for expansion (REQ-EXPAND-8, C2). */
export const MODEL_ID = "@cf/meta/llama-4-scout-17b-16e-instruct";

/** Sampling temperature sent with every Model call (REQ-EXPAND-8). */
export const TEMPERATURE = 0.2;

/** Reply length cap sent with every Model call (REQ-EXPAND-8). */
export const MAX_TOKENS = 200;

/** The system message sent to the Model (REQ-EXPAND-8). */
export const SYSTEM_PROMPT =
  'You expand word starts into short spoken sentences for a person who cannot speak. The input is a list of items separated by spaces. Each item is the start of one word (one or more letters), in order. Return exactly 4 different candidate sentences as JSON, and nothing else: {"candidates":["...","...","...","..."]} Every candidate must have exactly one word per item, and each word must start with the letters of its item. Use everyday, first-person language a person would say to a carer or friend.';

/** One chat message passed to the Model (REQ-EXPAND-8). */
export interface ChatMessage {
  role: "system" | "user";
  content: string;
}

/**
 * Builds the Model messages for [tokens] (REQ-EXPAND-8): the System_Prompt as
 * the system message, then the Tokens joined by single spaces as the user
 * message.
 */
export function buildMessages(tokens: string[]): ChatMessage[] {
  return [
    { role: "system", content: SYSTEM_PROMPT },
    { role: "user", content: tokens.join(" ") },
  ];
}
