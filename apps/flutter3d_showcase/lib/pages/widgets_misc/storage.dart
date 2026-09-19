/// Small documents a player's choices live in, kept the right way on
/// whichever of five platforms is running: a file on four of them, an
/// IndexedDB record for anything too big for `localStorage` on the fifth.
///
/// Quoted by `storage.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class StorageDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    final material = Material(
      name: 'disk',
      baseColor: Vector4(0.6, 0.6, 0.7, 1.0),
    );
    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  static Future<String> _run() async {
    // #region text
    final storage = defaultStorage('flutter3d-showcase-demo');
    final wrote = storage.write('settings.json', '{"volume":0.8}');
    final readBack = storage.read('settings.json');
    // #endregion text

    // #region remove
    storage.remove('settings.json');
    final afterRemove = storage.read('settings.json');
    // #endregion remove

    // #region binary
    final binary = defaultBinaryStorage('flutter3d-showcase-demo');
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    await binary.write('blob.bin', bytes);
    final readBytes = await binary.read('blob.bin');
    await binary.remove('blob.bin');
    // #endregion binary

    return 'wrote: $wrote, read back: $readBack, after remove: $afterRemove\n'
        'binary round trip: $readBytes';
  }

  @override
  Future<void> prepare(DemoContext context) async {
    _report = await _run();
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(_report),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the disk marker was not drawn');
    }
    if (!_report.contains('read back: {"volume":0.8}')) {
      throw StateError('what was written should read back exactly');
    }
    if (!_report.contains('after remove: null')) {
      throw StateError('a removed document should read back as nothing');
    }
    if (!_report.contains('binary round trip: [1, 2, 3, 4]')) {
      throw StateError('the bytes written should read back exactly');
    }
  }
}
