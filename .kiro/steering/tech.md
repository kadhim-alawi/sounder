---
inclusion: always
---

# Tech: Sounder

## Stack
- Client: Flutter, web build only for the hackathon. Riverpod for state.
- Engine: `packages/morse_core`, a pure Dart package. It must never import Flutter.
- Backend: one stateless serverless function, `functions/expand`, hosted on Netlify Functions.
- Speech: the platform's own text-to-speech through a Flutter plugin.
- Storage: on-device key-value storage only. No database, no accounts.
- Use the dart MCP server (configured in .kiro/settings/mcp.json) to look up packages on pub.dev, check APIs, and run the analyzer and tests. Never guess an API or a package version.
- Before using dart MCP tools, make sure both app/ and packages/morse_core are registered as roots with the dart MCP server (use its roots tool). If a dart MCP tool still cannot be used, run the command in the shell and say so, as you did in key-screen task 1.

## Layering rules
- `morse_core` handles the code table, encoding, decoding, timing and calibration. Pure functions, no I/O.
- UI code never classifies timing or decodes Morse. It calls `morse_core`.
- The function holds the model API key, validates input, rate limits, and stores nothing.
- The app validates every model candidate locally. Each word must start with the typed initial, in order.

## Banned shortcuts
- No hardcoded or canned model output in the hosted build. Mocks only in tests, named as mocks.
- No secrets in code, chat or commits. Keys live in host environment variables only.
- No absolute time constants in the decoder. All durations are relative to the calibrated unit.
- No logging of what the user typed or said.

## Testing
- Every requirement has an ID such as `REQ-TIMING-3`. Tests and doc comments cite it.
- Engine invariants are property-based tests in `packages/morse_core/test/`.
- Run engine tests: `cd packages/morse_core && dart test`
- Run app tests: `cd app && flutter test`
- A task is done only when its cited tests pass.

## Performance budgets
- Press to on-screen feedback: under 50 ms.
- Expansion: median under 1.5 s; time out at 2.5 s and fall back to saved phrases.
- First load on broadband: under 4 s.