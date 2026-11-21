// Example use of the morse_core public API. REQ-PURE-5, REQ-PURE-6.
import 'package:morse_core/morse_core.dart';

void main() {
  const table = CodeTable();
  const encoder = MorseEncoder();
  const decoder = MorseDecoder();

  // Look up one code. REQ-CODE-2.
  print('A is ${table.codeFor('A')}');

  // Encode and decode a phrase. REQ-ENC-9, REQ-DEC-8.
  final morse = encoder.encode('hello world');
  print('encode: $morse');
  print('decode: ${decoder.decode(morse)}');

  // Invalid input raises MorseFormatException. Print only its message,
  // never the input or the exception source. REQ-ERR-3, REQ-ERR-8.
  try {
    decoder.decode('... ...... ...');
  } on MorseFormatException catch (e) {
    print('error: ${e.message}');
  }
}
