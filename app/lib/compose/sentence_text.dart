import 'package:morse_core/morse_core.dart';

/// The Placeholder `□` (U+25A1) shown for an Unknown_Letter_Item and never
/// spoken (K4). REQ-KEY-11, REQ-SPEAK-1.
const String placeholder = '\u25A1';

/// The Sentence text: a Letter_Item is its character, an
/// Unknown_Letter_Item is the [placeholder] and a Word_Space is one space,
/// one UTF-16 code unit per item, in order. Pure Dart. REQ-KEY-11,
/// REQ-COMPOSE-1.
String sentenceText(List<DecodedItem> items) {
  final buffer = StringBuffer();
  for (final item in items) {
    buffer.write(switch (item.kind) {
      DecodedItemKind.letter => item.character!,
      DecodedItemKind.unknownLetter => placeholder,
      DecodedItemKind.wordSpace => ' ',
    });
  }
  return buffer.toString();
}

/// The Speak_Text: the Sentence text with every Placeholder removed, runs
/// of spaces collapsed to one and no leading or trailing space. Built as
/// the Letter_Item characters of each word between Word_Spaces, empty
/// words dropped, joined by one space. Empty when the Sentence has no
/// Letter_Item. REQ-SPEAK-1, REQ-SPEAK-2, REQ-COMPOSE-1.
String speakText(List<DecodedItem> items) {
  final words = <String>[];
  final word = StringBuffer();
  for (final item in items) {
    switch (item.kind) {
      case DecodedItemKind.letter:
        word.write(item.character!);
      case DecodedItemKind.unknownLetter:
        break;
      case DecodedItemKind.wordSpace:
        if (word.isNotEmpty) {
          words.add(word.toString());
          word.clear();
        }
    }
  }
  if (word.isNotEmpty) {
    words.add(word.toString());
  }
  return words.join(' ');
}

/// The Partial_Sequence for display: each `.` becomes `·` (U+00B7) and
/// each `-` becomes `–` (U+2013), in keyed order, same length; empty in,
/// empty out (K9). REQ-KEY-10, REQ-COMPOSE-1.
String partialGlyphs(String partialSequence) =>
    partialSequence.replaceAll('.', '\u00B7').replaceAll('-', '\u2013');
