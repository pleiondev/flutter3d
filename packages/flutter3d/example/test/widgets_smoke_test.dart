/// The widget-written example opens, draws, and keeps its nodes across a tap
/// — `P10`.
///
///     flutter test test/widgets_smoke_test.dart
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_example/widgets_main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the widgets example draws, and a tap changes the material it '
      'already has', (tester) async {
    // Mutation: make `_Material3DState._material` a new engine material on
    // every read — the tap leaves the sphere with another object, and a game
    // holding the first is left changing one nothing draws.
    Scene3DController? controller;
    await tester.pumpWidget(WidgetsApp3D(onCreated: (c) => controller = c));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('opening')), findsNothing);

    final sphere = controller!.scene.meshes.single;
    final material = sphere.material;
    expect(material.roughness, 0.35);

    await tester.tap(find.byType(Scene3D));
    await tester.pumpAndSettle();

    expect(identical(controller!.scene.meshes.single, sphere), isTrue);
    expect(identical(sphere.material, material), isTrue);
    expect(material.roughness, 0.1);
    expect(material.metallic, 1.0);
  });
}
