# Implementation Plan: key-screen

## Overview

The Key_Screen is built in Dart and Flutter in the order its layers depend on each other: dependencies first, then the pure Dart compose layer (`Composer`, `sentence_text.dart`, `KeySession`), then the input adapters and the speech service, then the Riverpod controller, the widgets and `KeyScreen` itself, and last the CI step. A screen that keys `E` and speaks it exists at the end of task 5.5.

Conventions for every task:

- New code goes in the folder that owns it: `app/lib/input/`, `app/lib/compose/`, `app/lib/speech/`, `app/lib/ui/`. One widget per file in `lib/ui/`. File names are `snake_case.dart`.
- Every public declaration in `app/lib/` has a `///` comment citing at least one requirement ID.
- Every test description begins with the requirement ID or IDs it covers, followed by a colon (REQ-CI-2), for example `'REQ-COMPOSE-3: undo on an empty Sentence raises nothing'`.
- Speech mocks live only under `app/test/` and their class names begin with `Mock` (REQ-CI-3).
- Nothing in `app/lib/` prints or logs the Sentence, the Partial_Sequence or the Speak_Text.
- Widget tests use `tester.pump`, never `pumpAndSettle`, because the Frame_Ticker schedules a frame every vsync (design D4).
- A task is done only when its cited tests pass with `cd app && flutter test`, and `cd packages/morse_core && dart test` still passes.

## Tasks

- [ ] 1. Fix the app dependencies
  - In `app/pubspec.yaml`, move `morse_core: path: ../packages/morse_core` from `dev_dependencies` to `dependencies` (K6)
  - Add `flutter_riverpod: ^3.5.0` and `flutter_tts: ^4.2.5` to `dependencies`, and `kiri_check: ^1.4.0` to `dev_dependencies` (design D11, R5, R6, R7)
  - Run `cd app && flutter pub get` and confirm it resolves; leave `main.dart` unchanged for now
  - _Requirements: REQ-KEY-6, REQ-SPEAK-1, REQ-COMPOSE-6_

