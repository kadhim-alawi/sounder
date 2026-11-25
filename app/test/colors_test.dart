import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:sounder/ui/sounder_colors.dart';

/// WCAG 2.x linearisation of one 8-bit sRGB channel.
double _linear(int channel) {
  final c = channel / 255;
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG 2.x relative luminance, computed from the colour's 8-bit channels.
double relativeLuminance(Color color) {
  final argb = color.toARGB32();
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return 0.2126 * _linear(r) + 0.7152 * _linear(g) + 0.0722 * _linear(b);
}

/// WCAG 2.x contrast ratio, lighter luminance on top.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('REQ-A11Y-3: WCAG formula sanity', () {
    test('REQ-A11Y-3: white has luminance 1.0 and black 0.0', () {
      expect(relativeLuminance(const Color(0xFFFFFFFF)), closeTo(1.0, 1e-9));
      expect(relativeLuminance(const Color(0xFF000000)), closeTo(0.0, 1e-9));
    });

    test('REQ-A11Y-3: white on black is 21:1', () {
      expect(
        contrastRatio(const Color(0xFFFFFFFF), const Color(0xFF000000)),
        closeTo(21.0, 1e-9),
      );
    });
  });

  test('REQ-A11Y-3: text colour is white', () {
    expect(SounderColors.text.toARGB32(), 0xFFFFFFFF);
  });

  const backgrounds = <String, Color>{
    'screenBackground': SounderColors.screenBackground,
    'released': SounderColors.released,
    'pressed': SounderColors.pressed,
  };

  for (final entry in backgrounds.entries) {
    test('REQ-A11Y-3: ${entry.key} has luminance at most 0.2', () {
      expect(relativeLuminance(entry.value), lessThanOrEqualTo(0.2));
    });

    test('REQ-A11Y-3: text on ${entry.key} has contrast at least 7:1', () {
      expect(
        contrastRatio(SounderColors.text, entry.value),
        greaterThanOrEqualTo(7.0),
      );
    });
  }
}
