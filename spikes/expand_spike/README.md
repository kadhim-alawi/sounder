# expand_spike (throwaway)

Compares two Workers AI models at expanding initials into sentences:
`@cf/meta/llama-3.3-70b-instruct-fp8-fast` and `@cf/meta/llama-4-scout-17b-16e-instruct`.
`GET /run` calls each model on six test phrases, one call at a time, and returns a plain-text
summary table followed by the full details.

JSON Mode (`response_format`) is on for llama-3.3 only, because the
[JSON Mode docs](https://developers.cloudflare.com/workers-ai/features/json-mode/) list it as supported
and do not list llama-4-scout.

Not part of the Sounder build. No secrets live in this folder; Wrangler uses your own Cloudflare login.

## Run

```powershell
cd spikes/expand_spike
npm install
npx wrangler login        # once, opens a browser
npx wrangler types        # regenerates worker-configuration.d.ts
npx tsc --noEmit          # optional typecheck
npx wrangler dev --port 8799
```

In a second terminal:

```powershell
curl.exe http://127.0.0.1:8799/run
```

Workers AI calls always go to Cloudflare, even under `wrangler dev`, so each run uses your account's
Workers AI allowance (12 small calls).
