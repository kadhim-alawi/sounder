/// The 43-entry International Morse code table from Recommendation
/// ITU-R M.1677-1, Part I, section 1.1: the 26 letters `A`-`Z`, the 10 digits
/// `0`-`9` and the punctuation `. , ? / - ( )`.
///
/// Both the table and its reverse lookup are unmodifiable; any attempt to
/// add, remove or change an entry throws `UnsupportedError`. Lookups never
/// throw. REQ-CODE-1, REQ-CODE-2, REQ-CODE-3, REQ-CODE-10, REQ-PURE-3.
final class CodeTable {
  /// Creates a view of the shared, immutable code table. REQ-CODE-1.
  const CodeTable();

  // The single transcription of the ITU-R M.1677-1 table. Keys are uppercase
  // Supported_Characters. REQ-CODE-1 to REQ-CODE-5.
  static const Map<String, String> _codes = {
    // Letters, section 1.1.1. REQ-CODE-2.
    'A': '.-',
    'B': '-...',
    'C': '-.-.',
    'D': '-..',
    'E': '.',
    'F': '..-.',
    'G': '--.',
    'H': '....',
    'I': '..',
    'J': '.---',
    'K': '-.-',
    'L': '.-..',
    'M': '--',
    'N': '-.',
    'O': '---',
    'P': '.--.',
    'Q': '--.-',
    'R': '.-.',
    'S': '...',
    'T': '-',
    'U': '..-',
    'V': '...-',
    'W': '.--',
    'X': '-..-',
    'Y': '-.--',
    'Z': '--..',
    // Figures, section 1.1.2. REQ-CODE-2.
    '1': '.----',
    '2': '..---',
    '3': '...--',
    '4': '....-',
    '5': '.....',
    '6': '-....',
    '7': '--...',
    '8': '---..',
    '9': '----.',
    '0': '-----',
    // Punctuation, section 1.1.3. REQ-CODE-3.
    '.': '.-.-.-',
    ',': '--..--',
    '?': '..--..',
    '/': '-..-.',
    '-': '-....-',
    '(': '-.--.',
    ')': '-.--.-',
  };

  // Reverse lookup derived from [_codes], so there is one transcription to
  // check. A code collision would leave fewer than 43 entries.
  // REQ-CODE-6, REQ-CODE-10.
  static final Map<String, String> _characters = Map.unmodifiable({
    for (final entry in _codes.entries) entry.value: entry.key,
  });

  /// Unmodifiable map from uppercase Supported_Character to Morse_Code, with
  /// exactly 43 entries. Mutation attempts throw `UnsupportedError`.
  /// REQ-CODE-1, REQ-CODE-2, REQ-CODE-3, REQ-CODE-10.
  Map<String, String> get codes => _codes;

  /// Unmodifiable reverse map from Morse_Code to uppercase Supported_Character,
  /// with exactly 43 entries. Mutation attempts throw `UnsupportedError`.
  /// REQ-CODE-6, REQ-CODE-10.
  Map<String, String> get characters => _characters;

  /// Returns the Morse_Code for a one-character string, or null if
  /// [character] is not a Supported_Character.
  ///
  /// Lowercase `a`-`z` (code units 0x61-0x7A) fold to `A`-`Z` by code unit
  /// arithmetic only; no other character is case folded, so characters such
  /// as `ı` or `ß` return null. Never throws. REQ-CODE-8, REQ-CODE-9.
  String? codeFor(String character) {
    if (character.length != 1) return null;
    var unit = character.codeUnitAt(0);
    if (unit >= 0x61 && unit <= 0x7A) unit -= 0x20;
    return _codes[String.fromCharCode(unit)];
  }

  /// Returns the uppercase Supported_Character for a Morse_Code, or null if
  /// [code] is not one of the 43 codes. Never throws.
  /// REQ-CODE-6, REQ-CODE-7, REQ-CODE-9.
  String? characterFor(String code) => _characters[code];
}
