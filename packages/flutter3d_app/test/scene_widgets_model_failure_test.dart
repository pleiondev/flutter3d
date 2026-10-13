/// A `Model3D` that will not load says so in the widget tree, not in the
/// zone: `onError`, `errorBuilder`, and the view's log when neither is set.
///
///     flutter test test/scene_widgets_model_failure_test.dart
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/flutter3d.dart' as engine show RenderMaterial;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

CpuDevice _device() => CpuDevice(
  width: 32,
  height: 24,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

Widget _noPresenter(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.contain,
  FilterQuality quality = FilterQuality.low,
}) => const SizedBox.expand();

final engine.RenderMaterial _grey = engine.RenderMaterial(
  baseColor: LinearColor.fromSrgb(0.6, 0.6, 0.6, 1.0),
);

Mesh3D _marker(String name) =>
    Mesh3D(shape: CuboidShape(), material: _grey, name: name);

Future<Scene3DController> _pump(
  WidgetTester tester,
  List<Widget> children, {
  EngineLog? log,
}) async {
  Scene3DController? controller;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Scene3D(
        device: DeviceSettings(device: _device(), presenter: _noPresenter),
        view: const ViewSettings(continuous: false, warmUp: false),
        log: log,
        onSceneCreated: (c) => controller = c,
        children: children,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return controller!;
}

Iterable<String?> _names(Scene3DController controller) =>
    controller.scene.meshes.map((MeshNode m) => m.name);

void main() {
  testWidgets('a model that will not load is handed to onError, and '
      'errorBuilder stands in for it', (tester) async {
    // Mutation: leave `_loadInto` with `try/finally` and no `catch`, and the
    // error goes to the zone, the test fails on it, and the placeholder
    // stays for ever.
    final failed = Completer<ModelAsset>();
    final failures = <Model3DFailure>[];
    final controller = await _pump(tester, <Widget>[
      Model3D(
        load: (GraphicsDevice device) => failed.future,
        placeholder: _marker('placeholder'),
        errorBuilder: (BuildContext context, Model3DFailure failure) =>
            _marker('broken'),
        onError: failures.add,
      ),
    ]);
    expect(_names(controller), <String?>['placeholder']);

    failed.completeError(const FormatException('not a model'));
    await tester.pump();
    await tester.pump();
    expect(failures, hasLength(1));
    expect(failures.single.error, isA<FormatException>());
    expect(failures.single.stackTrace, isNotNull);
    expect(_names(controller), <String?>['broken']);
  });

  testWidgets('with neither set, the failure goes to the view\'s log and '
      'the placeholder goes', (tester) async {
    // Mutation: report nothing when neither is set, and a model that never
    // appears leaves no word anywhere.
    final log = EngineLog();
    final records = <LogRecord>[];
    log.listen(records.add);
    final controller = await _pump(tester, <Widget>[
      Model3D(
        load: (GraphicsDevice device) async =>
            throw const FormatException('not a model'),
        placeholder: _marker('placeholder'),
      ),
    ], log: log);
    await tester.pump();
    await tester.pump();
    final errors = records.where((LogRecord r) => r.level == LogLevel.error);
    expect(errors, hasLength(1));
    expect(errors.single.error, isA<FormatException>());
    expect(_names(controller), isEmpty);
  });

  testWidgets('a model gone while it loads says nothing when its load '
      'fails after', (tester) async {
    final failed = Completer<ModelAsset>();
    var told = 0;
    await _pump(tester, <Widget>[
      Model3D(
        load: (GraphicsDevice device) => failed.future,
        onError: (Model3DFailure failure) => told++,
      ),
    ]);
    await tester.pumpWidget(const SizedBox());
    failed.completeError(StateError('too late'));
    await tester.pump();
    expect(told, 0);
  });
}
