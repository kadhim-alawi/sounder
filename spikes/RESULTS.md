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