- [ ] 2. Implement the pure Dart compose layer
  - [ ] 2.1 Implement `Composer`
    - `app/lib/compose/composer.dart`: `sentence` (unmodifiable view), `append`, `undo` (no-op when empty), `clear`; no other mutator
    - Imports only `package:morse_core/morse_core.dart`; no Flutter, `dart:ui`, `dart:html`, `dart:io`, `dart:js_interop`, clock, timer or I/O
    - _Requirements: REQ-COMPOSE-1, REQ-COMPOSE-2, REQ-COMPOSE-3, REQ-COMPOSE-4, REQ-COMPOSE-5_
  - [ ] 2.2 Write unit tests for `Composer` (REQ-CI-2a, required)
    - `app/test/composer_test.dart`: REQ-COMPOSE-2 append keeps order and leaves earlier items unchanged; REQ-COMPOSE-3 Undo removes only the last item, including Undo on an empty Sentence raising nothing; REQ-COMPOSE-4 Clear, including Clear on an empty Sentence; REQ-COMPOSE-5 the Sentence changes only through append, undo and clear (the returned list is unmodifiable)
    - _Requirements: REQ-COMPOSE-2, REQ-COMPOSE-3, REQ-COMPOSE-4, REQ-COMPOSE-5, REQ-CI-2_
  - [ ] 2.3 Write the item generators and the append-undo property test (REQ-CI-2b, required)
    - `app/test/support/item_arbitraries.dart`: `decodedItem()` as a `frequency` of Letter_Items from the code-table characters, Unknown_Letter_Items built from the fixed unknown prefix `........` plus random symbols (no filter), and Word_Spaces; `itemList(maxLength:)`
    - Create `app/test/compose_properties_test.dart` with seed `(200 + N) * 1000 + 3`, `maxExamples: 200`, and the tag comment `// Feature: key-screen, Property 1: append then undo round trip`
    - **Property 1: Append then undo round trip** (lengths 0 to 200, k derived by modulo, no filter)
    - **Validates: Requirements 3.6, 3.3** (REQ-COMPOSE-6, REQ-COMPOSE-3)
  - [ ]* 2.4 Write property test for Composer against a list model
    - Add to `compose_properties_test.dart`; 0 to 300 operations of append, undo and clear; no operation throws
    - **Property 2: Composer matches a list model**
    - **Validates: Requirements 3.2, 3.3, 3.4** (REQ-COMPOSE-2, REQ-COMPOSE-3, REQ-COMPOSE-4)
  - [ ] 2.5 Implement the display and speak text functions
    - `app/lib/compose/sentence_text.dart`: `placeholder = '\u25A1'`; `sentenceText(items)` (letter → its character, unknown → Placeholder, Word_Space → one space); `speakText(items)` (Placeholders removed, space runs collapsed, trimmed); `partialGlyphs(s)` (`.` → `·` U+00B7, `-` → `–` U+2013)
    - Pure Dart under the same import rules as 2.1
    - _Requirements: REQ-KEY-10, REQ-KEY-11, REQ-SPEAK-1, REQ-SPEAK-2, REQ-COMPOSE-1_
  - [ ]* 2.6 Write unit tests for the text functions
    - `app/test/sentence_text_test.dart`: the `HI□ THERE` example; `speakText` of only Placeholders and Word_Spaces is empty; REQ-KEY-10 glyphs including the empty Partial_Sequence
    - _Requirements: REQ-KEY-10, REQ-KEY-11, REQ-SPEAK-1, REQ-SPEAK-2_
  - [ ]* 2.7 Write property test for item-by-item display text
    - Add to `compose_properties_test.dart`; also a generator of 0 to 20 `.`/`-` characters
    - **Property 3: Display text maps item by item**
    - **Validates: Requirements 2.3, 2.2** (REQ-KEY-11, REQ-KEY-10)
  - [ ]* 2.8 Write property test for Speak_Text
    - Add to `compose_properties_test.dart`; oracle splits at Word_Spaces, keeps Letter_Item characters, drops empty parts, joins with one space
    - **Property 4: Speak_Text is the letters, words separated by single spaces**
    - **Validates: Requirements 4.1, 4.2** (REQ-SPEAK-1, REQ-SPEAK-2)
  - [ ] 2.9 Implement `KeySession`
    - `app/lib/compose/key_session.dart`: default Calibration (Dit_Length 100,000, Dah_Length 300,000, Symbol_Gap 250,000, Letter_Gap 700,000) as named constants with a REQ-KEY-6 comment, `TimingConfig.defaults`; `KeySession.withDecoder` for tests
    - Every call clamps `t' = max(t, decoder.latestTimestamp ?? t)`; catches only `TimingInputException`, returns false and changes nothing; after each accepted call forwards `decoder.items.sublist(_forwarded)` to the Composer and updates `_forwarded`
    - `undo` and `clear` touch only the Composer; getters `sentence`, `partialSequence`, `isPressed`
    - _Requirements: REQ-KEY-4, REQ-KEY-6, REQ-KEY-7, REQ-COMPOSE-1, REQ-COMPOSE-2, REQ-COMPOSE-3, REQ-COMPOSE-4_
  - [ ]* 2.10 Write unit tests for `KeySession`
    - `app/test/key_session_test.dart`: REQ-KEY-6 default Calibration values; press at 0, release at 100,000, `advanceTo(800,000)` gives `E`; a second press while held returns false and changes nothing (REQ-KEY-7)
    - _Requirements: REQ-KEY-6, REQ-KEY-7_
  - [ ]* 2.11 Write property test for KeySession
    - Add a `sessionCall()` generator to `item_arbitraries.dart` (`oneOf` press, release, advanceTo with `integer(0, 20000000)`, undo, clear); add the property to `compose_properties_test.dart`
    - **Property 5: KeySession clamps, discards errors and forwards each item once**
    - **Validates: Requirements 1.4, 1.7, 3.2, 3.3, 3.4** (REQ-KEY-4, REQ-KEY-7, REQ-COMPOSE-2, REQ-COMPOSE-3, REQ-COMPOSE-4)

