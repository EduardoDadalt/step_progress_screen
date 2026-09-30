import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_progress_screen/step_progress_screen.dart';

class _FakeFatalError implements Exception {}

class _Opener extends StatelessWidget {
  const _Opener({
    required this.steps,
    this.onDone,
    this.onFailed,
    this.isFatalError,
    this.errorMessageBuilder,
    this.onShowDetails,
    this.showErrorDetails = true,
    this.labels = const StepProgressLabels(),
  });

  final List<ProgressStep> steps;
  final void Function()? onDone;
  final void Function(Object error, StackTrace stackTrace)? onFailed;
  final bool Function(Object error)? isFatalError;
  final ErrorMessageBuilder? errorMessageBuilder;
  final ErrorDetailsCallback? onShowDetails;
  final bool showErrorDetails;
  final StepProgressLabels labels;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            try {
              await StepProgressScreen.show(
                context,
                steps: steps,
                isFatalError: isFatalError,
                errorMessageBuilder: errorMessageBuilder,
                onShowDetails: onShowDetails,
                showErrorDetails: showErrorDetails,
                labels: labels,
              );
              onDone?.call();
            } on Object catch (error, stackTrace) {
              onFailed?.call(error, stackTrace);
            }
          },
          child: const Text('Open'),
        ),
      ),
    );
  }
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _waitForCompletion(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1600));
  await tester.pump(const Duration(milliseconds: 500));
}

ProgressStep _failingStep(Exception error) => ProgressStep(
  title: 'Failing step',
  icon: Icons.dangerous,
  run: () async => throw error,
);

