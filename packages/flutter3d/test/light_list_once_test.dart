/// The light list is built once a view, not once a draw.
///
///     flutter test test/light_list_once_test.dart
///
/// A scene with more lights than a draw's 8 slots puts every light, and the
/// view's cells, into one texture the lit draws sample (`gfx-74n`, `L6`). Its
/// rows are the same for every draw of a view, yet every lit draw wrote them
/// all again and compared them with the last upload: the Ascent's 17 lights
/// and their cells, rewritten and compared 270 times a frame, were two thirds
/// of its frame on a desktop GPU. Each build is counted here, so the list
/// stays one build per view however many draws read it.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_core/src/engine/render/renderer.dart'
    show RendererInternals;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

const int _size = 32;

/// [boxes] lit boxes in a row under [lamps] point lights.
({Renderer renderer, CpuDevice device, Scene scene, List<LightNode> lamps})
_stage({required int boxes, required int lamps}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final scene = Scene();
  final mesh = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(0.8, 0.8, 0.8)).build(),
  );
  for (var i = 0; i < boxes; i++) {
    scene.add(
      MeshNode(
        mesh,
        RenderMaterial(
          name: 'box $i',
          baseColor: LinearColor.fromSrgb(1.0, 1.0, 1.0, 1.0),
        ),
      )..setPosition(i - boxes / 2.0, 0.0, 0.0),
    );
  }
  final lights = <LightNode>[
    for (var i = 0; i < lamps; i++)
      LightNode(
        type: LightType.point,
        intensity: LightNode.defaultIntensity,
        range: 30.0,
      )..setPosition(i - lamps / 2.0, 2.0, 1.0),
  ];
  for (final light in lights) {
    scene.add(light);
  }
  scene.add(
    CameraNode()
      ..setPosition(0.0, 6.0, 14.0)
      ..lookAt(Vector3.zero()),
  );
  return (renderer: renderer, device: device, scene: scene, lamps: lights);
}

FrameResult _render(Renderer renderer, Scene scene, List<RenderView> views) =>
    renderer.render(
      width: _size,
      height: _size,
      scene: scene,
      views: views,
      settings: const RenderSettings(),
    );

void main() {
  test('a view of many lit draws builds its light list once', () {
    final (:renderer, :device, :scene, lamps: _) = _stage(boxes: 24, lamps: 12);
    final views = <RenderView>[RenderView(camera: scene.cameras.single)];

    final frame = _render(renderer, scene, views);
    expect(frame.drawCalls, greaterThan(12), reason: 'many lit draws');
    expect(renderer.debugLightListBuilds, 1);

    _render(renderer, scene, views);
    expect(renderer.debugLightListBuilds, 2, reason: 'and once again a frame');
  });

  test('each view builds its own, since each has its own cells', () {
    final (:renderer, :device, :scene, lamps: _) = _stage(boxes: 12, lamps: 12);
    final other = CameraNode()
      ..setPosition(8.0, 3.0, 4.0)
      ..lookAt(Vector3.zero());
    scene.add(other);

    _render(renderer, scene, <RenderView>[
      RenderView(camera: scene.cameras.first),
      RenderView(
        camera: other,
        viewportFraction: const ViewportRect(0.5, 0.0, 0.5, 1.0),
      ),
    ]);
    expect(renderer.debugLightListBuilds, 2);
  });

  test('a light changed between frames reaches the next frame', () async {
    final (:renderer, :device, :scene, :lamps) = _stage(boxes: 6, lamps: 12);
    final views = <RenderView>[RenderView(camera: scene.cameras.single)];

    Future<int> brightness() async {
      final frame = _render(renderer, scene, views);
      final bytes = await device.readback(frame.frame);
      var total = 0;
      for (var i = 0; i < _size * _size * 4; i += 4) {
        total += bytes.getUint8(i);
      }
      return total;
    }

    final lit = await brightness();
    for (final lamp in lamps) {
      lamp.color = LinearColor.fromSrgb(0.05, 0.05, 0.05, 1.0);
    }
    final dimmed = await brightness();
    expect(dimmed, lessThan(lit));
  });

  test('a scene inside the eight slots builds none', () {
    final (:renderer, :device, :scene, lamps: _) = _stage(boxes: 6, lamps: 4);
    _render(renderer, scene, <RenderView>[
      RenderView(camera: scene.cameras.single),
    ]);
    expect(renderer.debugLightListBuilds, 0);
  });
}
