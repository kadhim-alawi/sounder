import 'package:flutter/foundation.dart';
import 'package:morse_core/morse_core.dart';

/// Marks "argument not given" for nullable fields in [KeyScreenState.copyWith],
/// so a caller can pass `null` to reset a field. REQ-CHOICE-5.
const Object _unset = Object();

/// One immutable snapshot of what the Key_Screen shows: the Sentence, the
/// Partial_Sequence, the switch state, whether the Fallback_View is shown,
/// and the expansion area (Expansion_Notice, Thinking_Indicator,
/// Candidate_List, Failure_Message).
/// REQ-KEY-8, REQ-KEY-10, REQ-KEY-12, REQ-SPEAK-3, REQ-NOTICE-1, REQ-WAIT-1,
/// REQ-CHOICE-1, REQ-FAIL-1, REQ-CHOICE-5.
@immutable
final class KeyScreenState {
  /// Creates a snapshot. [sentence] and [candidates] are copied into
  /// unmodifiable lists. The expansion fields default to the idle state:
  /// no notice, not thinking, no candidates, no failure, no fallback
  /// candidate. REQ-COMPOSE-5, REQ-CHOICE-1.
  KeyScreenState({
    required List<DecodedItem> sentence,
    required this.partialSequence,
    required this.isPressed,
    required this.fallbackVisible,
    this.noticeVisible = false,
    this.thinking = false,
    List<String> candidates = const <String>[],
    this.failureVisible = false,
    this.fallbackCandidate,
  }) : assert(candidates.length <= 4, 'REQ-CHOICE-1: at most 4 candidates'),
       sentence = List<DecodedItem>.unmodifiable(sentence),
       candidates = List<String>.unmodifiable(candidates);

  /// The empty start state: no Sentence, no Partial_Sequence, switch
  /// released, Fallback_View hidden, expansion area idle. REQ-KEY-6.
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

  /// Whether the one-time Expansion_Notice is shown. REQ-NOTICE-1.
  final bool noticeVisible;

  /// Whether a Pending_Request exists, so the Thinking_Indicator is shown.
  /// REQ-WAIT-1.
  final bool thinking;

  /// The Candidate_List, 0 to 4 Candidates in list order. Unmodifiable.
  /// REQ-CHOICE-1.
  final List<String> candidates;

  /// Whether the Failure_Message is shown. REQ-FAIL-1.
  final bool failureVisible;

  /// The Candidate text the Fallback_View shows in place of the Sentence
  /// after speaking a chosen Candidate failed, or `null` to show the
  /// Sentence. REQ-CHOICE-5.
  final String? fallbackCandidate;

  /// Returns a copy with the given fields replaced. Pass
  /// `fallbackCandidate: null` to reset it; omit it to keep the current
  /// value. REQ-KEY-12, REQ-CHOICE-5.
  KeyScreenState copyWith({
    List<DecodedItem>? sentence,
    String? partialSequence,
    bool? isPressed,
    bool? fallbackVisible,
    bool? noticeVisible,
    bool? thinking,
    List<String>? candidates,
    bool? failureVisible,
    Object? fallbackCandidate = _unset,
  }) => KeyScreenState(
    sentence: sentence ?? this.sentence,
    partialSequence: partialSequence ?? this.partialSequence,
    isPressed: isPressed ?? this.isPressed,
    fallbackVisible: fallbackVisible ?? this.fallbackVisible,
    noticeVisible: noticeVisible ?? this.noticeVisible,
    thinking: thinking ?? this.thinking,
    candidates: candidates ?? this.candidates,
    failureVisible: failureVisible ?? this.failureVisible,
    fallbackCandidate: identical(fallbackCandidate, _unset)
        ? this.fallbackCandidate
        : fallbackCandidate as String?,
  );
}
