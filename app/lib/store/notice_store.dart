import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether the user has accepted the Expansion_Notice.
///
/// Both methods may throw. Callers treat a failed read as "not accepted"
/// and ignore a failed write (REQ-NOTICE-5).
abstract interface class NoticeStore {
  /// Whether a Notice_Acceptance is stored (REQ-NOTICE-2). May throw.
  Future<bool> isAccepted();

  /// Stores the Notice_Acceptance after the user activates Send
  /// (REQ-NOTICE-2). May throw.
  Future<void> accept();
}

/// [NoticeStore] in browser storage through [SharedPreferencesAsync].
///
/// Stores one entry only: [acceptedKey] with the value `true`. Cancel stores
/// nothing (REQ-NOTICE-3). Any storage error, including a missing platform
/// implementation, surfaces from [isAccepted] or [accept] rather than from
/// the constructor, so the caller can handle it (REQ-NOTICE-5).
final class SharedPreferencesNoticeStore implements NoticeStore {
  /// Creates a store. [preferences] is created on first use when omitted.
  SharedPreferencesNoticeStore({this._preferences});

  /// The storage key of the Notice_Acceptance (REQ-NOTICE-2).
  static const String acceptedKey = 'sounder.expansion_notice_accepted';

  SharedPreferencesAsync? _preferences;

  // The SharedPreferencesAsync constructor throws a StateError when no
  // platform implementation is registered, so it is created inside the
  // methods that are allowed to throw (REQ-NOTICE-5).
  SharedPreferencesAsync get _prefs =>
      _preferences ??= SharedPreferencesAsync();

  /// Returns `true` only when [acceptedKey] holds `true` (REQ-NOTICE-2,
  /// REQ-NOTICE-5). May throw.
  @override
  Future<bool> isAccepted() async =>
      (await _prefs.getBool(acceptedKey)) ?? false;

  /// Writes [acceptedKey] = `true` and nothing else (REQ-NOTICE-2,
  /// REQ-NOTICE-3). May throw.
  @override
  Future<void> accept() async => _prefs.setBool(acceptedKey, true);
}
