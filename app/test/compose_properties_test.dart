/// Property-based tests for the key-screen compose layer, one
/// `property(...)` per correctness property in the design. Each uses a
/// single `forAll` with `maxExamples: 200` and the fixed seed
/// `(200 + N) * 1000 + 3` for Property N. REQ-CI-2.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:morse_core/morse_core.dart';
import 'package:sounder/compose/composer.dart';
import 'package:sounder/compose/key_session.dart';
import 'package:sounder/compose/sentence_text.dart';
import 'package:sounder/input/pointer_adapter.dart';

import 'support/item_arbitraries.dart';

/// Records the counterexample and seed so a failure can be reproduced.
/// `DecodedItem.toString` prints only the item kind, so no decoded text is
/// printed. REQ-CI-2.
void Function(Object?) report(int seed) =>
    (x) => printOnFailure('Falsifying example: $x, seed: $seed');

void main() {
  // Feature: key-screen, Property 1: append then undo round trip
  property('REQ-COMPOSE-6, REQ-COMPOSE-3: append then undo round trip', () {
    forAll(
      combine2(itemList(maxLength: 200), integer(min: 0, max: 200)),
      (input) {
        final (items, rawK) = input;
        // Generate to satisfy, no filter: k is in 0..items.length.
        final k = rawK % (items.length + 1);
        final composer = Composer();
        items.forEach(composer.append);
        for (var i = 0; i < k; i++) {
          composer.undo();
        }
        expect(composer.sentence, items.sublist(0, items.length - k));
        if (k == items.length) {
          expect(composer.sentence, isEmpty);
        }
      },
      maxExamples: 200,
      seed: 201003,
      onFalsify: report(201003),
    );
  });

  // Feature: key-screen, Property 2: Composer matches a list model
  property('REQ-COMPOSE-2, REQ-COMPOSE-3, REQ-COMPOSE-4: '
      'Composer matches a list model', () {
    forAll(
      composerOps(maxLength: 300),
      (ops) {
        final composer = Composer();
        final model = <DecodedItem>[];
        for (final op in ops) {
          switch (op) {
            case AppendOp(:final item):
              composer.append(item);
              model.add(item);
            case UndoOp():
              composer.undo();
              if (model.isNotEmpty) model.removeLast();
            case ClearOp():
              composer.clear();
              model.clear();
          }
          expect(composer.sentence, model);
        }
      },
      maxExamples: 200,
      seed: 202003,
      onFalsify: report(202003),
    );
  });

  // Feature: key-screen, Property 3: Display text maps item by item
  property('REQ-KEY-11, REQ-KEY-10: display text maps item by item', () {
    forAll(
      combine2(itemList(maxLength: 200), symbolString(maxLength: 20)),
      (input) {
        final (items, symbols) = input;

        // Sentence text: one UTF-16 code unit per item, mapped by kind.
        final text = sentenceText(items);
        expect(text.length, items.length);
        for (var i = 0; i < items.length; i++) {
          final item = items[i];
          final expected = switch (item.kind) {
            DecodedItemKind.letter => item.character!,
            DecodedItemKind.unknownLetter => placeholder,
            DecodedItemKind.wordSpace => ' ',
          };
          expect(text[i], expected, reason: 'index $i');
        }

        // Partial_Sequence glyphs: same length, '.' -> '·', '-' -> '–'.
        final glyphs = partialGlyphs(symbols);
        expect(glyphs.length, symbols.length);
        for (var i = 0; i < symbols.length; i++) {
          expect(
            glyphs[i],
            symbols[i] == '.' ? '\u00B7' : '\u2013',
            reason: 'index $i',
          );
        }
      },
      maxExamples: 200,
      seed: 203003,
      onFalsify: report(203003),
    );
  });

  // Feature: key-screen, Property 4: Speak_Text is the letters, words separated by single spaces
  property('REQ-SPEAK-1, REQ-SPEAK-2: Speak_Text is the letters, '
      'words separated by single spaces', () {
    forAll(
      itemList(maxLength: 200),
      (items) {
        // Oracle: split at Word_Spaces, keep Letter_Item characters of
        // each part, drop empty parts, join with one space.
        final parts = <List<DecodedItem>>[<DecodedItem>[]];
        for (final item in items) {
          if (item.kind == DecodedItemKind.wordSpace) {
            parts.add(<DecodedItem>[]);
          } else {
            parts.last.add(item);
          }
        }
        final expected = parts
            .map(
              (part) => part
                  .where((i) => i.kind == DecodedItemKind.letter)
                  .map((i) => i.character!)
                  .join(),
            )
            .where((word) => word.isNotEmpty)
            .join(' ');

        final spoken = speakText(items);
        expect(spoken, expected);

        // Consequences named in the design.
        expect(spoken.contains(placeholder), isFalse);
        expect(spoken.contains('  '), isFalse);
        expect(spoken, spoken.trim());
        final hasLetter = items.any((i) => i.kind == DecodedItemKind.letter);
        expect(spoken.isEmpty, !hasLetter);
      },
      maxExamples: 200,
      seed: 204003,
      onFalsify: report(204003),
    );
  });

  // Feature: key-screen, Property 5: KeySession clamps, discards errors and forwards each item once
  property('REQ-KEY-4, REQ-KEY-7, REQ-COMPOSE-2, REQ-COMPOSE-3, '
      'REQ-COMPOSE-4: KeySession clamps, discards errors and forwards each '
      'item once', () {
    forAll(
      sessionCalls(maxLength: 150),
      (calls) {
        final decoder = LiveDecoder(
          Calibration(
            ditLength: defaultDitLength,
            dahLength: defaultDahLength,
            symbolGap: defaultSymbolGap,
            letterGap: defaultLetterGap,
          ),
          TimingConfig.defaults,
        );
        final session = KeySession.withDecoder(decoder);
        final model = <DecodedItem>[];

        for (final call in calls) {
          final sentenceBefore = List<DecodedItem>.of(session.sentence);
          final partialBefore = session.partialSequence;
          final pressedBefore = session.isPressed;
          final latestBefore = decoder.latestTimestamp;
          final itemsBefore = decoder.items.length;

          // The clamped timestamp the decoder should receive (D2).
          int expectedLatest(int t) =>
              latestBefore != null && latestBefore > t ? latestBefore : t;

          // Checks an accepted decoder call: the clamped timestamp was
          // recorded and the new items were forwarded once, in order.
          void accepted(int t) {
            expect(decoder.latestTimestamp, expectedLatest(t), reason: '$call');
            model.addAll(decoder.items.sublist(itemsBefore));
          }

          // Checks a rejected decoder call: nothing changed.
          void rejected() {
            expect(session.sentence, sentenceBefore, reason: '$call');
            expect(session.partialSequence, partialBefore, reason: '$call');
            expect(session.isPressed, pressedBefore, reason: '$call');
            expect(decoder.latestTimestamp, latestBefore, reason: '$call');
            expect(decoder.items.length, itemsBefore, reason: '$call');
          }

          switch (call) {
            case PressCall(:final t):
              final ok = session.press(t);
              // Only a press while pressed may be rejected, so no
              // decreasingTimestamp error can have occurred.
              expect(ok, !pressedBefore, reason: '$call');
              if (ok) {
                accepted(t);
              } else {
                rejected();
              }
            case ReleaseCall(:final t):
              final ok = session.release(t);
              // Only a release while released may be rejected.
              expect(ok, pressedBefore, reason: '$call');
              if (ok) {
                accepted(t);
              } else {
                rejected();
              }
            case AdvanceCall(:final t):
              // advanceTo is never rejected after the clamp: the latest
              // timestamp moving to the clamped value proves acceptance.
              session.advanceTo(t);
              accepted(t);
            case UndoCall():
              session.undo();
              if (model.isNotEmpty) model.removeLast();
            case ClearCall():
              session.clear();
              model.clear();
          }

          if (call is UndoCall || call is ClearCall) {
            expect(session.partialSequence, partialBefore, reason: '$call');
            expect(session.isPressed, pressedBefore, reason: '$call');
            expect(decoder.latestTimestamp, latestBefore, reason: '$call');
            expect(decoder.items.length, itemsBefore, reason: '$call');
          }

          // The latest timestamp never decreases (REQ-KEY-4).
          if (latestBefore != null) {
            expect(
              decoder.latestTimestamp,
              greaterThanOrEqualTo(latestBefore),
              reason: '$call',
            );
          }
          expect(session.sentence, model, reason: '$call');
        }
      },
      maxExamples: 200,
      seed: 205003,
      onFalsify: report(205003),
    );
  });

  // Feature: key-screen, Property 6: only the pressing pointer releases
  property('REQ-KEY-3, REQ-KEY-7: only the pressing pointer releases', () {
    forAll(
      pointerEventCalls(maxLength: 100),
      (events) {
        final adapter = PointerAdapter();
        // One-variable model: the tracked pointer, or null.
        int? tracked;
        for (final event in events) {
          switch (event.kind) {
            case PointerEventKind.down:
              expect(adapter.down(event.pointer), isTrue, reason: '$event');
              tracked ??= event.pointer;
            case PointerEventKind.up:
            case PointerEventKind.cancel:
              final expected = tracked == event.pointer;
              expect(adapter.end(event.pointer), expected, reason: '$event');
              if (expected) tracked = null;
          }
        }
      },
      maxExamples: 200,
      seed: 206003,
      onFalsify: report(206003),
    );
  });
}
