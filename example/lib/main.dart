import 'package:flutter/material.dart';
import 'package:step_progress_screen/step_progress_screen.dart';

void main() {
  runApp(const ExampleApp());
}

/// Demonstrates the main flows of [StepProgressScreen].
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'step_progress_screen',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}

/// A retryable error, e.g. a network timeout.
class TimeoutError implements Exception {
  @override
  String toString() => 'Connection timed out.';
}

/// A terminal error: retrying the step would never succeed.
class PaymentExpiredError implements Exception {
  @override
  String toString() => 'The payment has expired.';
}

Future<void> _wait() => Future<void>.delayed(const Duration(seconds: 1));

List<ProgressStep> _successfulFlow() => const <ProgressStep>[
  ProgressStep(
    title: 'Connecting to the server',
    icon: Icons.cloud_outlined,
    run: _wait,
  ),
  ProgressStep(
    title: 'Sending the order',
    icon: Icons.upload_outlined,
    run: _wait,
  ),
  ProgressStep(
    title: 'Printing the receipt',
    icon: Icons.print_outlined,
    run: _wait,
  ),
];

List<ProgressStep> _retryableFlow() {
  int attempts = 0;
  return <ProgressStep>[
    const ProgressStep(
      title: 'Connecting to the server',
      icon: Icons.cloud_outlined,
      run: _wait,
    ),
    ProgressStep(
      title: 'Sending the order (fails once)',
      icon: Icons.upload_outlined,
      run: () async {
        await _wait();
        attempts++;
        if (attempts == 1) {
          throw TimeoutError();
        }
      },
    ),
  ];
}

List<ProgressStep> _fatalFlow() => <ProgressStep>[
  ProgressStep(
    title: 'Confirming the payment',
    icon: Icons.payments_outlined,
    run: () async {
      await _wait();
      throw PaymentExpiredError();
    },
  ),
];

/// Lists the demo flows.
class HomePage extends StatelessWidget {
  /// Creates the home page.
  const HomePage({super.key});

  Future<void> _run(BuildContext context, List<ProgressStep> steps) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await StepProgressScreen.show(
        context,
        steps: steps,
        isFatalError: (Object error) => error is PaymentExpiredError,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('All steps completed.')),
      );
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('step_progress_screen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FilledButton(
            onPressed: () => _run(context, _successfulFlow()),
            child: const Text('Successful flow'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => _run(context, _retryableFlow()),
            child: const Text('Flow with a retryable error'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _run(context, _fatalFlow()),
            child: const Text('Flow with a fatal error'),
          ),
        ],
      ),
    );
  }
}