void main() {
  testWidgets('runs the steps in sequence and closes itself when done', (
    WidgetTester tester,
  ) async {
    final Completer<void> step1 = Completer<void>();
    final Completer<void> step2 = Completer<void>();
    final List<String> order = <String>[];
    bool done = false;

    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          steps: <ProgressStep>[
            ProgressStep(
              title: 'First step',
              icon: Icons.looks_one,
              run: () {
                order.add('1');
                return step1.future;
              },
            ),
            ProgressStep(
              title: 'Second step',
              icon: Icons.looks_two,
              run: () {
                order.add('2');
                return step2.future;
              },
            ),
          ],
          onDone: () => done = true,
        ),
      ),
    );
    await _open(tester);

    expect(find.text('First step'), findsOneWidget);
    expect(find.text('Second step'), findsOneWidget);
    expect(order, <String>['1']);

    step1.complete();
    await tester.pump();
    await tester.pump();
    expect(order, <String>['1', '2']);
    expect(done, isFalse);

    step2.complete();
    await _waitForCompletion(tester);
    expect(done, isTrue);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('blocks the back button while running', (
    WidgetTester tester,
  ) async {
    final Completer<void> step = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          steps: <ProgressStep>[
            ProgressStep(
              title: 'Single step',
              icon: Icons.hourglass_empty,
              run: () => step.future,
            ),
          ],
        ),
      ),
    );
    await _open(tester);

    final NavigatorState navigator = tester.state(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Single step'), findsOneWidget);
    expect(find.text('Open'), findsNothing);

    // Completes so the pending future does not leak.
    step.complete();
    await _waitForCompletion(tester);
  });

  testWidgets('on error, Try again re-runs only the failed step', (
    WidgetTester tester,
  ) async {
    int attempts = 0;
    final List<String> order = <String>[];
    bool done = false;

    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          steps: <ProgressStep>[
            ProgressStep(
              title: 'Stable step',
              icon: Icons.looks_one,
              run: () async {
                order.add('stable');
              },
            ),
            ProgressStep(
              title: 'Flaky step',
              icon: Icons.looks_two,
              run: () async {
                attempts++;
                if (attempts == 1) {
                  throw Exception('failed on purpose');
                }
              },
            ),
          ],
          onDone: () => done = true,
        ),
      ),
    );
    await _open(tester);
    await tester.pump();

    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(done, isFalse);

    await tester.tap(find.text('Try again'));
    await _waitForCompletion(tester);

    expect(order, <String>['stable']);
    expect(attempts, 2);
    expect(done, isTrue);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('Cancel closes the screen rethrowing the error with its '
      'original stack trace', (WidgetTester tester) async {
    StackTrace? originalStackTrace;
    Object? caughtError;
    StackTrace? caughtStackTrace;

    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          steps: <ProgressStep>[
            ProgressStep(
              title: 'Failing step',
              icon: Icons.dangerous,
              run: () => Future<void>.sync(() {
                try {
                  throw const FormatException('no network');
                } on FormatException catch (_, stackTrace) {
                  originalStackTrace = stackTrace;
                  rethrow;
                }
              }),
            ),
          ],
          onFailed: (Object error, StackTrace stackTrace) {
            caughtError = error;
            caughtStackTrace = stackTrace;
          },
        ),
      ),
    );
    await _open(tester);
    await tester.pump();

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(caughtError, isA<FormatException>());
    expect(caughtStackTrace.toString(), originalStackTrace.toString());
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('a fatal error closes the screen rethrowing it without offering '
      'Try again', (WidgetTester tester) async {
    int attempts = 0;
    Object? caughtError;

    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          isFatalError: (Object error) => error is _FakeFatalError,
          steps: <ProgressStep>[
            ProgressStep(
              title: 'Terminal step',
              icon: Icons.block,
              run: () {
                attempts++;
                throw _FakeFatalError();
              },
            ),
          ],
          onFailed: (Object error, _) => caughtError = error,
        ),
      ),
    );
    await _open(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // No retry is offered: the screen closes itself rethrowing the error.
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(caughtError, isA<_FakeFatalError>());
    // The terminal step runs a single time (there is no retry loop).
    expect(attempts, 1);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('two quick taps on Try again do not run the step twice', (
    WidgetTester tester,
  ) async {
    int attempts = 0;
    bool done = false;

    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          steps: <ProgressStep>[
            ProgressStep(
              title: 'Flaky step',
              icon: Icons.looks_one,
              run: () async {
                attempts++;
                if (attempts == 1) {
                  throw Exception('failed on purpose');
                }
              },
            ),
          ],
          onDone: () => done = true,
        ),
      ),
    );
    await _open(tester);
    await tester.pump();

    // Two taps at the same position without a frame between them.
    await tester.tap(find.text('Try again'));
    await tester.tap(find.text('Try again'), warnIfMissed: false);
    await _waitForCompletion(tester);

    expect(attempts, 2);
    expect(done, isTrue);
    // The caller screen stays intact (no double pop).
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('does not overflow on a small screen with an error displayed', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          steps: <ProgressStep>[
            ProgressStep(
              title: 'Step 1',
              icon: Icons.looks_one,
              run: () async {},
            ),
            ProgressStep(
              title: 'Step 2',
              icon: Icons.looks_two,
              run: () async {},
            ),
            _failingStep(
              Exception(
                'a reasonably long error message '
                'to take up vertical space on the screen',
              ),
            ),
          ],
        ),
      ),
    );
    await _open(tester);
    await tester.pump();
    await tester.pump();

    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second failure followed by Cancel rethrows the latest error', (
    WidgetTester tester,
  ) async {
    int attempts = 0;
    Object? caughtError;

    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          steps: <ProgressStep>[
            ProgressStep(
              title: 'Always fails',
              icon: Icons.looks_one,
              run: () {
                attempts++;
                throw StateError('failure $attempts');
              },
            ),
          ],
          onFailed: (Object error, _) => caughtError = error,
        ),
      ),
    );
    await _open(tester);
    await tester.pump();

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(attempts, 2);
    expect(caughtError, isA<StateError>());
    expect((caughtError! as StateError).message, 'failure 2');
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('shows error.toString() by default', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          steps: <ProgressStep>[_failingStep(const FormatException('boom'))],
        ),
      ),
    );
    await _open(tester);
    await tester.pump();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('FormatException: boom'), findsOneWidget);
  });

  testWidgets('uses errorMessageBuilder to build the message', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          steps: <ProgressStep>[_failingStep(const FormatException('boom'))],
          errorMessageBuilder: (Object error) => 'Friendly message',
        ),
      ),
    );
    await _open(tester);
    await tester.pump();

    expect(find.text('Friendly message'), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('Show details opens the default sheet with the stack trace', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          steps: <ProgressStep>[_failingStep(const FormatException('boom'))],
        ),
      ),
    );
    await _open(tester);
    await tester.pump();

    expect(find.text('Error details'), findsNothing);

    await tester.tap(find.text('Show details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Error details'), findsOneWidget);
    expect(find.byTooltip('Copy'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is SelectableText &&
            (widget.data?.startsWith('FormatException: boom\n\n') ?? false),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Show details calls onShowDetails with the error and its stack '
      'trace', (WidgetTester tester) async {
    const FormatException error = FormatException('boom');
    Object? receivedError;
    StackTrace? receivedStackTrace;

    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          steps: <ProgressStep>[_failingStep(error)],
          onShowDetails:
              (
                BuildContext context,
                Object error,
                StackTrace stackTrace,
              ) async {
                receivedError = error;
                receivedStackTrace = stackTrace;
              },
        ),
      ),
    );
    await _open(tester);
    await tester.pump();

    await tester.tap(find.text('Show details'));
    await tester.pump();

    expect(receivedError, same(error));
    expect(receivedStackTrace, isNotNull);
    expect(find.text('Error details'), findsNothing);
  });

  testWidgets('hides Show details when showErrorDetails is false', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          steps: <ProgressStep>[_failingStep(const FormatException('boom'))],
          showErrorDetails: false,
        ),
      ),
    );
    await _open(tester);
    await tester.pump();

    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Show details'), findsNothing);
  });

  testWidgets('uses the provided labels', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _Opener(
          steps: <ProgressStep>[_failingStep(const FormatException('boom'))],
          labels: const StepProgressLabels(
            errorTitle: 'Ocorreu um erro',
            showDetails: 'Ver detalhes',
            retry: 'Tentar novamente',
            cancel: 'Cancelar',
          ),
        ),
      ),
    );
    await _open(tester);
    await tester.pump();

    expect(find.text('Ocorreu um erro'), findsOneWidget);
    expect(find.text('Ver detalhes'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
  });

  testWidgets('uses the success color from StepProgressThemeData', (
    WidgetTester tester,
  ) async {
    const Color successColor = Color(0xFF123456);
    final Completer<void> secondStep = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[
            StepProgressThemeData(successColor: successColor),
          ],
        ),
        home: _Opener(
          steps: <ProgressStep>[
            ProgressStep(title: 'Done', icon: Icons.check, run: () async {}),
            ProgressStep(
              title: 'Running',
              icon: Icons.hourglass_empty,
              run: () => secondStep.future,
            ),
          ],
        ),
      ),
    );
    await _open(tester);
    await tester.pump();

    final Icon doneIcon = tester.widget(find.byIcon(Icons.check_circle));
    expect(doneIcon.color, successColor);

    secondStep.complete();
    await _waitForCompletion(tester);
  });

  test('StepProgressThemeData.lerp interpolates its values', () {
    const StepProgressThemeData a = StepProgressThemeData(
      successColor: Color(0xFF000000),
      maxContentWidth: 100,
    );
    const StepProgressThemeData b = StepProgressThemeData(
      successColor: Color(0xFFFFFFFF),
      maxContentWidth: 300,
    );

    final StepProgressThemeData middle = a.lerp(b, 0.5);

    expect(middle.maxContentWidth, 200);
    expect(
      middle.successColor,
      Color.lerp(a.successColor, b.successColor, 0.5),
    );
    expect(a.copyWith(maxContentWidth: 50).successColor, a.successColor);
  });
}
