import 'package:flutter/painting.dart';

/// The Key_Screen palette: white text on dark backgrounds, each background
/// with WCAG 2.x relative luminance at most 0.2 and a contrast ratio of at
/// least 7:1 with white (design "Palette"). REQ-A11Y-3.
abstract final class SounderColors {
  /// All text, including the Sentence, the Placeholder, the
  /// Partial_Sequence, control labels and the Fallback_View notice
  /// (luminance 1.0). REQ-A11Y-3.
  static const Color text = Color(0xFFFFFFFF);

  /// Screen and Fallback_View background (luminance 0.006, 18.7:1).
  /// REQ-A11Y-3.
  static const Color screenBackground = Color(0xFF121212);

  /// On_Screen_Key released and button background (luminance 0.013,
  /// 16.7:1). REQ-A11Y-3.
  static const Color released = Color(0xFF1E1E1E);

  /// On_Screen_Key pressed background (luminance 0.072, 8.6:1).
  /// REQ-A11Y-3.
  static const Color pressed = Color(0xFF0D47A1);
}
