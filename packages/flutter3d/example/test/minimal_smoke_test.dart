/// The minimal example, run the way CI runs everything: with no GPU.
///
/// The view falls back to the software rasteriser when Impeller will not
/// start, which is exactly what happens under `flutter test` — so this file is
/// both a smoke test and the proof that the fallback story in
/// `minimal_main.dart`'s comment is true.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_example/minimal_main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the minimal example opens a device and draws', (tester) async {
    // A small window: the software rasteriser draws every pixel of it.
    tester.view
      ..physicalSize = const Size(160, 120)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MinimalApp());

    // The device opens asynchronously, and the view's clock never settles:
    // let real time pass by turns until the placeholder is gone.
    for (
      var i = 0;
      i < 20 && find.byKey(const Key('opening')).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(microseconds: 16667));
    }

    // Reaching here means the device opened, the sphere uploaded, and a
    // frame was drawn without throwing. The placeholder is the one widget
    // that must be gone, and the scene drawn is the sphere's.
    expect(find.byKey(const Key('opening')), findsNothing);
    expect(find.byType(DidNotStart), findsNothing);
    final surface = tester.widget<SceneSurface>(find.byType(SceneSurface));
    expect(surface.scene.meshes.map((MeshNode it) => it.name), <String?>[
      'sphere',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
