import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../compose/expansion_client.dart';
import '../compose/initials_validator.dart';
import '../compose/key_session.dart';
import '../compose/narrowing.dart';
import '../compose/sentence_text.dart';
import '../compose/sentence_tokens.dart';
import '../input/time_base.dart';
import '../net/http_expansion_transport.dart';
import '../speech/flutter_tts_speech_service.dart';
import '../speech/speech_service.dart';
import '../store/notice_store.dart';
import 'key_screen_state.dart';

/// Most Candidates the Candidate_List shows. REQ-CHOICE-1.
const int maxShownCandidates = 4;

/// The one Time_Base for every Live_Decoder timestamp. Tests override it
/// with a test-controlled clock (design D3). REQ-KEY-4.
final timeBaseProvider = Provider<TimeBase>((ref) => const PlatformTimeBase());

/// The Speech_Service used for Speak_Actions and chosen Candidates. Tests
/// override it with a mock defined under `app/test/` (REQ-CI-3).
/// REQ-SPEAK-1, REQ-CHOICE-3.
final speechServiceProvider = Provider<SpeechService>(
  (ref) => FlutterTtsSpeechService(),
);

/// The Expansion_Client: a [TransportExpansionClient] over
/// [HttpExpansionTransport], with the real 6-second [Delay]
/// (`Future.delayed`), which lives here so `lib/compose/` stays free of
/// timers (design D9, REQ-COMPOSE-1). Tests override it with a mock defined
/// under `app/test/` (REQ-APPTEST-4). REQ-WAIT-3, REQ-WAIT-5.
final expansionClientProvider = Provider<ExpansionClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return TransportExpansionClient(
    transport: HttpExpansionTransport(client),
    delay: (duration) => Future<void>.delayed(duration),
  );
});

/// The store of the Notice_Acceptance in browser storage. Tests override it
/// with a mock defined under `app/test/`. REQ-NOTICE-2, REQ-NOTICE-5.
final noticeStoreProvider = Provider<NoticeStore>(
  (ref) => SharedPreferencesNoticeStore(),
);

/// The Key_Screen controller and its published [KeyScreenState].
/// REQ-KEY-6, REQ-KEY-12.
final keyScreenControllerProvider =
    NotifierProvider<KeyScreenController, KeyScreenState>(
      KeyScreenController.new,
    );

/// Wraps one [KeySession] and publishes immutable [KeyScreenState]
/// snapshots (design D5). Every timestamp goes through the [TimeBase]
/// (REQ-KEY-4). Only [speak] and [choose] call the Speech_Service
/// (REQ-SPEAK-2, REQ-CHOICE-6), and only [undo] and [clear] change the
/// Sentence apart from decoded items (REQ-COMPOSE-5). It also runs the
/// Expand flow: the one-time Expansion_Notice, one Pending_Request at a
/// time tracked by request id, the Candidate_List and the Failure_Message.
/// Nothing here prints or logs the Sentence, a Token or a Candidate
/// (REQ-FAIL-4).
/// REQ-KEY-4, REQ-KEY-5, REQ-KEY-7, REQ-KEY-8, REQ-KEY-12, REQ-COMPOSE-2,
/// REQ-COMPOSE-3, REQ-COMPOSE-4, REQ-COMPOSE-5, REQ-SPEAK-1, REQ-SPEAK-2,
/// REQ-SPEAK-3, REQ-SPEAK-4, REQ-SPEAK-5, REQ-TOKENS-2, REQ-NOTICE-1,
/// REQ-NOTICE-2, REQ-NOTICE-3, REQ-NOTICE-4, REQ-NOTICE-5, REQ-WAIT-3,
/// REQ-WAIT-4, REQ-WAIT-6, REQ-CHOICE-1, REQ-CHOICE-3, REQ-CHOICE-4,
/// REQ-CHOICE-5, REQ-CHOICE-6, REQ-NARROW-1, REQ-NARROW-2, REQ-FAIL-1,
/// REQ-FAIL-2, REQ-FAIL-4.
final class KeyScreenController extends Notifier<KeyScreenState> {
  late KeySession _session;

  // Cached Notice_Acceptance (design D10). False until the store read
  // finishes, and false when the read or write fails. REQ-NOTICE-5.
  bool _noticeAccepted = false;

  // Id of the last request sent; ids only grow. REQ-WAIT-6.
  int _requestSeq = 0;

  // Id of the Pending_Request, or null when none exists or it was
  // abandoned. Only a reply carrying this id can change the screen.
  // REQ-WAIT-4, REQ-WAIT-6, REQ-NARROW-2.
  int? _pendingId;

  /// Creates the one Live_Decoder with the default Calibration through a new
  /// [KeySession], starts reading the Notice_Acceptance in the background
  /// (design D10), and returns the empty state. REQ-KEY-6, REQ-NOTICE-5.
  @override
  KeyScreenState build() {
    _session = KeySession();
    _noticeAccepted = false;
    _requestSeq = 0;
    _pendingId = null;
    unawaited(_loadAcceptance());
    return KeyScreenState.initial();
  }

