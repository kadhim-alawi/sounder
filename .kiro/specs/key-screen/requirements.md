# Requirements Document

## Introduction

`key-screen` is the first usable screen of the Sounder Flutter web app in `app/`. The user keys Morse code with one switch (the Space key or a large on-screen key), the existing `LiveDecoder` in `packages/morse_core` turns presses into letters, a Spell mode composer builds the sentence, and the user chooses Speak to hear it through the platform text-to-speech voice.

This spec is deliberately small so that it can ship today. Calibration, Shorthand mode, expansion, phrases, two-switch mode and switch scanning are later specs.

Every acceptance criterion has an ID in the style of the earlier specs: `REQ-KEY-n` (input, timing and display), `REQ-COMPOSE-n` (composer), `REQ-SPEAK-n` (speech), `REQ-A11Y-n` (accessibility) and `REQ-CI-n` (tests and pipeline). None of these areas reuse an area name from the morse-core or adaptive-timing specs. Tests and doc comments cite these IDs.

### Decisions and assumptions

These points were not fixed by the request. Each is a recorded decision, flagged for review.

- **K1. Clock choice belongs to the design.** These requirements only fix that every timestamp passed to the Live_Decoder comes from one monotonic Microsecond Time_Base (REQ-KEY-4). The design must name the clock used for key events, pointer events and `advanceTo`, and show that they share a time base.
- **K2. Default Calibration.** Until the calibrate screen exists, the Key_Screen uses Dit_Length 100,000, Dah_Length 300,000, Symbol_Gap 250,000 and Letter_Gap 700,000 Microseconds with the default Timing_Config (Debounce_Time 30,000, Word_Gap_Factor 2.0). These values come from the Flutter web spike and match the adaptive-timing examples (REQ-BATCH-5).
- **K3. Two sources, one switch.** The Space key and the On_Screen_Key drive the same Live_Decoder. A press from one source while the other holds the switch is rejected by the Live_Decoder as two presses in a row and is discarded (REQ-KEY-7). No source-tracking logic is added.
- **K4. Placeholder.** An Unknown_Letter_Item appears in the Sentence as the Placeholder character `□` (U+25A1). The Placeholder is shown but not spoken (REQ-SPEAK-1), because speaking a symbol name would put words in the user's mouth (product principle 4).
- **K5. Audible press feedback is deferred.** Product principle 1 asks for visible and audible feedback on every press. This spec delivers visible feedback only (REQ-KEY-8). Audible feedback is left to a later spec. This is a deviation from a design principle and needs explicit approval.
- **K6. Dependency placement.** `app/pubspec.yaml` lists `morse_core` under `dev_dependencies`. The app imports it at runtime, so it must move to `dependencies`. `kiri_check` is added to the app's `dev_dependencies` for REQ-COMPOSE-6.
- **K7. Fallback is dismissed by the user.** The speech-failure Fallback_View stays until the user closes it with a control (REQ-SPEAK-3). It never closes on a timer (product principle 3).
- **K8. Undo and Clear scope.** Undo and Clear act on the Sentence only and never change the Live_Decoder Partial_Sequence. Only the on-screen buttons trigger Undo and Clear (REQ-COMPOSE-3, REQ-COMPOSE-4).
- **K9. Partial_Sequence glyphs.** The Partial_Sequence is shown with `·` (U+00B7) for dit and `–` (U+2013) for dah (REQ-KEY-10, REQ-A11Y-5).
- **K10. Closing the Fallback_View with one switch is deferred.** The Fallback_View closes with its Close control, the Escape key (REQ-SPEAK-4) or a Speak_Action that completes successfully (REQ-SPEAK-5). Closing it with the switch alone is left to the switch-scanning spec. Known limitation: a one-switch user who cannot use a pointer or the Escape key cannot close the Fallback_View until switch scanning exists, except through a successful Speak.
- **K11. Silent speech is not detected.** REQ-SPEAK-3 covers only failures that the Speech_Service reports. Speech that reports success but makes no sound, or that reports nothing, shows no Fallback_View. This is accepted as a known limitation for this spec.

## Glossary

