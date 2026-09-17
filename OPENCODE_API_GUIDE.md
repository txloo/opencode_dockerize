# Calling the OpenCode Zen API (mimicking an opencode session)

How to craft a chat-completions request to OpenCode Zen so the gateway treats it
like a real opencode CLI session — required for correct routing, prompt caching,
and streaming.

## Endpoint

```
POST https://opencode.ai/zen/v1/chat/completions
```

- Configurable via `OPENCODE_BASE_URL` (default: the zen URL above).
- OpenAI-compatible wire format (`@ai-sdk/openai-compatible`).

## Headers (required)

| Header                  | Value                                                              | Why                                                                 |
| ----------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------- |
| `Content-Type`          | `application/json`                                                 | standard                                                             |
| `Authorization`         | `Bearer <OPENCODE_API_KEY>`                                        | auth                                                                 |
| `Accept`                | `text/event-stream`                                                | ask for SSE (needed for streaming responses)                        |
| `x-opencode-client`     | `cli`                                                              | client identity — the gateway routes CLI-style calls                |
| `x-opencode-session`    | **stable per conversation**, `_ses_<26-char id>` e.g. `ses_561eca5ebffeCngoybZWxbTrD8` | same format the CLI sends; pins consecutive requests to the same backend for prompt-caching |
| `x-opencode-request`    | **fresh per request**, `msg_<26-char id>`                          | unique request/message id                                           |
| `x-opencode-project`    | `proj_<26-char id>` (stable per conversation)                      | project namespace                                                    |
| `User-Agent`            | `opencode/1.18.30`                                                 | must look like the current CLI                                      |

ID format (matches the real opencode CLI — `packages/schema/src/identifier.ts`):
`<prefix>_` + 12 hex chars (descending timestamp+counter) + 14 chars drawn from
base62 `0-9A-Za-z`. Generate them with `openCodeId("ses" | "msg" | "proj")` from
`src/lib/opencode-ids.ts`; `isOpenCodeId(value, prefix)` validates a value.

Implementation notes:
- The generator is a port of opencode's `Identifier.create(descending=true)`.
  The tsconfig targets ES2017, so **do not use BigInt literal suffixes**
  (`0x1000n`, `0xffn`) — write `BigInt(0x1000)`, `BigInt(0xff)` instead
  (TS2737 otherwise).
- The voice pod keeps its own copy of the generator in `services/voice/llm.ts`
  because the pod is standalone and must not import from `src/lib/`.
- `POST /api/playground` accepts client-supplied `sessionId`/`projectId`,
  validates each with `isOpenCodeId`, and falls back to freshly generated ids
  when a value is missing or malformed.

Notes:
- `x-opencode-session` must be **stable across all turns of one conversation**
  but **unique per conversation**. The typed playground holds one `ses_`/`proj_`
  pair per conversation (`PlaygroundChat`), and the voice pod generates a fresh
  pair per `Start→Stop` session.
- `x-opencode-request` must be **fresh on every request** (it is the message id).
- Do not send the legacy `ses_callmeai-…` / `msg_<32 hex>` / `global` values —
  they are not what the CLI sends.

## Body

```jsonc
{
  "model": "big-pickle",
  "messages": [
    { "role": "system", "content": "<system prompt, optional>" },
    { "role": "assistant", "content": "<greeting/assistant turns, gathered from history>" },
    { "role": "user", "content": "<latest user turn>" }
  ],
  "stream": true
}
```

- `stream: true` is what makes it stream tokens instead of waiting for the whole
  response.
- Supported models in this codebase map to opencode only for `big-pickle`
  (see `OPENCODE_CHAT_MODELS` in `src/lib/llm/opencode.ts` and
  `services/voice/llm.ts`).

## Streaming response (SSE)

The response body is a server-sent event stream of JSON lines:

```
data: {"choices":[{"delta":{"content":"Hel"}}]}

data: {"choices":[{"delta":{"content":"lo"}}]}

data: [DONE]
```

- Parse lines; only `data:` lines matter.
- Concatenate `choices[0].delta.content` for the running reply.
- Stop at `data: [DONE]`.
- Tolerate chunks with no content (e.g. usage-only frames, empty `choices`).

## Verifying with curl

Run from the same machine/network as the app so any Cloudflare/WAF block is
reproduced the same way. The ids below are real-shaped but arbitrary:

```bash
curl -sS -N https://opencode.ai/zen/v1/chat/completions \
  -H "Authorization: Bearer $OPENCODE_API_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -H "User-Agent: opencode/1.18.30" \
  -H "x-opencode-client: cli" \
  -H "x-opencode-session: ses_561eca5ebffeCngoybZWxbTrD8" \
  -H "x-opencode-request: msg_a9e135a170018Ui4RfAZfIDlfl" \
  -H "x-opencode-project: proj_533cded24ffeEg9nWRBZHMGN7c" \
  -d '{"model":"big-pickle","messages":[{"role":"user","content":"Say hi in one short sentence."}],"stream":true}'
```

Reading the result:
- SSE `data: {"choices":[...]}` stream → impersonation works.
- JSON error envelope (`{"type":"error","error":{"type":"RegionError"...}}`) →
  gateway-level block (country/model/entitlement), not a header problem.
- HTML / `cf-ray` / `1010` → Cloudflare edge/WAF block from the network,
  unrelated to the CLI headers.
- To isolate streaming, drop `Accept: text/event-stream` and send `"stream":false`.

## Reference implementation (already wired up)

| File                                      | Role                                    |
| ----------------------------------------- | --------------------------------------- |
| `services/voice/llm.ts`                   | `OpenCodeLlmClient` (voice pod) + `readSseBody` SSE parser; duplicates the id generator (pod is standalone) |
| `services/voice/voice-pod.ts`             | generates one `ses_`/`proj_` pair per pod session and passes both into `llm.chat` |
| `src/lib/llm/opencode.ts`                 | `OpenCodeProviderClient` (typed playground `POST /api/playground`) |
| `src/lib/opencode-ids.ts`                 | `openCodeId` / `isOpenCodeId` / `OPENCODE_CLI_VERSION` (id + UA source of truth app-side) |
| `src/lib/llm/index.ts` (`runChat`)        | provider dispatch; forwards `sessionId` + `projectId` |
| `src/app/api/playground/route.ts`         | threads client-provided conversation ids (validated) or falls back to fresh ones |
| `src/components/playground/playground-chat.tsx` | holds one `ses_`/`proj_` pair per conversation |

## Environment variables

- `OPENCODE_API_KEY` — required for live calls; without it the stub is used.
- `OPENCODE_BASE_URL` — optional override of the zen endpoint.

## Reference request (copy-safe skeleton)

```ts
const sessionId = openCodeId("ses"); // stable per conversation
const requestId = openCodeId("msg"); // fresh per request
const projectId = openCodeId("proj"); // stable per conversation

const response = await fetch(baseUrl, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    Authorization: `Bearer ${apiKey}`,
    Accept: "text/event-stream",
    "x-opencode-client": "cli",
    "x-opencode-session": sessionId,
    "x-opencode-request": requestId,
    "x-opencode-project": projectId,
    "User-Agent": `opencode/${OPENCODE_CLI_VERSION}`, // "1.18.30"
  },
  body: JSON.stringify({ model, messages, stream: true }),
});
// then read the SSE body as described above
```