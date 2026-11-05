// Google Gemini over plain REST (no SDK, so the credential never leaves this server and there is nothing to bundle).
// Docs: POST /v1beta/models/{model}:generateContent with generationConfig.responseMimeType + responseSchema.
import type { LlmClient, LlmRequest } from './llm.ts';

export interface GeminiConfig {
  apiKey: string;
  model: string;
  baseUrl?: string;
  fetchFn?: typeof fetch;
}

export class GeminiClient implements LlmClient {
  private cfg: Required<Omit<GeminiConfig, 'fetchFn'>> & { fetchFn: typeof fetch };

  constructor(cfg: GeminiConfig) {
    this.cfg = { baseUrl: 'https://generativelanguage.googleapis.com', fetchFn: cfg.fetchFn ?? fetch, apiKey: cfg.apiKey, model: cfg.model };
    if (cfg.baseUrl) this.cfg.baseUrl = cfg.baseUrl;
  }

  async json(req: LlmRequest): Promise<unknown> {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), req.timeoutMs);
    try {
      const res = await this.cfg.fetchFn(`${this.cfg.baseUrl}/v1beta/models/${encodeURIComponent(this.cfg.model)}:generateContent`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-goog-api-key': this.cfg.apiKey },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: req.system }] },
          contents: [...(req.history ?? []).map((h) => ({ role: h.role, parts: [{ text: h.text }] })), { role: 'user', parts: [{ text: req.prompt }] }],
          generationConfig: {
            responseMimeType: 'application/json', responseSchema: req.schema,
            temperature: req.temperature ?? 1.0, maxOutputTokens: 4096,
          },
        }),
        signal: ctrl.signal,
      });
      // Never include the response body or the URL in errors: they can contain the key or user-derived text.
      if (!res.ok) throw new Error(`gemini_http_${res.status}`);
      const data = (await res.json()) as { candidates?: { content?: { parts?: { text?: string }[] } }[] };
      const text = data.candidates?.[0]?.content?.parts?.map((p) => p.text ?? '').join('') ?? '';
      if (!text.trim()) throw new Error('gemini_empty');
      return JSON.parse(text.replace(/^```(?:json)?|```$/gim, '').trim());
    } finally {
      clearTimeout(timer);
    }
  }
}
