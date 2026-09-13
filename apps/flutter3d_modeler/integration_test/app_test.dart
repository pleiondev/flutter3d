/// A real e2e smoke test: `ModelerApp` on the actual platform rather than the
/// headless `TestWidgetsFlutterBinding` every other test here runs under.
///
///     flutter test integration_test/app_test.dart -d macos
///
/// **Why this exists beside the widget tests, not instead of them.** Every
/// other test in `test/` pumps one component — the shell, the status line,
/// the gizmo — at a size it names, which is fast and precise about which
/// widget broke. None of them ever construct the real `ModelerApp`, open a
/// real `GraphicsDevice`, or run in the actual window a person sees, so a
/// wiring mistake between `main()` and the pieces those tests already cover
/// individually has nowhere to be caught. This is that one place.
///
/// **Polled, not settled.** `pumpAndSettle` gives up once nothing is left to
/// pump, and a live viewport drives its own frames outside Flutter's ticker —
/// waiting for "nothing pending" here could mean waiting for the render loop
/// to stop, which it will not. A bounded poll for `ModelerReady`'s own shell
/// to appear is what every other async-boot test in this file style should
/// reach for instead.
library;

import 'package:flutter3d_modeler/main.dart';
import 'package:flutter3d_modeler/src/ui/shell.dart';
import 'package:flutter3d_modeler/src/ui/status_line.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Pumps until [ModelerShell] appears or [tries] runs out — the device has
/// opened and the cubit has moved past `ModelerOpening`.
Future<bool> _pumpUntilReady(
  WidgetTester tester, {
  int tries = 100,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < tries; i++) {
    await tester.pump(step);
    if (find.byType(ModelerShell).evaluate().isNotEmpty) return true;
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app opens for real and the shell lays out with no '
      'overflow', (WidgetTester tester) async {
    await tester.pumpWidget(const ModelerApp());

    final bool ready = await _pumpUntilReady(tester);
    expect(
      ready,
      isTrue,
      reason:
          'never reached ModelerReady — the device did not open, or '
          'took longer than this test waits',
    );

    // Mutation: a layout change that overflows the shell at the window's
    // real size — this is the one test in the suite that runs at whatever
    // size the actual macOS window opens at, rather than a size a test
    // chose.
    expect(
      tester.takeException(),
      isNull,
      reason: 'the shell overflowed opening the app for real',
    );

    expect(find.byType(ModelerShell), findsOneWidget);
    expect(find.byType(StatusLine), findsOneWidget);
  });
}
