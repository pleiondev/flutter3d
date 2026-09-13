## 0.1.0

- **The rendering core leaves `flutter3d` (`mcp-03n`).** Scene graph, render
  list, passes, materials and animation move here with no Flutter SDK
  behind them; `flutter3d` re-exports this package and keeps `rootBundle`,
  `dart:ui` and the widgets for its own thin shell.
