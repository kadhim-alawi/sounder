/// The kind of a Timing_Input_Error, as a value tests can compare.
///
/// Each kind carries one fixed English [phrase], different from every other
/// kind's. REQ-EVENT-3, REQ-EVENT-4.
enum TimingInputErrorKind {
  /// A timestamp is outside the range −2^52 to 2^52 Microseconds.
  /// REQ-EVENT-5.
  timestampOutOfRange('timestamp is out of range'),

  /// The Event_Sequence starts with a release. REQ-EVENT-3.
  startsWithRelease('sequence starts with a release'),

  /// A press follows a press with no release between them. REQ-EVENT-3,
  /// REQ-LIVE-9.
  twoPressesInARow('two presses in a row'),

  /// A release follows a release with no press between them. REQ-EVENT-3,
  /// REQ-LIVE-9.
  twoReleasesInARow('two releases in a row'),

  /// A timestamp is lower than the one before it. REQ-EVENT-3, REQ-LIVE-9.
  decreasingTimestamp('timestamp is earlier than the one before'),

  /// The Event_Sequence ends with a press. REQ-EVENT-3.
  endsWithPress('sequence ends with a press'),

  /// The Debounce_Time is negative. REQ-DEBOUNCE-3.
  invalidDebounceTime('debounce time is negative'),

  /// The Word_Gap_Factor is not a finite number greater than 1 and at most
  /// 1,000. REQ-DEBOUNCE-3.
  invalidWordGapFactor(
    'word gap factor must be greater than 1 and at most 1000',
  ),

  /// The Dit_Length is invalid. REQ-CAL-14.
  invalidDitLength('dit length is invalid'),

  /// The Dah_Length is invalid. REQ-CAL-14.
  invalidDahLength('dah length is invalid'),

  /// The Symbol_Gap is invalid. REQ-CAL-14.
  invalidSymbolGap('symbol gap is invalid'),

  /// The Letter_Gap is invalid. REQ-CAL-14.
  invalidLetterGap('letter gap is invalid'),

  /// The Debounce_Time is longer than the Dit_Length or the Symbol_Gap.
  /// REQ-TIMING-9.
  debounceTimeTooLong(
    'debounce time is longer than the dit length or symbol gap',
  ),

  /// A duration given to the Classifier is negative. REQ-TIMING-11.
  negativeDuration('duration is negative'),

  /// A Press given to the Debouncer is released before it is pressed.
  /// REQ-DEBOUNCE-20.
  releaseBeforePress('press is released before it is pressed'),

  /// A Press given to the Debouncer starts before the previous Press is
  /// released. REQ-DEBOUNCE-20.
  pressOverlapsPrevious('press starts before the previous press is released');

  /// Creates a kind with its fixed [phrase]. REQ-EVENT-4.
  const TimingInputErrorKind(this.phrase);

  /// Fixed English phrase, unique per kind. REQ-EVENT-4.
  final String phrase;
}
