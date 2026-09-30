import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Visual customization for `StepProgressScreen`, registered as a
/// [ThemeExtension] in [ThemeData.extensions].
///
/// ```dart
/// ThemeData(
///   extensions: const <ThemeExtension<dynamic>>[
///     StepProgressThemeData(successColor: Color(0xFF2E7D32)),
///   ],
/// )
/// ```
@immutable
class StepProgressThemeData extends ThemeExtension<StepProgressThemeData> {
  /// Creates the theme. Omitted values fall back to the defaults resolved by
  /// [StepProgressThemeData.of].
  const StepProgressThemeData({this.successColor, this.maxContentWidth});

  /// Color of the ring and of the check icons for completed steps.
  ///
  /// Defaults to a green tone generated for the current [Brightness].
  final Color? successColor;

  /// Maximum width of the content column. Defaults to 400.
  final double? maxContentWidth;

  static final Map<Brightness, Color> _defaultSuccessColors =
      <Brightness, Color>{};

  /// Returns the theme registered in [context] with every value resolved.
  // Follows the Flutter `Theme.of(context)` convention.
  // ignore: prefer_constructors_over_static_methods
  static StepProgressThemeData of(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final StepProgressThemeData? extension = theme
        .extension<StepProgressThemeData>();
    return StepProgressThemeData(
      successColor:
          extension?.successColor ??
          _defaultSuccessColors.putIfAbsent(
            theme.brightness,
            () => ColorScheme.fromSeed(
              seedColor: const Color(0xFF2E7D32),
              brightness: theme.brightness,
            ).primary,
          ),
      maxContentWidth: extension?.maxContentWidth ?? 400,
    );
  }

  @override
  StepProgressThemeData copyWith({
    Color? successColor,
    double? maxContentWidth,
  }) => StepProgressThemeData(
    successColor: successColor ?? this.successColor,
    maxContentWidth: maxContentWidth ?? this.maxContentWidth,
  );

  @override
  StepProgressThemeData lerp(
    covariant ThemeExtension<StepProgressThemeData>? other,
    double t,
  ) {
    if (other is! StepProgressThemeData) {
      return this;
    }
    return StepProgressThemeData(
      successColor: Color.lerp(successColor, other.successColor, t),
      maxContentWidth: lerpDouble(maxContentWidth, other.maxContentWidth, t),
    );
  }
}
