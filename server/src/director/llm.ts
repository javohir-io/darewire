// The Director talks to any model through this tiny interface, so tests can inject a fake and the provider can change.
export interface LlmRequest {
  system: string;
  prompt: string;
  /** JSON schema (Gemini OpenAPI-subset) the response must follow. */
  schema: Record<string, unknown>;
  timeoutMs: number;
  /** Earlier turns of a conversation (oldest first). The final user turn is `prompt`. */
  history?: { role: 'user' | 'model'; text: string }[];
  temperature?: number;
}
export interface LlmClient { json(req: LlmRequest): Promise<unknown> }
