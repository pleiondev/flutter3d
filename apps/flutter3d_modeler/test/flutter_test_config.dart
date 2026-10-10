/// Holds every `testWidgets` here to the minute `dart_test.yaml` gives a test.
///
/// **`testWidgets` brings a timeout of its own.** It passes `test()` the
/// binding's `defaultTestTimeout`, ten minutes, as the test's own timeout
/// (`timeout ?? binding.defaultTestTimeout`, read as the test is declared),
/// and a test's own timeout wins over the package's. So without this file a
/// widget test could run for ten minutes in a package that says one.
///
/// **The binding is still flutter_test's own, made when it always was.** It
/// is not created here: a file that declares no widget test and never calls
/// `TestWidgetsFlutterBinding.ensureInitialized` still has no binding, and
/// one that does gets the usual `AutomatedTestWidgetsFlutterBinding` at that
/// moment — with its `HttpOverrides` that answers every request with 400,
/// exactly where it applied before. All this changes is the timeout, and it
/// does it from inside that construction: `PaintingBinding.initInstances`
/// calls `PaintingBinding.shaderWarmUp?.execute()` synchronously, after the
/// binding's field initialisers (the ten minutes) have run and before
/// `ensureInitialized` returns it to the `testWidgets` about to read the
/// timeout. Nothing else in the tree or in flutter_test sets a warm-up, and
/// `flutter test` has no GPU for one to warm.
///
/// A factor of one rather than a duration, so that what the package or the
/// file says is what applies: a reasoned `@Timeout` on a file still counts.
///
/// The same file in every package with a widget test; the structure rule "a
/// test runs in a minute unless its reason is listed" checks that it is here
/// and that it says this.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show PaintingBinding, ShaderWarmUp;
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  PaintingBinding.shaderWarmUp = const _MinuteForWidgetTests();
  await testMain();
}

/// Not a warm-up: the one call a binding makes, while it is being built, to
/// code that is not its own.
final class _MinuteForWidgetTests extends ShaderWarmUp {
  const _MinuteForWidgetTests();

  @override
  Future<void> execute() async {
    if (PaintingBinding.instance
        case final AutomatedTestWidgetsFlutterBinding binding) {
      binding.defaultTestTimeout = const Timeout.factor(1);
    }
  }

  @override
  Future<void> warmUpOnCanvas(ui.Canvas canvas) async {}
}