- **Key_Screen**: The Flutter screen in `app/lib/ui/` defined by this spec.
- **Live_Decoder**: The existing `LiveDecoder` class in `packages/morse_core/lib/src/live_decoder.dart`, with `press`, `release` and `advanceTo` calls, `items` (completed Decoded_Items), `partialSequence` and `isPressed`.
- **Calibration**: The existing morse_core `Calibration` value: Dit_Length, Dah_Length, Symbol_Gap and Letter_Gap in Microseconds.
- **Dit_Length**: The calibrated duration of a press meant as a dit.
- **Dah_Length**: The calibrated duration of a press meant as a dah.
- **Symbol_Gap**: The calibrated duration of a gap between two presses inside one letter.
- **Letter_Gap**: The calibrated duration of a gap between two letters inside one word.
- **Timing_Config**: The existing morse_core `TimingConfig` value: Debounce_Time and Word_Gap_Factor.
- **Debounce_Time**: The Timing_Config duration, in Microseconds, below which a press or a gap counts as switch bounce. Default 30,000.
- **Word_Gap_Factor**: The Timing_Config number that, multiplied by Letter_Gap, sets the gap that ends a word. Default 2.0.
- **Letter_Gap_Threshold**: The Live_Decoder duration, derived from Symbol_Gap and Letter_Gap as in adaptive-timing REQ-TIMING-1, at or above which a gap ends a letter.
- **Partial_Sequence**: The Live_Decoder `partialSequence`: the confirmed dits and dahs of the letter the Live_Decoder is currently building.
- **Decoded_Item**: The existing morse_core `DecodedItem`: a Letter_Item, an Unknown_Letter_Item or a Word_Space.
- **Letter_Item**: A Decoded_Item carrying the uppercase character that the morse_core code table maps the letter's dits and dahs to.
- **Unknown_Letter_Item**: A Decoded_Item carrying a non-empty sequence of dits and dahs that is not a Morse code in the morse_core code table.
- **Word_Space**: A Decoded_Item that separates two words.
- **Timing_Input_Error**: The existing morse_core `TimingInputException`.
- **Microsecond**: The unit of every timestamp passed to the Live_Decoder, held as a Dart `int`.
- **Time_Base**: The single monotonic clock, read in Microseconds, from which the Key_Screen takes every timestamp it passes to the Live_Decoder.
- **Switch_Source**: Either the Space key or the On_Screen_Key.
- **On_Screen_Key**: The large on-screen button on the Key_Screen that acts as the switch.
- **Repeat_Event**: A key event the platform generates while a key is held down (Flutter `KeyRepeatEvent`).
- **Frame_Ticker**: The Key_Screen component that calls `advanceTo` once per rendered frame.
- **Composer**: The pure Dart Spell mode composer in `app/lib/compose/` that holds the Sentence.
- **Sentence**: The ordered list of Decoded_Items the Composer holds, shown as text in which a Letter_Item is its character, an Unknown_Letter_Item is the Placeholder and a Word_Space is one space.
- **Undo**: The Composer operation, triggered by the on-screen Undo button, that removes the last Decoded_Item from the Sentence.
- **Clear**: The Composer operation, triggered by the on-screen Clear button, that makes the Sentence empty.
- **Placeholder**: The character `□` (U+25A1) shown for an Unknown_Letter_Item.
- **Speak_Text**: The Sentence text with every Placeholder removed, runs of spaces collapsed to one space, and leading and trailing spaces trimmed.
- **Speech_Service**: The app component in `app/lib/speech/` that passes Speak_Text to a Flutter text-to-speech plugin that supports the web platform.
- **Speak_Action**: A non-repeat Enter key-down event on the Key_Screen, or activation of the on-screen Speak button.
- **Speech_Failure**: The Speech_Service reports that speaking did not start or did not complete: the plugin raises an error, reports an error, or reports that no voice is available.
- **Fallback_View**: A full-screen view showing the Sentence text and a short notice that speech failed, with a Close control.
- **Deploy_Workflow**: The GitHub Actions file `.github/workflows/deploy.yml`.

## Requirements

### Requirement 1: Switch input and timing

**User Story:** As a person who can make one reliable movement, I want the Space key or a large on-screen key to act as my switch, so that I can key Morse code with whichever I can reach.

#### Acceptance Criteria

