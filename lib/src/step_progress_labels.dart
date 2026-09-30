import 'package:flutter/foundation.dart';

/// The texts displayed by a `StepProgressScreen`.
///
/// Defaults are in English; pass a custom instance to translate them.
@immutable
class StepProgressLabels {
  /// Creates the labels, using English defaults for omitted values.
  const StepProgressLabels({
    this.errorTitle = 'Something went wrong',
    this.showDetails = 'Show details',
    this.retry = 'Try again',
    this.cancel = 'Cancel',
    this.errorDetailsTitle = 'Error details',
    this.copy = 'Copy',
  });

  /// Title of the error card shown when a step fails.
  final String errorTitle;

  /// Button that opens the technical error details.
  final String showDetails;

  /// Button that re-runs the failed step.
  final String retry;

  /// Button that closes the screen rethrowing the error.
  final String cancel;

  /// Title of the default error details bottom sheet.
  final String errorDetailsTitle;

  /// Tooltip of the copy button in the default error details bottom sheet.
  final String copy;
}