- [ ] 3. Checkpoint - Ensure all tests pass
  - Run `cd app && flutter test` and `cd packages/morse_core && dart test`.
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 4. Implement the input adapters and the speech service
  - [ ] 4.1 Implement `TimeBase` and `PlatformTimeBase`
    - `app/lib/input/time_base.dart`: `TimeBase.stamp(Duration)`; `PlatformTimeBase` returns `d.inMicroseconds` (design R1, D1, D3)
    - _Requirements: REQ-KEY-4_
  - [ ] 4.2 Implement `KeyAction` and `keyActionFor`
    - `app/lib/input/keyboard_adapter.dart`: the design's table for Space, Enter (including `numpadEnter`), Escape and other keys across `KeyDownEvent`, `KeyUpEvent` and `KeyRepeatEvent`; no state
    - _Requirements: REQ-KEY-1, REQ-KEY-2, REQ-SPEAK-4_
  - [ ]* 4.3 Write unit tests for `keyActionFor`
    - `app/test/keyboard_adapter_test.dart`: every table cell, numpad Enter, and an unrelated key returning `ignore`
    - _Requirements: REQ-KEY-1, REQ-KEY-2, REQ-SPEAK-4_
  - [ ] 4.4 Implement `PointerAdapter`
    - `app/lib/input/pointer_adapter.dart`: `down(pointer)` always returns true and tracks the pointer when none is tracked; `end(pointer)` returns true only for the tracked pointer and clears it
    - _Requirements: REQ-KEY-3, REQ-KEY-7_
  - [ ]* 4.5 Write property test for PointerAdapter
    - Add to `compose_properties_test.dart`; 0 to 100 down, up or cancel events with ids 0 to 3, compared with a one-variable model
    - **Property 6: Only the pressing pointer releases**
    - **Validates: Requirements 1.3, 1.7** (REQ-KEY-3, REQ-KEY-7)
  - [ ] 4.6 Implement `SpeechService` and `FlutterTtsSpeechService`
    - `app/lib/speech/speech_service.dart`: `SpeechResult { completed, failed, superseded }` and the `SpeechService` interface (`init`, `speak`)
    - `app/lib/speech/flutter_tts_speech_service.dart`: `init` warms `getVoices`; `speak` returns `failed` for an empty or null voice list or a throw; while busy it supersedes the previous call, stores one pending text and calls `stop()` (D7); handlers treat `interrupted` and `canceled` like cancel and any other error code as `failed` (D6); no `awaitSpeakCompletion`; never stores the text beyond the pending slot and never logs it
    - _Requirements: REQ-SPEAK-1, REQ-SPEAK-2, REQ-SPEAK-3, REQ-CI-3_
  - [ ] 4.7 Add the test clock and the speech mock
    - `app/test/support/manual_time_base.dart`: `ManualTimeBase implements TimeBase` with a settable `now` that `stamp` returns, ignoring its argument (D3)
    - `app/test/support/mock_speech_service.dart`: `MockSpeechService implements SpeechService` recording every `speak` text and returning a settable `SpeechResult`
    - _Requirements: REQ-CI-2, REQ-CI-3_