1. REQ-KEY-1: WHEN the Key_Screen receives a non-repeat Space key-down event, THE Key_Screen SHALL make one Live_Decoder `press` call, and WHEN the Key_Screen receives a Space key-up event, THE Key_Screen SHALL make one Live_Decoder `release` call. This SHALL hold whichever control on the Key_Screen has keyboard focus. The Space key SHALL activate no other control and SHALL trigger no browser default action, including page scrolling.
2. REQ-KEY-2: WHEN the Key_Screen receives a Repeat_Event for the Space key, the Enter key or the Escape key, THE Key_Screen SHALL make no Live_Decoder call and no Speak_Action for that event, and the Sentence, the Partial_Sequence and the On_Screen_Key state SHALL stay unchanged.
3. REQ-KEY-3: WHEN a pointer (mouse, touch or pen) goes down on the On_Screen_Key, THE Key_Screen SHALL make one Live_Decoder `press` call, and WHEN that same pointer goes up or is cancelled, whether or not it is still over the On_Screen_Key, THE Key_Screen SHALL make one Live_Decoder `release` call.
4. REQ-KEY-4: THE Key_Screen SHALL take every timestamp it passes to the Live_Decoder `press`, `release` and `advanceTo` calls, from both Switch_Sources and the Frame_Ticker, from the one Time_Base as a whole number of Microseconds. Each timestamp SHALL be greater than or equal to the timestamp passed in the previous Live_Decoder call of any kind.
5. REQ-KEY-5: WHILE the Key_Screen is shown, THE Frame_Ticker SHALL make exactly one Live_Decoder `advanceTo` call per rendered frame with the Time_Base timestamp read for that frame. As a result, a letter in progress SHALL appear in the Sentence in the first rendered frame whose timestamp is at least the Live_Decoder's Letter_Gap_Threshold after the last release, with no further press.
6. REQ-KEY-6: WHEN the Key_Screen is created, THE Key_Screen SHALL create one Live_Decoder with a Calibration of Dit_Length 100,000, Dah_Length 300,000, Symbol_Gap 250,000 and Letter_Gap 700,000 Microseconds and the default Timing_Config (Debounce_Time 30,000 Microseconds, Word_Gap_Factor 2.0). Both Switch_Sources and the Frame_Ticker SHALL use that one Live_Decoder.
7. REQ-KEY-7: IF a Live_Decoder call raises a Timing_Input_Error, which includes a press from one Switch_Source while the other Switch_Source holds the switch, THEN THE Key_Screen SHALL discard that event and show no error to the user. The Sentence, the Partial_Sequence and the On_Screen_Key state SHALL stay as they were before the call, and THE Key_Screen SHALL handle the next input event and the next frame as usual. Because no source tracking is added (K3), a release from either Switch_Source SHALL end the current press.
8. REQ-KEY-8: WHEN a `press` or `release` call returns without a Timing_Input_Error, THE Key_Screen SHALL show the On_Screen_Key in the pressed state if the Live_Decoder `isPressed` value is true, and in the released state if it is false. The new state SHALL appear in the next rendered frame and no later than 50 milliseconds after the Key_Screen receives the input event.

### Requirement 2: Display

**User Story:** As a person keying a sentence, I want to see the sentence and the letter I am keying, so that I can follow my input as I go.

#### Acceptance Criteria

1. REQ-KEY-9: THE Key_Screen SHALL show the Sentence text and the Partial_Sequence each at a font size of at least 32 logical pixels, and SHALL wrap the Sentence text onto further lines so that no character of the Sentence is truncated, clipped or replaced by an ellipsis.
2. REQ-KEY-10: WHEN a Live_Decoder call changes the Partial_Sequence or appends a Decoded_Item, or the Composer changes the Sentence through append, Undo or Clear, THE Key_Screen SHALL show the new Sentence text and the new Partial_Sequence in the next rendered frame. The Partial_Sequence SHALL be shown as one dot for each dit and one dash for each dah, in keyed order, and SHALL be shown empty when the Live_Decoder Partial_Sequence is empty.
3. REQ-KEY-11: WHEN the Live_Decoder appends an Unknown_Letter_Item, THE Key_Screen SHALL show exactly one Placeholder in the Sentence text at the position of that Unknown_Letter_Item, between the characters of the Decoded_Items before and after it.
4. REQ-KEY-12: THE Key_Screen SHALL change its layout, colours and content only in response to a Switch_Source event, a Speak_Action, an Undo, Clear or Close activation, a focus change made by the user, a change in Live_Decoder `items`, `partialSequence` or `isPressed`, or a Speech_Service result. THE Key_Screen SHALL contain no animation that runs by itself, such as a blinking cursor, spinner, scrolling text or timed transition, so that while none of these events occur for 10 seconds, every rendered frame of the Key_Screen is identical to the frame before it.

### Requirement 3: Spell mode composer

**User Story:** As a person keying letter by letter, I want my decoded letters to build a sentence that I can undo or clear, so that a mistake never forces me to start over.

#### Acceptance Criteria

