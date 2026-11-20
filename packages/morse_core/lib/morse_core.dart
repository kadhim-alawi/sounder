/// Pure Dart International Morse code engine for Sounder (ITU-R M.1677-1).
///
/// This single import exposes the whole public API: the code table, the
/// encoder, the decoder and the format error. REQ-PURE-5.
library;

export 'src/code_table.dart';
export 'src/morse_decoder.dart';
export 'src/morse_encoder.dart';
export 'src/morse_format_exception.dart';
