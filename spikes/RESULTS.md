# Spike results

## Spike 1: key timing and speech (Flutter web)
- Date: 2026-11-19
- Prompts needed to get it working: 1
- Short taps: 66 to 122 ms, typically about 100 ms
- Spread of short taps: 55 ms (34 ms excluding one fast tap)
- Gaps between taps: 214 to 314 ms
- Long holds: 1,274 ms and 2,611 ms, each counted as one press
- Key repeat ignored: yes (88 repeat events ignored)
- Speech in Chrome: yes
- Speech in second browser (Edge): yes
- Verdict: Flutter web is OK for Sounder

## Spike 2: requirements to property tests
- Did design.md list correctness properties? yes, 13, each linked to a requirement ID
- Dart property-testing package: kiri_check 1.4.0 (glados rejected: last release Dec 2023)
- Sabotage (E changed to ..): 5 tests failed, including the round-trip property (Falsifying example: E, seed 2003)
- Finding: the unique-codes property missed it (sampled 200 of 903 pairs); fixed with a bugfix spec and re-verified
- Verdict: Kiro drives Dart property tests directly

## Spike 3: expansion model (2026-11-27)
Playground: Gemma 4 26B and GLM-4.7 Flash looped in reasoning and gave no answer.
Script (spikes/expand_spike, real Workers AI calls, 6 tests, temperature 0.2):
- Llama 3.3 70B fp8-fast: hits 2/6, valid 23/24, median 1710 ms
- Llama 4 Scout 17B: hits 5/6, valid 22/24, median 2813 ms
Decision: Llama 4 Scout. Its miss (P C M D -> "Please Call My Doctor") is a reasonable sentence.
Consequences: the validator must discard invalid candidates (3 of 48 failed); latency target set from measurement, not the plan's 1.5 s.