  /// A switch press at [platformTime]. A rejected press changes nothing and
  /// shows no error. REQ-KEY-1, REQ-KEY-3, REQ-KEY-4, REQ-KEY-7, REQ-KEY-8.
  void press(Duration platformTime) {
    if (_session.press(_stamp(platformTime))) _publish();
  }

  /// A switch release at [platformTime]. A rejected release changes nothing
  /// and shows no error. REQ-KEY-1, REQ-KEY-3, REQ-KEY-4, REQ-KEY-7,
  /// REQ-KEY-8.
  void release(Duration platformTime) {
    if (_session.release(_stamp(platformTime))) _publish();
  }

  /// One Frame_Ticker frame at [platformTime]. Publishes a new state only
  /// when the Partial_Sequence, the Sentence length or the switch state
  /// changed, so an idle frame causes no rebuild. REQ-KEY-4, REQ-KEY-5,
  /// REQ-KEY-12, REQ-COMPOSE-2.
  void frame(Duration platformTime) {
    _session.advanceTo(_stamp(platformTime));
    final current = state;
    if (_session.partialSequence != current.partialSequence ||
        _session.sentence.length != current.sentence.length ||
        _session.isPressed != current.isPressed) {
      _publish();
    }
  }

  /// A Speak_Action. With an empty Speak_Text it makes no Speech_Service
  /// call. Otherwise it makes exactly one call for the typed Sentence, never
  /// a Candidate: `failed` shows the Fallback_View with the Sentence text
  /// (`fallbackCandidate` reset), `completed` hides it, `superseded` leaves
  /// it as it is. The Sentence is never changed. REQ-SPEAK-1, REQ-SPEAK-2,
  /// REQ-SPEAK-3, REQ-SPEAK-5, REQ-COMPOSE-5, REQ-CHOICE-4.
  Future<void> speak() async {
    final text = speakText(_session.sentence);
    if (text.isEmpty) return;
    final result = await ref.read(speechServiceProvider).speak(text);
    if (!ref.mounted) return;
    switch (result) {
      case SpeechResult.failed:
        state = state.copyWith(fallbackVisible: true, fallbackCandidate: null);
      case SpeechResult.completed:
        state = state.copyWith(fallbackVisible: false, fallbackCandidate: null);
      case SpeechResult.superseded:
        break;
    }
  }

  /// Removes the last Decoded_Item of the Sentence; the Partial_Sequence is
  /// unchanged. REQ-COMPOSE-3.
  void undo() {
    _session.undo();
    _publish();
  }

  /// Makes the Sentence empty; the Partial_Sequence is unchanged.
  /// REQ-COMPOSE-4.
  void clear() {
    _session.clear();
    _publish();
  }

  /// Hides the Fallback_View with the Sentence unchanged. Does nothing when
  /// it is hidden. Used by the Close control and, through [escape], the
  /// Escape key. REQ-SPEAK-3, REQ-SPEAK-4, REQ-COMPOSE-5.
  void closeFallback() {
    if (!state.fallbackVisible) return;
    state = state.copyWith(fallbackVisible: false, fallbackCandidate: null);
  }

  /// An Expand_Action. Does nothing while the Sentence_Tokens are not ready
  /// (REQ-TOKENS-2). Otherwise clears the Failure_Message and either shows
  /// the Expansion_Notice when no Notice_Acceptance is known (REQ-NOTICE-1),
  /// or sends the Sentence_Tokens, abandoning any older Pending_Request
  /// (REQ-NOTICE-4, REQ-WAIT-6). Shown Candidates stay until the reply
  /// (design D13). REQ-TOKENS-2, REQ-NOTICE-1, REQ-NOTICE-4, REQ-WAIT-6,
  /// REQ-FAIL-2.
  void expand() {
    final check = sentenceTokens(_session.sentence);
    if (check is! TokensReady) return;
    if (!_noticeAccepted) {
      state = state.copyWith(noticeVisible: true, failureVisible: false);
      return;
    }
    unawaited(_send(check.tokens));
  }

  /// Send on the Expansion_Notice. Does nothing unless the notice is shown.
  /// Closes the notice, caches the Notice_Acceptance and writes it in the
  /// background (a failed write resets the cache, REQ-NOTICE-5), then sends
  /// the current Sentence_Tokens if they are ready; otherwise sends nothing
  /// (design D11). REQ-NOTICE-2, REQ-NOTICE-5.
  void sendNotice() {
    if (!state.noticeVisible) return;
    state = state.copyWith(noticeVisible: false);
    _noticeAccepted = true;
    unawaited(_storeAcceptance());
    final check = sentenceTokens(_session.sentence);
    if (check is TokensReady) unawaited(_send(check.tokens));
  }

  /// Cancel on the Expansion_Notice. Does nothing unless the notice is
  /// shown. Closes it, sends no request, stores nothing and leaves the
  /// Sentence unchanged. REQ-NOTICE-3.
  void cancelNotice() {
    if (!state.noticeVisible) return;
    state = state.copyWith(noticeVisible: false);
  }

