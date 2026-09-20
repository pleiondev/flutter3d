/// `.fmat`: a material as a file of its own, read and written by
/// `readFmat`/`writeFmat`, round-tripping through `MaterialDocument`.
///
/// Quoted by `fmat_files.md` and shown whole in the Source tab.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as f3d show Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class FmatFilesDemo extends ShowcaseDemo {
  late final String _text;
  late final MaterialDocument _roundTripped;
  late final List<String> _typoWarnings;
  late final Scene _scene;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 2.4
      ..pitch = 0.2;
  }

  @override
  Scene build(DemoContext context) {
    // #region document
    final MaterialDocument document = MaterialDocument(
      surface: SurfaceMaterial(
        name: 'hull-plate',
        baseColor: Vector4(0.55, 0.6, 0.65, 1.0),
        metallic: 0.9,
        roughness: 0.28,
      ),
    );
    // #endregion document

    // #region roundtrip
    _text = writeFmat(document);
    _roundTripped = readFmat(
      Uint8List.fromList(utf8.encode(_text)),
      name: 'hull-plate.fmat',
    );
    // #endregion roundtrip

    // #region typo
    // An unknown key does not fail the file: it is recorded as a warning and
    // everything this reader does know still loads.
    const String typo =
        '{"fmat": 1, "name": "typo", "roughnesss": 0.2, "baseColor": '
        '[1, 1, 1, 1]}';
    _typoWarnings = readFmat(
      Uint8List.fromList(utf8.encode(typo)),
      name: 'typo.fmat',
    ).warnings;
    // #endregion typo

    final SurfaceMaterial surface = _roundTripped.surface;
    return _scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            SphereShape(segments: 40, rings: 20).build(),
          ),
          f3d.Material(
            name: surface.name,
            baseColor: surface.baseColor,
            metallic: surface.metallic,
            roughness: surface.roughness,
          ),
          name: 'plate',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -0.7, -0.6)),
      );
  }

  // #region report
  String _report() =>
      '$_text\n'
      'round trip warnings: ${_roundTripped.warnings.isEmpty ? "none" : _roundTripped.warnings}\n'
      'a file with an unknown key warns: $_typoWarnings';
  // #endregion report

  // A material file is text first — Step 4 of the guide says so, and the
  // report stays the whole story on the left. But a reader who cannot see
  // what "metallic: 0.9, roughness: 0.28" looks like is trusting the
  // numbers on faith, so the sphere those numbers actually shade sits
  // beside the report rather than instead of it, and drags like every
  // other page's viewport does.
  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Container(
          color: const Color(0xFF14161A),
          padding: const EdgeInsets.all(24),
          alignment: Alignment.topLeft,
          child: SingleChildScrollView(
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Color(0xFFE8E8EC),
                fontSize: 14,
                fontFamily: 'monospace',
              ),
              child: Text(_report()),
            ),
          ),
        ),
      ),
      Expanded(
        child: Listener(
          onPointerMove: (PointerMoveEvent event) =>
              context.orbit.rotate(event.delta.dx, event.delta.dy),
          onPointerSignal: (PointerSignalEvent event) {
            if (event is PointerScrollEvent) {
              context.orbit.zoom(event.scrollDelta.dy > 0.0 ? 1.1 : 1.0 / 1.1);
            }
          },
          child: SceneSurface(
            renderer: context.renderer,
            scene: _scene,
            view: context.view,
            settings: () => const RenderSettings(),
            onBeforeFrame: () =>
                context.orbit.syncProjectionDepth(context.camera),
            presentFrame: presentFrame,
          ),
        ),
      ),
    ],
  );

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final SurfaceMaterial original = SurfaceMaterial(
      metallic: 0.9,
      roughness: 0.28,
    );
    final SurfaceMaterial read = _roundTripped.surface;
    if (read.metallic != original.metallic ||
        read.roughness != original.roughness) {
      throw StateError('the round trip changed the material');
    }
    if (_roundTripped.warnings.isNotEmpty) {
      throw StateError(
        'a clean file should not warn: ${_roundTripped.warnings}',
      );
    }
    if (_typoWarnings.isEmpty) {
      throw StateError('an unknown key should have warned and did not');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the plate was not drawn');
    }
    // #endregion check
  }
}
