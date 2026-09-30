# step_progress_screen

A blocking, full-screen progress view that runs async steps in sequence.
Failed steps can be retried, terminal errors close the screen, and error
details are one tap away.

Useful for flows the user must not leave halfway, such as finishing a payment,
syncing data or generating a report.

## Features

- Runs a list of async steps one after another, with an animated progress ring
  and a checklist of steps.
- Blocks the back button until every step finishes or the user cancels.
- **Try again** re-runs only the step that failed.
- **Cancel** closes the screen and rethrows the step error with its original
  stack trace, so the caller handles it like any other exception.
- **Fatal errors**: errors matched by `isFatalError` close the screen
  immediately, without offering a retry that would fail again.
- Customizable error message, error details view, texts and colors.
- Responsive, Material 3 based, and works in light and dark themes.

## Usage

```dart
import 'package:step_progress_screen/step_progress_screen.dart';

Future<void> finishOrder(BuildContext context) async {
  try {
    await StepProgressScreen.show(
      context,
      steps: <ProgressStep>[
        ProgressStep(
          title: 'Sending the order',
          icon: Icons.upload_outlined,
          run: () => api.sendOrder(order),
        ),
        ProgressStep(
          title: 'Printing the receipt',
          icon: Icons.print_outlined,
          run: () => printer.print(order),
        ),
      ],
    );
    // Every step completed.
  } on Exception catch (error) {
    // The user tapped "Cancel" after a failure, or a fatal error happened.
  }
}
```

`show` completes when every step has finished and throws the error of the
failed step when the user cancels. Always open the screen through `show`:
pushing `StepProgressScreen` directly does not rethrow step errors.

Because a step may run more than once, steps with side effects must tolerate
being re-executed.

### Fatal errors

```dart
await StepProgressScreen.show(
  context,
  steps: steps,
  isFatalError: (Object error) => error is PaymentExpiredException,
);
```

### Error message and details

By default the error card shows `error.toString()` and "Show details" opens a
bottom sheet with the error and its stack trace, which can be copied.

```dart
await StepProgressScreen.show(
  context,
  steps: steps,
  errorMessageBuilder: (Object error) => myErrorTranslator(error),
  onShowDetails: (BuildContext context, Object error, StackTrace stackTrace) =>
      showMyErrorDetails(context, error, stackTrace),
  // Or hide the button:
  // showErrorDetails: false,
);
```

### Translating the texts

```dart
await StepProgressScreen.show(
  context,
  steps: steps,
  labels: const StepProgressLabels(
    errorTitle: 'Ocorreu um erro',
    showDetails: 'Ver detalhes',
    retry: 'Tentar novamente',
    cancel: 'Cancelar',
    errorDetailsTitle: 'Detalhes do erro',
    copy: 'Copiar',
  ),
);
```

### Theming

Running steps and buttons use the `ColorScheme` of your theme. To change the
success color or the maximum content width, register a
`StepProgressThemeData`:

```dart
MaterialApp(
  theme: ThemeData(
    extensions: const <ThemeExtension<dynamic>>[
      StepProgressThemeData(
        successColor: Color(0xFF2E7D32),
        maxContentWidth: 480,
      ),
    ],
  ),
);
```

### Other options

| Parameter | Default | Description |
| --- | --- | --- |
| `completionDelay` | 1.5 s | How long the completed state stays visible before closing. |
| `useRootNavigator` | `true` | Pushes the screen on the root navigator. |

## Example

See the [example](example/lib/main.dart) app for successful, retryable and
fatal flows.

## License

MIT. See [LICENSE](LICENSE).
