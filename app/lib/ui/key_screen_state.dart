import 'package:flutter/foundation.dart';
import 'package:morse_core/morse_core.dart';

/// One immutable snapshot of what the Key_Screen shows: the Sentence, the
/// Partial_Sequence, the switch state and whether the Fallback_View is shown.
/// REQ-KEY-8, REQ-KEY-10, REQ-KEY-12, REQ-SPEAK-3.
@immutable
final class KeyScreenState {
  /// Creates a snapshot. [sentence] is copied into an unmodifiable list.
  /// REQ-COMPOSE-5.
  KeyScreenState({
    required List<DecodedItem> sentence,
    required this.partialSequence,
    required this.isPressed,
    required this.fallbackVisible,
  }) : sentence = List<DecodedItem>.unmodifiable(sentence);

  /// The empty start state: no Sentence, no Partial_Sequence, switch
  /// released, Fallback_View hidden. REQ-KEY-6.
  factory KeyScreenState.initial() => KeyScreenState(
    sentence: const <DecodedItem>[],
    partialSequence: '',
    isPressed: false,
    fallbackVisible: false,
  );

  /// The Sentence, oldest item first. Unmodifiable. REQ-COMPOSE-2,
  /// REQ-COMPOSE-5.
  final List<DecodedItem> sentence;

  /// The Live_Decoder Partial_Sequence as `.` and `-`. REQ-KEY-10.
  final String partialSequence;

  /// Whether the Live_Decoder reports the switch as pressed. REQ-KEY-8.
  final bool isPressed;

  /// Whether the speech-failure Fallback_View is shown. REQ-SPEAK-3,
  /// REQ-SPEAK-4, REQ-SPEAK-5.
  final bool fallbackVisible;

  /// Returns a copy with the given fields replaced. REQ-KEY-12.
  KeyScreenState copyWith({
    List<DecodedItem>? sentence,
    String? partialSequence,
    bool? isPressed,
    bool? fallbackVisible,
  }) => KeyScreenState(
    sentence: sentence ?? this.sentence,
    partialSequence: partialSequence ?? this.partialSequence,
    isPressed: isPressed ?? this.isPressed,
    fallbackVisible: fallbackVisible ?? this.fallbackVisible,
  );
}