- [ ] 5. Build the Key_Screen UI and its widget tests
  - [ ] 5.1 Implement the palette
    - `app/lib/ui/sounder_colors.dart`: white text, `#121212` screen and Fallback_View, `#1E1E1E` released key and buttons, `#0D47A1` pressed key
    - _Requirements: REQ-A11Y-3_
  - [ ]* 5.2 Write unit tests for the palette contrast
    - `app/test/colors_test.dart`: WCAG 2.x relative luminance of each background ≤ 0.2 and contrast with white ≥ 7:1, computed from the constants
    - _Requirements: REQ-A11Y-3_
  - [ ] 5.3 Implement `KeyScreenState` and `KeyScreenController`
    - `app/lib/ui/key_screen_state.dart`: immutable `sentence` (unmodifiable), `partialSequence`, `isPressed`, `fallbackVisible`
    - `app/lib/ui/key_screen_controller.dart`: `timeBaseProvider`, `speechServiceProvider`, `keyScreenControllerProvider` (`NotifierProvider`); `press`, `release`, `frame` stamp through the `TimeBase` and call `KeySession`; `frame` publishes only when `partialSequence`, `sentence` length or `isPressed` changed
    - `speak()`: empty `speakText` makes no call; otherwise one `speechService.speak` call; `failed` shows, `completed` hides, `superseded` leaves the Fallback_View; `undo`, `clear`, `closeFallback` (no-op when hidden); none of these change the Sentence except `undo` and `clear`
    - _Requirements: REQ-KEY-4, REQ-KEY-5, REQ-KEY-7, REQ-KEY-8, REQ-KEY-12, REQ-COMPOSE-2, REQ-COMPOSE-3, REQ-COMPOSE-4, REQ-COMPOSE-5, REQ-SPEAK-1, REQ-SPEAK-2, REQ-SPEAK-3, REQ-SPEAK-4, REQ-SPEAK-5_
  - [ ] 5.4 Implement the Key_Screen widgets and the Fallback_View
    - `app/lib/ui/on_screen_key.dart`: `Semantics(button: true, label: 'Morse key', value: 'pressed'/'released')` → `Listener` (down, up, cancel through `PointerAdapter`) → `DecoratedBox`, at least 160 px high, full width, "Pressed"/"Released" text and a 4 px versus 1 px border; no `InkWell`
    - `app/lib/ui/sentence_display.dart` and `app/lib/ui/partial_display.dart`: 36 px, wrapping, no `maxLines` or `overflow`, semantics label and value with an empty-field label
    - `app/lib/ui/action_bar.dart`: `Wrap` of Speak, Undo and Clear `FilledButton`s, `minimumSize: Size(64, 64)`, `NoSplash`, transparent overlay, `animationDuration: Duration.zero` (D9)
    - `app/lib/speech/fallback_view.dart`: full-screen Sentence text at 36 px, "Speech failed" notice, labelled Close button at least 64 by 64
    - _Requirements: REQ-KEY-3, REQ-KEY-8, REQ-KEY-9, REQ-KEY-10, REQ-KEY-11, REQ-KEY-12, REQ-SPEAK-3, REQ-A11Y-1, REQ-A11Y-2, REQ-A11Y-3, REQ-A11Y-4, REQ-A11Y-5_
  - [ ] 5.5 Implement `KeyScreen` and wire it into `main.dart`
    - `app/lib/ui/key_screen.dart`: `ConsumerStatefulWidget` with `SingleTickerProviderStateMixin`; root `Focus(autofocus: true, onKeyEvent:)` mapping `keyActionFor` to controller calls with `event.timeStamp` and returning `handled` for everything except `ignore`; a `Ticker` calling `controller.frame(SchedulerBinding.instance.currentSystemFrameTimeStamp)`; `Stack` of a vertical `SingleChildScrollView` (Sentence, Partial_Sequence, On_Screen_Key, ActionBar, 16 px horizontal padding) and the Fallback_View; `initState` calls `speechServiceProvider` `init()` once
    - Rewrite `app/lib/main.dart` as `ProviderScope(child: MaterialApp(home: KeyScreen()))`
    - _Requirements: REQ-KEY-1, REQ-KEY-2, REQ-KEY-4, REQ-KEY-5, REQ-KEY-6, REQ-KEY-12, REQ-SPEAK-4, REQ-SPEAK-5, REQ-A11Y-4_
  - [ ] 5.6 Write the dit-to-E widget test (REQ-CI-2c, required)
    - Create `app/test/key_screen_test.dart` with a pump helper that overrides `timeBaseProvider` with `ManualTimeBase` and `speechServiceProvider` with `MockSpeechService`, and `frameTo(us)` advancing the clock in 16,667 µs steps with one `tester.pump` each
    - Space key-down at T, key-up at T + 100,000, frames until T + 900,000: Sentence text is exactly `E`
    - Also REQ-KEY-5: Sentence empty at the last frame below release + 475,000 and `E` at the first frame at or above it
    - _Requirements: REQ-CI-2, REQ-KEY-1, REQ-KEY-4, REQ-KEY-5_
  - [ ] 5.7 Write the single speech call widget test (REQ-CI-2d, required)
    - Key `HI`, then Enter: the mock has exactly one call with text `HI`, and the Sentence is unchanged
    - _Requirements: REQ-CI-2, REQ-SPEAK-1, REQ-COMPOSE-5_
  - [ ] 5.8 Write the Escape-closes-fallback widget test (REQ-CI-2e, required)
    - Mock returns `failed`; Speak shows the Fallback_View; focus its Close button; Escape key-down hides it; Sentence unchanged; mock still has one call
    - _Requirements: REQ-CI-2, REQ-SPEAK-3, REQ-SPEAK-4, REQ-COMPOSE-5_
  - [ ] 5.9 Write the successful-speak-closes-fallback widget test (REQ-CI-2f, required)
    - Mock returns `failed`, Fallback_View shown; set the mock to `completed`; focus the Close button; Enter key-down: the mock has a second call, the Fallback_View is hidden, the Sentence is unchanged
    - _Requirements: REQ-CI-2, REQ-SPEAK-5, REQ-COMPOSE-5_
  - [ ]* 5.10 Write the remaining Key_Screen widget tests
    - Add to `key_screen_test.dart`, one test per row of the design's widget-test table not covered by 5.6 to 5.9: REQ-KEY-1 (Space with Undo focused makes a press, Undo not activated), REQ-KEY-2 (repeat events for Space, Enter, Escape), REQ-KEY-3 (gesture moved off the key then up releases), REQ-KEY-7 and REQ-KEY-8 (Space then pointer down, one press, "Pressed" after one pump), REQ-KEY-9 and REQ-A11Y-4 (200 items at widths 320 and 1920), REQ-KEY-11, REQ-KEY-12 (600 idle frames, state unchanged, no rebuild), REQ-SPEAK-2, REQ-SPEAK-3 with REQ-COMPOSE-5 (still shown after 10 s of frames, Close hides it), REQ-COMPOSE-3 and -4 via the buttons, REQ-A11Y-1, -2 and -5 at widths 320, 1024 and 1920
    - _Requirements: REQ-KEY-1, REQ-KEY-2, REQ-KEY-3, REQ-KEY-7, REQ-KEY-8, REQ-KEY-9, REQ-KEY-11, REQ-KEY-12, REQ-SPEAK-2, REQ-SPEAK-3, REQ-COMPOSE-3, REQ-COMPOSE-4, REQ-COMPOSE-5, REQ-A11Y-1, REQ-A11Y-2, REQ-A11Y-4, REQ-A11Y-5_
  - [ ] 5.11 Write the source rule tests
    - `app/test/source_rules_test.dart`: REQ-COMPOSE-1 no banned import or identifier (`package:flutter`, `dart:ui`, `dart:html`, `dart:io`, `dart:js_interop`, `DateTime.now`, `Stopwatch`, `Timer`, `Future.delayed`) in `app/lib/compose/`; REQ-CI-3 no `class Mock…` and no import of `test/` in any `app/lib/` file; REQ-CI-2 every `test(`, `testWidgets(` and `property(` description under `app/test/` begins with a REQ ID list and a colon
    - _Requirements: REQ-COMPOSE-1, REQ-CI-2, REQ-CI-3_