1. REQ-COMPOSE-1: THE Composer SHALL be pure Dart in `app/lib/compose/`, SHALL import no `package:flutter` library, `dart:ui`, `dart:html`, `dart:io` or `dart:js_interop`, and SHALL read no clock, start no timer and perform no I/O. This means no use of `DateTime.now`, `Stopwatch`, `Timer` or `Future.delayed`.
2. REQ-COMPOSE-2: WHEN the Key_Screen passes a Decoded_Item to the Composer, THE Composer SHALL append that Decoded_Item to the end of the Sentence and leave every earlier Decoded_Item unchanged and in order. THE Key_Screen SHALL pass each Decoded_Item that the Live_Decoder appends to `items` to the Composer exactly once, in the order the Live_Decoder appended them, and SHALL pass no other Decoded_Item.
3. REQ-COMPOSE-3: WHEN the user activates the on-screen Undo button, THE Composer SHALL remove only the last Decoded_Item (Letter_Item, Unknown_Letter_Item or Word_Space) from the Sentence, leaving every earlier Decoded_Item unchanged and in order, and THE Key_Screen SHALL show the updated Sentence in the next rendered frame. IF the Sentence is empty when Undo is activated, THEN THE Composer SHALL leave the Sentence empty and raise no error. Undo SHALL NOT change the Live_Decoder Partial_Sequence.
4. REQ-COMPOSE-4: WHEN the user activates the on-screen Clear button, THE Composer SHALL make the Sentence empty, raising no error if the Sentence is already empty, and THE Key_Screen SHALL show the empty Sentence in the next rendered frame. Clear SHALL NOT change the Live_Decoder Partial_Sequence.
5. REQ-COMPOSE-5: THE Composer SHALL change the Sentence only through append (REQ-COMPOSE-2), Undo (REQ-COMPOSE-3) and Clear (REQ-COMPOSE-4). THE Key_Screen SHALL offer Undo and Clear as on-screen buttons, and a Speak_Action, a Speech_Failure or closing the Fallback_View SHALL leave the Sentence unchanged.
6. REQ-COMPOSE-6: FOR ALL sequences of 0 to 200 Decoded_Items, drawn from Letter_Items, Unknown_Letter_Items and Word_Spaces and appended to an empty Composer, and FOR ALL k from 0 to the sequence length, applying Undo k times SHALL leave a Sentence equal to the first (length − k) items of the sequence, in order. With k equal to the length, the Sentence SHALL be empty (append and undo round-trip property).

### Requirement 4: Speech

**User Story:** As a person who cannot speak, I want the sentence spoken aloud only when I choose Speak, so that the words said are always mine.

#### Acceptance Criteria

1. REQ-SPEAK-1: WHEN a Speak_Action occurs and the Speak_Text is not empty, THE Key_Screen SHALL pass the Speak_Text to the Speech_Service exactly once for that Speak_Action. The Speak_Text SHALL be built only from the Decoded_Items in the Sentence when the Speak_Action occurs and SHALL exclude any Live_Decoder Partial_Sequence. THE Key_Screen SHALL leave the Sentence unchanged after the Speak_Action.
2. REQ-SPEAK-2: IF a Speak_Action occurs and the Speak_Text is empty (the Sentence is empty, or holds only Placeholders and Word_Spaces), THEN THE Key_Screen SHALL make no Speech_Service call, show no Fallback_View, and leave the Sentence unchanged. THE Key_Screen SHALL call the Speech_Service only as a result of a Speak_Action, and THE Speech_Service SHALL speak only text passed to it by a Speak_Action.
3. REQ-SPEAK-3: IF the Speech_Service reports a Speech_Failure, THEN THE Key_Screen SHALL show the Fallback_View with the Sentence text (Placeholders included) at a font size of at least 32 logical pixels and a notice that speech failed. THE Key_Screen SHALL keep the Fallback_View shown until the user activates its Close control, presses the Escape key (REQ-SPEAK-4), or a Speak_Action completes successfully (REQ-SPEAK-5), with no timer closing it. WHEN the user activates the Close control, THE Key_Screen SHALL hide the Fallback_View and return to the Key_Screen with the Sentence unchanged.
4. REQ-SPEAK-4: WHEN the Fallback_View is shown and the Key_Screen receives a non-repeat Escape key-down event, THE Key_Screen SHALL hide the Fallback_View with the Sentence unchanged, whichever control has keyboard focus. Escape Repeat_Events are ignored as in REQ-KEY-2.
5. REQ-SPEAK-5: WHEN the Fallback_View is shown and a Speak_Action results in the Speech_Service reporting that speaking completed successfully, THE Key_Screen SHALL hide the Fallback_View with the Sentence unchanged.

