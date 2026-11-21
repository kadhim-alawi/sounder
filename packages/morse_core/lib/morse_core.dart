/// Pure Dart International Morse code engine for Sounder (ITU-R M.1677-1).
///
/// This single import exposes the whole public API, so a consumer never
/// imports a file under `lib/src/`. REQ-PURE-5.
///
/// - `CodeTable`: the 43 ITU-R M.1677-1 codes and their reverse lookup.
///   REQ-CODE-1.
/// - `MorseEncoder`: Plain_Text to Encoded_Text. REQ-ENC-1.
/// - `MorseDecoder`: Encoded_Text to uppercase Plain_Text. REQ-DEC-1.
/// - `MorseFormatException`: the error raised for invalid input. It carries
///   the offending character or token and its position, never the full
///   input. REQ-ERR-8.
///
/// The package has no runtime dependencies, imports no Flutter or I/O
/// library, and every operation is a pure, synchronous function of its
/// argument. REQ-PURE-1, REQ-PURE-2, REQ-PURE-3.
///
/// ```dart
/// const encoder = MorseEncoder();
/// const decoder = MorseDecoder();
/// final morse = encoder.encode('hello world');
/// // .... . .-.. .-.. --- / .-- --- .-. .-.. -..
/// final text = decoder.decode(morse); // HELLO WORLD
/// ```
library;

export 'src/code_table.dart';
export 'src/morse_decoder.dart';
export 'src/morse_encoder.dart';
export 'src/morse_format_exception.dart';
