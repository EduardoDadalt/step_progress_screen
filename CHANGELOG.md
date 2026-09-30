## 0.1.0

- Initial release.
- `StepProgressScreen.show` runs `ProgressStep`s in sequence on a blocking,
  full-screen route.
- Retry of the failed step, fatal errors through `isFatalError` and "Cancel"
  rethrowing the step error with its original stack trace.
- Customizable error message (`errorMessageBuilder`), error details
  (`onShowDetails`), texts (`StepProgressLabels`) and theme
  (`StepProgressThemeData`).
