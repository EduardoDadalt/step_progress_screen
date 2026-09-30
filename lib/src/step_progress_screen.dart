import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:step_progress_screen/src/progress_step.dart';
import 'package:step_progress_screen/src/step_progress_labels.dart';
import 'package:step_progress_screen/src/step_progress_theme.dart';

/// Converts a step error into the message shown to the user.
typedef ErrorMessageBuilder = String Function(Object error);

/// Opens a custom view with the technical details of a step error.
typedef ErrorDetailsCallback =
    Future<void> Function(
      BuildContext context,
      Object error,
      StackTrace stackTrace,
    );

enum _StepState { pending, running, done, failed }

class _StepFailure {
  const _StepFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

/// A blocking, full-screen view that runs [steps] in sequence showing the
/// progress of each one.
///
/// ## Entry point
///
/// Use [StepProgressScreen.show] to display this screen. Pushing it directly
/// with a `Navigator` does not interpret the error result returned by the
/// route, so step exceptions would be silently swallowed.
///
/// ## Retry
///
/// When a step fails, the user can tap "Try again": the screen invokes
/// [ProgressStep.run] again only for the step that failed. Steps with partial
/// side effects must tolerate being re-executed.
///
/// The error message comes from [errorMessageBuilder]; "Show details" opens
/// [onShowDetails] or, when it is null, a bottom sheet with the error and its
/// stack trace.
///
/// The user cannot leave the screen (it uses a [PopScope]) until every step
/// completes or until they tap "Cancel", which closes the screen rethrowing
/// the error.
class StepProgressScreen extends StatefulWidget {
  /// Creates the screen. Prefer [StepProgressScreen.show].
  const StepProgressScreen({
    required this.steps,
    this.isFatalError,
    this.errorMessageBuilder,
    this.onShowDetails,
    this.showErrorDetails = true,
    this.labels = const StepProgressLabels(),
    this.completionDelay = const Duration(milliseconds: 1500),
    super.key,
  });

  /// The steps executed in order. Must not be empty.
  final List<ProgressStep> steps;

  /// When a step throws an error for which [isFatalError] returns `true`, the
  /// screen does NOT offer "Try again": it closes immediately, rethrowing the
  /// error to the caller. Use it for terminal errors (e.g. an expired
  /// payment), where re-running the step would only repeat the same failure.
  final bool Function(Object error)? isFatalError;

  /// Builds the message shown when a step fails. Defaults to
  /// `error.toString()`.
  final ErrorMessageBuilder? errorMessageBuilder;

  /// Opens the technical details of an error. Defaults to a bottom sheet with
  /// the error and its stack trace.
  final ErrorDetailsCallback? onShowDetails;

  /// Whether the "Show details" button is displayed.
  final bool showErrorDetails;

  /// The texts displayed by the screen.
  final StepProgressLabels labels;

  /// How long the completed state stays visible before the screen closes.
  final Duration completionDelay;

  /// Pushes the screen and completes when every step has finished.
  ///
  /// Throws the error of the failed step, with its original stack trace, when
  /// the user taps "Cancel" or when [isFatalError] returns `true`.
  static Future<void> show(
    BuildContext context, {
    required List<ProgressStep> steps,
    bool Function(Object error)? isFatalError,
    ErrorMessageBuilder? errorMessageBuilder,
    ErrorDetailsCallback? onShowDetails,
    bool showErrorDetails = true,
    StepProgressLabels labels = const StepProgressLabels(),
    Duration completionDelay = const Duration(milliseconds: 1500),
    bool useRootNavigator = true,
  }) async {
    final Object? result =
        await Navigator.of(
          context,
          rootNavigator: useRootNavigator,
        ).push<Object?>(
          MaterialPageRoute<Object?>(
            fullscreenDialog: true,
            builder: (BuildContext context) => StepProgressScreen(
              steps: steps,
              isFatalError: isFatalError,
              errorMessageBuilder: errorMessageBuilder,
              onShowDetails: onShowDetails,
              showErrorDetails: showErrorDetails,
              labels: labels,
              completionDelay: completionDelay,
            ),
          ),
        );
    if (result is _StepFailure) {
      Error.throwWithStackTrace(result.error, result.stackTrace);
    }
  }

  @override
  State<StepProgressScreen> createState() => _StepProgressScreenState();
}

class _StepProgressScreenState extends State<StepProgressScreen> {
  int currentStep = 0;
  Object? error;
  StackTrace? errorStackTrace;

  /// Prevents reentrancy: two quick taps on "Try again" must not start two
  /// concurrent [_runSteps] loops.
  bool _running = false;

  bool get completed => currentStep >= widget.steps.length;

