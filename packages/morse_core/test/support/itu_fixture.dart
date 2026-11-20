/// Independent transcription of the Morse code table from Recommendation
/// ITU-R M.1677-1 (10/2009), Part I, sections 1.1.1 (letters), 1.1.2
/// (figures) and 1.1.3 (the seven punctuation marks in scope).
///
/// Tests compare `CodeTable.codes` against this map. It deliberately does not
/// import `package:morse_core`, so a mistake in `lib/` cannot leak into the
/// expected values.
///
/// Exactly 43 entries: 26 letters, 10 digits, 7 punctuation marks.
/// REQ-TEST-3, REQ-CODE-1, REQ-CODE-2, REQ-CODE-3.
const Map<String, String> ituFixture = <String, String>{
  // Section 1.1.1: letters.
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

  // Section 1.1.2: figures.
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

  // Section 1.1.3: punctuation marks in scope.
  '.': '.-.-.-', // Full stop (period)
  ',': '--..--', // Comma
  '?': '..--..', // Question mark
  '/': '-..-.', // Fraction bar or division sign
  '-': '-....-', // Hyphen or dash
  '(': '-.--.', // Left-hand bracket (parenthesis)
  ')': '-.--.-', // Right-hand bracket (parenthesis)
};
