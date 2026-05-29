import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';

void main() {
  group('MeowColors presets', () {
    test('cozy preserves the current hardcoded palette', () {
      const c = MeowColors.cozy;
      expect(c.background, const Color(0xFF1A1410));
      expect(c.surface, const Color(0xF2241B14));
      expect(c.accent, const Color(0xFFD4A574));
      expect(c.textPrimary, const Color(0xFFF5E6D3));
      expect(c.textDim, const Color(0x99F5E6D3));
      expect(c.border, const Color(0x55D4A574));
      expect(c.myBubble, const Color(0x33D4A574));
      expect(c.peerBubble, const Color(0x55241B14));
      expect(c.backgroundGradient, isNull);
      expect(c.glassBlur, 0);
      expect(c.titleFontFamily, isNull);
    });

    test('noir is black + gold with a serif title font', () {
      const c = MeowColors.noir;
      expect(c.background, const Color(0xFF000000));
      expect(c.accent, const Color(0xFFD4AF37));
      expect(c.titleFontFamily, isNotNull);
      expect(c.glassBlur, 0);
    });

    test('aurora has a gradient and glass blur', () {
      const c = MeowColors.aurora;
      expect(c.backgroundGradient, isNotNull);
      expect(c.glassBlur, greaterThan(0));
      expect(c.accent, const Color(0xFF7DF9C2));
    });
  });

  group('MeowColors lerp/copyWith', () {
    test('lerp at t=0 returns this palette values', () {
      const a = MeowColors.cozy;
      const b = MeowColors.noir;
      final mid = a.lerp(b, 0.0);
      expect(mid.accent, a.accent);
    });

    test('lerp at t=1 returns the other palette values', () {
      const a = MeowColors.cozy;
      const b = MeowColors.noir;
      final mid = a.lerp(b, 1.0);
      expect(mid.accent, b.accent);
    });

    test('copyWith overrides one slot only', () {
      const c = MeowColors.cozy;
      final c2 = c.copyWith(accent: const Color(0xFF112233));
      expect(c2.accent, const Color(0xFF112233));
      expect(c2.background, c.background);
    });
  });

  group('MeowThemeId', () {
    test('fromName maps known names and falls back to cozy', () {
      expect(MeowThemeId.fromName('noir'), MeowThemeId.noir);
      expect(MeowThemeId.fromName('aurora'), MeowThemeId.aurora);
      expect(MeowThemeId.fromName('bogus'), MeowThemeId.cozy);
      expect(MeowThemeId.fromName(null), MeowThemeId.cozy);
    });

    test('each id carries its preset colors', () {
      expect(MeowThemeId.cozy.colors, MeowColors.cozy);
      expect(MeowThemeId.noir.colors, MeowColors.noir);
      expect(MeowThemeId.aurora.colors, MeowColors.aurora);
    });
  });
}