  @override
  void initState() {
    super.initState();
    assert(widget.steps.isNotEmpty, 'Provide at least one step.');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runSteps());
    });
  }

  Future<void> _runSteps() async {
    if (_running) {
      return;
    }
    _running = true;
    try {
      while (currentStep < widget.steps.length) {
        try {
          await widget.steps[currentStep].run();
        } catch (stepError, stackTrace) {
          if (!mounted) {
            return;
          }
          if (widget.isFatalError?.call(stepError) ?? false) {
            // Terminal error: close rethrowing it instead of offering
            // "Try again", which would only repeat the same failure.
            Navigator.of(context).pop(_StepFailure(stepError, stackTrace));
            return;
          }
          setState(() {
            error = stepError;
            errorStackTrace = stackTrace;
          });
          return;
        }
        if (!mounted) {
          return;
        }
        setState(() {
          currentStep++;
        });
      }

      // Let the user see the completed state before closing.
      await Future<void>.delayed(widget.completionDelay);
      if (!mounted) {
        return;
      }
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        Navigator.of(context).pop();
      }
    } finally {
      _running = false;
    }
  }

  void _retry() {
    setState(() {
      error = null;
      errorStackTrace = null;
    });
    unawaited(_runSteps());
  }

  void _cancel() {
    Navigator.of(context).pop(_StepFailure(error!, errorStackTrace!));
  }

  void _showDetails() {
    final ErrorDetailsCallback? onShowDetails = widget.onShowDetails;
    if (onShowDetails != null) {
      unawaited(onShowDetails(context, error!, errorStackTrace!));
      return;
    }
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (BuildContext context) => _ErrorDetailsSheet(
          error: error!,
          stackTrace: errorStackTrace!,
          labels: widget.labels,
        ),
      ),
    );
  }

  _StepState _stateOf(int index) {
    if (index < currentStep) {
      return _StepState.done;
    }
    if (index > currentStep) {
      return _StepState.pending;
    }
    if (error != null) {
      return _StepState.failed;
    }
    return _StepState.running;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final StepProgressThemeData stepTheme = StepProgressThemeData.of(context);
    final Color successColor = stepTheme.successColor!;
    final Color ringColor = error != null
        ? theme.colorScheme.error
        : completed
        ? successColor
        : theme.colorScheme.primary;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: stepTheme.maxContentWidth!,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _ProgressRing(
                        progress: currentStep / widget.steps.length,
                        color: ringColor,
                        running: !completed && error == null,
                        icon: completed
                            ? Icons.check
                            : error != null
                            ? Icons.error_outline
                            : widget.steps[currentStep].icon,
                        iconKey: completed
                            ? 'completed'
                            : error != null
                            ? 'error'
                            : 'step_$currentStep',
                      ),
                      const SizedBox(height: 40),
                      ...List<Widget>.generate(
                        widget.steps.length,
                        (int index) => _StepRow(
                          step: widget.steps[index],
                          state: _stateOf(index),
                          successColor: successColor,
                        ),
                      ),
                      if (error != null)
                        _ErrorWithActions(
                          message:
                              widget.errorMessageBuilder?.call(error!) ??
                              error.toString(),
                          labels: widget.labels,
                          onShowDetails: widget.showErrorDetails
                              ? _showDetails
                              : null,
                          onRetry: _retry,
                          onCancel: _cancel,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    required this.progress,
    required this.color,
    required this.running,
    required this.icon,
    required this.iconKey,
  });

  final double progress;
  final Color color;
  final bool running;
  final IconData icon;
  final String iconKey;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: SizedBox(
        width: 160,
        height: 160,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CircularProgressIndicator(
              value: 1,
              strokeWidth: 8,
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            if (running)
              CircularProgressIndicator(
                strokeWidth: 8,
                color: color.withValues(alpha: 0.3),
              ),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (BuildContext context, double value, Widget? _) =>
                  CircularProgressIndicator(
                    value: value,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    color: color,
                  ),
            ),
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder:
                    (Widget child, Animation<double> animation) =>
                        ScaleTransition(
                          scale: animation,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        ),
                child: Icon(
                  icon,
                  key: ValueKey<String>(iconKey),
                  size: 64,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.state,
    required this.successColor,
  });

  final ProgressStep step;
  final _StepState state;
  final Color successColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color disabledColor = theme.colorScheme.onSurface.withValues(
      alpha: 0.38,
    );

    final Widget indicator = switch (state) {
      _StepState.done => Icon(Icons.check_circle, color: successColor),
      _StepState.running => const Padding(
        padding: EdgeInsets.all(2),
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
      _StepState.failed => Icon(Icons.error, color: theme.colorScheme.error),
      _StepState.pending => Icon(Icons.circle_outlined, color: disabledColor),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          SizedBox(width: 28, height: 28, child: indicator),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              step.title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: state == _StepState.pending ? disabledColor : null,
                fontWeight: state == _StepState.running
                    ? FontWeight.bold
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorWithActions extends StatelessWidget {
  const _ErrorWithActions({
    required this.message,
    required this.labels,
    required this.onShowDetails,
    required this.onRetry,
    required this.onCancel,
  });

  final String message;
  final StepProgressLabels labels;
  final VoidCallback? onShowDetails;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            liveRegion: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: const BorderRadius.all(Radius.circular(12)),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  onShowDetails != null ? 8 : 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      labels.errorTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onErrorContainer,
                      ),
                    ),
                    if (onShowDetails != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: onShowDetails,
                          style: TextButton.styleFrom(
                            foregroundColor: colors.onErrorContainer,
                          ),
                          child: Text(labels.showDetails),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(labels.retry),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onCancel, child: Text(labels.cancel)),
        ],
      ),
    );
  }
}

class _ErrorDetailsSheet extends StatelessWidget {
  const _ErrorDetailsSheet({
    required this.error,
    required this.stackTrace,
    required this.labels,
  });

  final Object error;
  final StackTrace stackTrace;
  final StepProgressLabels labels;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String details = '$error\n\n$stackTrace';

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      labels.errorDetailsTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: labels.copy,
                    icon: const Icon(Icons.copy),
                    onPressed: () => unawaited(
                      Clipboard.setData(ClipboardData(text: details)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    details,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
