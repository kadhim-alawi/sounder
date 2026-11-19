---
inclusion: always
---

# Structure: Sounder

## Folders
- `.kiro/` specs, steering, hooks, agents, MCP settings, evidence. Never git-ignored.
- `app/` the Flutter app.
  - `lib/input/` keyboard, touch and switch adapters that emit timestamped press and release events.
  - `lib/compose/` composer (Shorthand and Spell modes, undo, press counting), phrase index, expansion client.
  - `lib/speech/` speech output and its on-screen fallback.
  - `lib/store/` on-device storage.
  - `lib/ui/` screens: key, phrases, learn, calibrate, settings. One widget file per component.
- `packages/morse_core/` the pure Dart engine and its tests.
- `functions/expand/` the serverless function: handler, prompt, schema, tests.
- `power/` our Kiro power: `plugin.json`, `skills/`, `mcp.json`.
- `eval/` benchmark phrase set, runner, results.
- `docs/` architecture, user journey, testing, deployment.

## Naming
- Dart files: `snake_case.dart`. Classes: `UpperCamelCase`.
- One public class per file in `morse_core`.
- Spec folders under `.kiro/specs/` use kebab-case: `morse-core`, `adaptive-timing`.

## Rules
- New code goes in the folder above that owns it. Do not create new top-level folders without updating this file.
- Root files: `README.md`, `LICENSE` (MIT, unmodified), `KIRO.md`, `THIRD_PARTY.md`, `.env.example`.
- `.gitignore` must never list `.kiro`.