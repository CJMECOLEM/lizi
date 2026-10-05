import 'package:flutter/material.dart';

import '../expiry/expiry_math.dart';

/// Gray for expired, red for one month or less, yellow for two months or
/// less.
class ExpiryStyle {
  const ExpiryStyle({required this.background, required this.foreground, required this.accent, required this.label});

  final Color background;
  final Color foreground;
  final Color accent;
  final String label;

  static ExpiryStyle of(ExpiryLevel level, ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return switch (level) {
      ExpiryLevel.expired => ExpiryStyle(
          background: dark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0),
          foreground: dark ? const Color(0xFFBDBDBD) : const Color(0xFF616161),
          accent: Colors.grey,
          label: '已过期',
        ),
      ExpiryLevel.withinOneMonth => ExpiryStyle(
          background: dark ? const Color(0xFF5C1A1A) : const Color(0xFFFFCDD2),
          foreground: dark ? const Color(0xFFFFCDD2) : const Color(0xFFB71C1C),
          accent: Colors.red,
          label: '1个月内',
        ),
      ExpiryLevel.withinTwoMonths => ExpiryStyle(
          background: dark ? const Color(0xFF5A4A00) : const Color(0xFFFFF59D),
          foreground: dark ? const Color(0xFFFFF59D) : const Color(0xFF795548),
          accent: Colors.amber,
          label: '2个月内',
        ),
      ExpiryLevel.ok => ExpiryStyle(
          background: scheme.surface,
          foreground: scheme.onSurface,
          accent: Colors.green,
          label: '正常',
        ),
    };
  }
}