- [ ] 6. Checkpoint - Ensure all tests pass
  - Run `cd app && flutter analyze` and `cd app && flutter test`, then `cd packages/morse_core && dart test`.
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 7. Add the App tests step to the Deploy_Workflow
  - In `.github/workflows/deploy.yml`, insert a step named `App tests` with `working-directory: app` that runs `flutter pub get` then `flutter test`, between "Engine tests" and "Build web app"
  - No `continue-on-error` on the step or the job; leave "Engine tests", "Build web app" and "Deploy to Cloudflare" unchanged
  - _Requirements: REQ-CI-1_

- [ ] 8. Final checkpoint - Ensure all tests pass
  - Run `cd packages/morse_core && dart test` and `cd app && flutter test`; both exit 0 with zero failures.
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 9. Manual browser check before submission
  - This is a manual check by the user, not a coding task. It covers design research R4, which a widget test cannot prove.
  - On the deployed site in Chrome and Firefox: with Undo focused, Space does not activate Undo and does not scroll the page; a 100 ms dit decodes as `E`; Speak says the sentence; with no system voice available, the Fallback_View appears.
  - Record the result in `.kiro/evidence/LOG.md`.
  - _Requirements: REQ-KEY-1, REQ-KEY-5, REQ-SPEAK-1, REQ-SPEAK-3_

## Notes

- Tasks marked with `*` are optional test sub-tasks and can be skipped to ship faster. The tests REQ-CI-2 names are required and are not marked: 2.2 (a), 2.3 (b), 5.6 (c), 5.7 (d), 5.8 (e), 5.9 (f), plus 5.11 for the REQ-CI-2 naming rule and REQ-CI-3.
- `compose_properties_test.dart` and `key_screen_test.dart` are each written by several tasks, so those tasks run in separate waves.
- A property task that runs before the task that normally adds a generator adds that generator itself.
- Task 9 is listed because the user asked for it. It is the only task that is not done by a coding agent.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1"] },
    { "id": 1, "tasks": ["2.1", "2.5"] },
    { "id": 2, "tasks": ["2.2", "2.3", "2.6", "2.9"] },
    { "id": 3, "tasks": ["2.4", "2.10"] },
    { "id": 4, "tasks": ["2.7"] },
    { "id": 5, "tasks": ["2.8"] },
    { "id": 6, "tasks": ["2.11"] },
    { "id": 7, "tasks": ["3"] },
    { "id": 8, "tasks": ["4.1", "4.2", "4.4", "4.6"] },
    { "id": 9, "tasks": ["4.3", "4.5", "4.7"] },
    { "id": 10, "tasks": ["5.1", "5.3"] },
    { "id": 11, "tasks": ["5.2", "5.4"] },
    { "id": 12, "tasks": ["5.5"] },
    { "id": 13, "tasks": ["5.6", "5.11"] },
    { "id": 14, "tasks": ["5.7"] },
    { "id": 15, "tasks": ["5.8"] },
    { "id": 16, "tasks": ["5.9"] },
    { "id": 17, "tasks": ["5.10"] },
    { "id": 18, "tasks": ["6"] },
    { "id": 19, "tasks": ["7"] },
    { "id": 20, "tasks": ["8"] },
    { "id": 21, "tasks": ["9"] }
  ]
}
```