  /// Chooses Candidate [n] (1-based), from its Candidate_Button or number
  /// key. Does nothing when the Candidate_List has fewer than [n] items
  /// (REQ-CHOICE-6). Otherwise passes that Candidate's text to the
  /// Speech_Service exactly once and leaves the Sentence and the
  /// Candidate_List unchanged (E20). `failed` shows the Fallback_View with
  /// the Candidate text, `completed` hides it, `superseded` changes nothing.
  /// REQ-CHOICE-3, REQ-CHOICE-5, REQ-CHOICE-6.
  Future<void> choose(int n) async {
    final candidates = state.candidates;
    if (n < 1 || n > candidates.length) return;
    final text = candidates[n - 1];
    final result = await ref.read(speechServiceProvider).speak(text);
    if (!ref.mounted) return;
    switch (result) {
      case SpeechResult.failed:
        state = state.copyWith(fallbackVisible: true, fallbackCandidate: text);
      case SpeechResult.completed:
        state = state.copyWith(fallbackVisible: false, fallbackCandidate: null);
      case SpeechResult.superseded:
        break;
    }
  }

  /// The Escape key (design D12): closes the Fallback_View if it is shown,
  /// otherwise cancels the Expansion_Notice if it is shown, otherwise does
  /// nothing. REQ-SPEAK-4, REQ-NOTICE-3.
  void escape() {
    if (state.fallbackVisible) {
      closeFallback();
    } else if (state.noticeVisible) {
      cancelNotice();
    }
  }

  /// The ArrowDown key (E18): Send while the Expansion_Notice is shown,
  /// otherwise an Expand_Action. REQ-TOKENS-4, REQ-NOTICE-2.
  void arrowDown() {
    if (state.noticeVisible) {
      sendNotice();
    } else {
      expand();
    }
  }

  // Sends [tokens] as the newest request and applies its result only if it
  // is still the Pending_Request and was sent for the current
  // Sentence_Tokens (REQ-NARROW-2). A reply's Candidates are re-checked by
  // the Dart_Validator and the first 4 kept (REQ-CHOICE-1); none left, or
  // any failure, clears the Candidate_List and shows the Failure_Message
  // (REQ-FAIL-1). REQ-WAIT-3, REQ-WAIT-6.
  Future<void> _send(List<String> tokens) async {
    final id = ++_requestSeq;
    _pendingId = id;
    state = state.copyWith(thinking: true, failureVisible: false);
    ExpansionResult result;
    try {
      result = await ref.read(expansionClientProvider).expand(tokens);
    } on Object {
      // The client maps errors itself; this keeps a broken client from
      // leaving the Thinking_Indicator up. The error is not kept or logged.
      result = ExpansionFailure(tokens, ExpansionFailureKind.network);
    }
    if (!ref.mounted || id != _pendingId) return;
    final current = sentenceTokens(_session.sentence);
    if (current is! TokensReady || !listEquals(result.tokens, current.tokens)) {
      return;
    }
    _pendingId = null;
    final valid = switch (result) {
      ExpansionReply(:final candidates) =>
        candidates
            .where((c) => isValidCandidate(current.tokens, c))
            .take(maxShownCandidates)
            .toList(),
      ExpansionFailure() => const <String>[],
    };
    state = state.copyWith(
      thinking: false,
      candidates: valid,
      failureVisible: valid.isEmpty,
    );
  }

  // Reads the Notice_Acceptance once (design D10). Only a successful `true`
  // changes the cache, so a late read never undoes a Send; an error leaves
  // it false. REQ-NOTICE-5.
  Future<void> _loadAcceptance() async {
    try {
      if (await ref.read(noticeStoreProvider).isAccepted()) {
        _noticeAccepted = true;
      }
    } on Object {
      // Treated as not stored; the error is not kept or logged.
    }
  }

  // Writes the Notice_Acceptance; a failure resets the cache so the next
  // Expand_Action shows the notice again. REQ-NOTICE-2, REQ-NOTICE-5.
  Future<void> _storeAcceptance() async {
    try {
      await ref.read(noticeStoreProvider).accept();
    } on Object {
      _noticeAccepted = false;
    }
  }

  int _stamp(Duration platformTime) =>
      ref.read(timeBaseProvider).stamp(platformTime);

  // The single place the Sentence reaches the state. When the Sentence
  // changed (design D15), any Pending_Request is abandoned (REQ-WAIT-4), the
  // Failure_Message is cleared (E22) and the Candidate_List is narrowed to
  // the Candidates still valid for the new Sentence_Tokens (REQ-NARROW-1).
  void _publish() {
    final sentence = _session.sentence;
    final current = state;
    if (listEquals(sentence, current.sentence)) {
      state = current.copyWith(
        partialSequence: _session.partialSequence,
        isPressed: _session.isPressed,
      );
      return;
    }
    _pendingId = null;
    state = current.copyWith(
      sentence: sentence,
      partialSequence: _session.partialSequence,
      isPressed: _session.isPressed,
      thinking: false,
      failureVisible: false,
      candidates: current.candidates.isEmpty
          ? current.candidates
          : narrowCandidates(current.candidates, sentenceTokens(sentence)),
    );
  }
}
