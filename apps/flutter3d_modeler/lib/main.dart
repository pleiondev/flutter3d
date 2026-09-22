/// A modeller for flutter3d.
///
///     flutter run -d macos
///     flutter run -d chrome --dart-define=model=assets/models/DamagedHelmet.glb
///
/// **The entry point and nothing else** — `ui-37d`. The screen, the fourteen
/// `part` files behind it and the imports they need are in
/// `src/screen/modeler_screen.dart`, which says why; this file exists so that
/// `flutter run` has somewhere to start and so that anything importing
/// `package:flutter3d_modeler/main.dart` — the tests do — still finds
/// `ModelerApp` and `ModelerScreen` where it always did.
///
/// The plan this follows is `doc/model-editor-plan.md` — ui-00 for this file,
/// view-02 for the viewport, p0-01 for the measurements; the answers, with the
/// machine and the date beside them, go in `doc/model-editor.md` §6.
library;

import 'src/screen/modeler_screen.dart';

export 'src/screen/modeler_screen.dart'
    show ModelerApp, ModelerScreen, findRecovery;

void main() => runModeler();