### Requirement 5: Accessibility

**User Story:** As a person with limited movement or vision, I want every control to be large, labelled and readable, so that I can use the Key_Screen with assistive technology on a small screen.

#### Acceptance Criteria

1. REQ-A11Y-1: THE Key_Screen SHALL give the On_Screen_Key and the Speak, Undo, Clear and Close controls each a non-empty semantic label exposed to assistive technology that names the control's action, SHALL expose the On_Screen_Key's pressed or released state in its semantics, and SHALL give the Sentence and the Partial_Sequence each a semantic value equal to their current displayed text, with a non-empty label saying the field is empty when that text is empty.
2. REQ-A11Y-2: THE Key_Screen SHALL give the On_Screen_Key, the Speak, Undo and Clear controls, and the Fallback_View Close control each a touch target of at least 48 by 48 logical pixels, measured as the hit-test area of the control, at every viewport width from 320 to 1920 logical pixels.
3. REQ-A11Y-3: THE Key_Screen SHALL show all text, including the Sentence, the Placeholder, the Partial_Sequence, control labels and the Fallback_View notice, with a contrast ratio of at least 7:1 against the background colour directly behind that text, where every such background colour has a WCAG 2.x relative luminance of at most 0.2, and every ratio is computed with the WCAG 2.x contrast ratio formula.
4. REQ-A11Y-4: WHILE the browser viewport is from 320 to 1920 logical pixels wide, THE Key_Screen and the Fallback_View SHALL show every control fully within the viewport width with no horizontal scrolling, and SHALL show a Sentence of up to 200 Decoded_Items in full by wrapping onto further lines, with vertical scrolling permitted and no text cut off or hidden.
5. REQ-A11Y-5: THE Key_Screen SHALL show each of these states with a cue that does not depend on colour, so that every state stays distinguishable when the screen is rendered in greyscale: switch pressed versus released (a text label or a change in shape or icon on the On_Screen_Key), the Partial_Sequence (the dot `·` and dash `–` characters), an Unknown_Letter_Item (the Placeholder character), and a Speech_Failure (the Fallback_View notice text).

### Requirement 6: Tests and pipeline

**User Story:** As a Sounder developer, I want the Key_Screen tested on every push, so that a broken screen never deploys.

#### Acceptance Criteria

1. REQ-CI-1: THE Deploy_Workflow SHALL contain a step, placed after the Flutter setup step and before the "Build web app" step, that runs `flutter pub get` and then `flutter test` with working directory `app`, with no `continue-on-error` setting on that step or its job, so that a non-zero exit from `flutter test` fails the Deploy_Workflow run and neither the "Build web app" step nor the "Deploy to Cloudflare" step runs. The existing "Engine tests" step SHALL remain in the Deploy_Workflow.
2. REQ-CI-2: WHEN `flutter test` runs in `app/`, THE app test suite SHALL exit with code 0 and report zero failed tests. The suite SHALL include: (a) at least one unit test for each of REQ-COMPOSE-2, REQ-COMPOSE-3 (including Undo on an empty Sentence), REQ-COMPOSE-4 and REQ-COMPOSE-5; (b) a `kiri_check` property test for REQ-COMPOSE-6 configured to run at least 100 generated cases, with generated sequence lengths from 0 to 200; (c) a widget test that drives the Key_Screen from a test-controlled Time_Base, sends a non-repeat Space key-down at time T and a Space key-up at T + 100,000 Microseconds, then renders frames until the Time_Base reaches at least T + 900,000 Microseconds, and checks that the Sentence text is exactly `E`; (d) a widget test in which the Sentence holds at least one Letter_Item, one Speak_Action occurs, and the speech mock receives exactly one call whose text equals the Speak_Text; (e) a widget test in which, with the Fallback_View shown, a non-repeat Escape key-down hides the Fallback_View and leaves the Sentence unchanged; and (f) a widget test in which, with the Fallback_View shown, a Speak_Action whose speech mock reports success hides the Fallback_View. Every test description SHALL begin with the requirement ID or IDs the test covers, followed by a colon.
3. REQ-CI-3: THE app SHALL define every Speech_Service mock only in files under `app/test/`, and every such mock class name SHALL begin with `Mock`. No file under `app/lib/` SHALL define or import a class whose name begins with `Mock`, and no file under `app/lib/` SHALL contain a hardcoded sentence passed to the Speech_Service, so that the hosted build speaks only Speak_Text produced from a Speak_Action.
