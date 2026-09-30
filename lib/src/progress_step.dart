import 'package:flutter/widgets.dart';

/// A named step executed by a `StepProgressScreen`.
///
/// [run] may be invoked again when the user taps "Try again", so steps with
/// partial side effects must tolerate being re-executed.
@immutable
class ProgressStep {
  /// Creates a step with a [title], an [icon] and the async [run] callback.
  const ProgressStep({
    required this.title,
    required this.icon,
    required this.run,
  });

  /// Text shown in the step list.
  final String title;

  /// Icon shown in the center of the progress ring while this step runs.
  final IconData icon;

  /// The work performed by this step. Throwing marks the step as failed.
  final Future<void> Function() run;
}
