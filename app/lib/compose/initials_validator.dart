// Dart_Validator: the Initials_Validator of REQ-VALIDATOR-1, written in pure
// Dart for the app. The TS_Validator in `worker/src/validator.ts` runs the
// same algorithm, and both read `fixtures/expansion_validator.json`
// (REQ-VALIDATOR-2).
//
// Every function here works on UTF-16 code units (`codeUnitAt`), uses no
// regex with Unicode classes and no `toLowerCase`, so the two runtimes cannot
// differ (E1, E5). Every function is pure: no I/O, no clock, no logging
// (REQ-VALIDATOR-4, REQ-COMPOSE-1).

/// Maximum Candidate length in UTF-16 code units after E2 trimming
/// (REQ-VALIDATOR-1 (a), E5).
const int maxCandidateLength = 200;

/// Maximum number of Tokens in a Token_List (REQ-VALIDATOR-1, REQ-EXPAND-4).
const int _maxTokens = 12;

/// Maximum number of letters in one Token (REQ-VALIDATOR-1, REQ-EXPAND-4).
const int _maxTokenLength = 8;

/// True when [codeUnit] is one E2 whitespace character: U+0009 to U+000D or
/// U+0020. Other Unicode spaces are not separators (REQ-VALIDATOR-1 (b), E2).
bool isE2Space(int codeUnit) =>
    (codeUnit >= 0x09 && codeUnit <= 0x0d) || codeUnit == 0x20;

/// True when [codeUnit] is one of the strip characters `. , ! ? ; : " ( )`
/// (REQ-VALIDATOR-1 (c), E4). Curly quotes are not strip characters.
bool isStripChar(int codeUnit) {
  switch (codeUnit) {
    case 0x2e: // .
    case 0x2c: // ,
    case 0x21: // !
    case 0x3f: // ?
    case 0x3b: // ;
    case 0x3a: // :
    case 0x22: // "
    case 0x28: // (
    case 0x29: // )
      return true;
    default:
      return false;
  }
}

/// True when [codeUnit] is one ASCII letter, `A`-`Z` or `a`-`z`
/// (REQ-VALIDATOR-1, E1).
bool isAsciiLetter(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7a);

bool _isJoiner(int codeUnit) =>
    codeUnit == 0x27 /* ' */ ||
    codeUnit == 0x2019 /* ’ */ ||
    codeUnit == 0x2d /* - */;

/// ASCII lowercasing: maps only U+0041..U+005A to U+0061..U+007A and keeps
/// every other code unit (REQ-VALIDATOR-1 (d), E1).
String asciiLower(String s) {
  final units = List<int>.of(s.codeUnits);
  for (var i = 0; i < units.length; i++) {
    final u = units[i];
    if (u >= 0x41 && u <= 0x5a) units[i] = u + 0x20;
  }
  return String.fromCharCodes(units);
}

/// [s] with E2 whitespace removed from both ends (REQ-VALIDATOR-1 (a), E2,
/// E5).
String trimE2(String s) {
  var start = 0;
  var end = s.length;
  while (start < end && isE2Space(s.codeUnitAt(start))) {
    start++;
  }
  while (end > start && isE2Space(s.codeUnitAt(end - 1))) {
    end--;
  }
  return s.substring(start, end);
}

/// Splits [s] on runs of E2 whitespace. Leading, trailing and repeated
/// whitespace create no empty Words (REQ-VALIDATOR-1 (b), E2).
List<String> splitWords(String s) {
  final words = <String>[];
  var start = -1;
  for (var i = 0; i < s.length; i++) {
    if (isE2Space(s.codeUnitAt(i))) {
      if (start >= 0) {
        words.add(s.substring(start, i));
        start = -1;
      }
    } else if (start < 0) {
      start = i;
    }
  }
  if (start >= 0) words.add(s.substring(start));
  return words;
}

/// The Stripped_Word: [word] with strip characters removed repeatedly from
/// both ends until neither end is a strip character (REQ-VALIDATOR-1 (c),
/// E4).
String stripWord(String word) {
  var start = 0;
  var end = word.length;
  while (start < end && isStripChar(word.codeUnitAt(start))) {
    start++;
  }
  while (end > start && isStripChar(word.codeUnitAt(end - 1))) {
    end--;
  }
  return word.substring(start, end);
}

/// True when [core] is non-empty, made only of ASCII letters, apostrophes
/// (U+0027, U+2019) and hyphens (U+002D), and every apostrophe and hyphen
/// has an ASCII letter directly before and after it (REQ-VALIDATOR-1 (c),
/// E3).
bool isWellFormedWord(String core) {
  final n = core.length;
  if (n == 0) return false;
  for (var j = 0; j < n; j++) {
    final u = core.codeUnitAt(j);
    if (isAsciiLetter(u)) continue;
    if (!_isJoiner(u)) return false;
    if (j == 0 || j == n - 1) return false;
    if (!isAsciiLetter(core.codeUnitAt(j - 1))) return false;
    if (!isAsciiLetter(core.codeUnitAt(j + 1))) return false;
  }
  return true;
}

/// True when [tokens] is a Token_List: 1 to 12 strings of 1 to 8 ASCII
/// letters (REQ-VALIDATOR-1).
bool _isTokenList(List<String> tokens) {
  if (tokens.isEmpty || tokens.length > _maxTokens) return false;
  for (final t in tokens) {
    if (t.isEmpty || t.length > _maxTokenLength) return false;
    for (var i = 0; i < t.length; i++) {
      if (!isAsciiLetter(t.codeUnitAt(i))) return false;
    }
  }
  return true;
}

/// The Initials_Validator rule (REQ-VALIDATOR-1). Accepts [candidate] for
/// [tokens] only when (a) the E2-trimmed Candidate is at most 200 UTF-16 code
/// units, (b) it has exactly one Word per Token, (c) every Stripped_Word is
/// non-empty and well formed (E3), and (d) every Stripped_Word,
/// ASCII-lowercased, starts with its Token, ASCII-lowercased. Returns false
/// when [tokens] is not a Token_List. Pure, with no I/O, clock or logging
/// (REQ-VALIDATOR-4).
bool isValidCandidate(List<String> tokens, String candidate) {
  if (!_isTokenList(tokens)) return false;
  final t = trimE2(candidate);
  if (t.length > maxCandidateLength) return false;
  final words = splitWords(t);
  if (words.length != tokens.length) return false;
  for (var i = 0; i < words.length; i++) {
    final core = stripWord(words[i]);
    if (!isWellFormedWord(core)) return false;
    if (!asciiLower(core).startsWith(asciiLower(tokens[i]))) return false;
  }
  return true;
}
