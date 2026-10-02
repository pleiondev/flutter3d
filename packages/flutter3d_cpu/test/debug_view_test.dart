/// A material channel in place of the light — `P6`: what the materials write
/// when `RenderSettings.debugView` asks, and the wipe between the two.
///
///     dart test test/debug_view_test.dart
///
/// Read through the composite, so every number here is what reaches the
/// screen: a channel has to come out as the value the material holds, with
/// the exposure and the tone curve left off its side of the split.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 48;

/// A card filling the middle of the frame, of [material], through
/// [settings], lit by one light from the front.
Float32List _render(RenderSettings settings, {Material? material}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final card =
      MeshNode(
          DeviceMesh.upload(device, CuboidShape().build()),
          material ??
              Material(
                baseColor: Vector4(0.6, 0.3, 0.1, 1.0),
                roughness: 0.35,
                metallic: 0.8,
              ),
        )
        ..setPosition(0.0, 0.0, -2.0)
        ..setScale(2.4, 1.8, 0.05);
  final camera = CameraNode();
  final light = LightNode(intensity: 3.0)..lookAt(Vector3(0.0, 0.0, -1.0));
  final result = Renderer.create(device: device).render(
    width: _width,
    height: _height,
    scene: Scene()
      ..add(card)
      ..add(light)
      ..add(camera),
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: settings,
  );
  return Float32List.fromList(device.readHdrPixels(result.frame));
}

/// The colour at pixel ([x], [y]).
Vector3 _at(Float32List frame, int x, int y) {
  final i = (y * _width + x) * 4;
  return Vector3(frame[i], frame[i + 1], frame[i + 2]);
}

const RenderSettings _plain = RenderSettings(
  bloom: BloomSettings(enabled: false),
  look: LookSettings(dither: 0.0),
);

RenderSettings _showing(DebugView view, {double split = 0.0}) =>
    _plain.copyWith(
      debugView: DebugViewSettings(view: view, split: split),
    );

void main() {
  test('off is the picture as it was, to the bit', () {
    // Mutation: write `debug_view.x` whatever `active` says, or leave the
    // composite's `lens.y` at one, and a frame nobody asked to debug moves.
    expect(_render(_showing(DebugView.off)), _render(_plain));
  });

  test('a channel reaches the screen as the value the material holds', () {
    // Mutation: leave the debug side under the exposure or the tone curve in
    // `composite.frag`, and the greys come out brighter or flatter than the
    // material's own numbers. A doubled exposure is there to show it.
    final exposed = _plain.copyWith(exposure: 2.0);
    Vector3 centre(DebugView view) => _at(
      _render(exposed.copyWith(debugView: DebugViewSettings(view: view))),
      _width ~/ 2,
      _height ~/ 2,
    );

    // `baseColor` is given in sRGB and the view shows it in sRGB: the
    // numbers come back as they went in.
    final albedo = centre(DebugView.albedo);
    expect(albedo.x, closeTo(0.6, 0.01));
    expect(albedo.y, closeTo(0.3, 0.01));
    expect(albedo.z, closeTo(0.1, 0.01));

    expect(centre(DebugView.roughness).x, closeTo(0.35, 0.01));
    expect(centre(DebugView.metallic).x, closeTo(0.8, 0.01));
    expect(centre(DebugView.occlusion).x, closeTo(1.0, 0.01));
    expect(centre(DebugView.emissive).x, closeTo(0.0, 0.01));

    // The card faces the camera, so its normal is +z: (0.5, 0.5, 1).
    final normal = centre(DebugView.normal);
    expect(normal.x, closeTo(0.5, 0.02));
    expect(normal.y, closeTo(0.5, 0.02));
    expect(normal.z, closeTo(1.0, 0.02));
  });

  test('the coordinate runs across the card', () {
    // Mutation: read `v_world_position` for the UV view, or swap its lanes.
    final frame = _render(_showing(DebugView.uv));
    final left = _at(frame, _width ~/ 4, _height ~/ 2);
    final right = _at(frame, _width * 3 ~/ 4, _height ~/ 2);
    expect(right.x, greaterThan(left.x + 0.1));
    expect(left.z, 0.0);
  });

  test('the split leaves the left lit and shows the channel on the right', () {
    // Mutation: compare against the output's width instead of the scene's,
    // or let the composite pass the whole frame through.
    final lit = _render(_plain);
    final wiped = _render(_showing(DebugView.roughness, split: 0.5));
    final y = _height ~/ 2;
    expect(_at(wiped, _width ~/ 4, y), _at(lit, _width ~/ 4, y));
    expect(_at(wiped, _width * 3 ~/ 4, y).x, closeTo(0.35, 0.01));
  });

  test('a NaN in the light shows as magenta, and nothing else does', () {
    // Mutation: test the light with `isNaN` on one channel only, or show the
    // grey for every fragment, and one of the two cards below goes wrong.
    final broken = _render(
      _showing(DebugView.nonFinite),
      // Emission is added as it is, so a NaN there reaches the light.
      material: Material(emissive: Vector3(double.nan, 0.0, 0.0)),
    );
    expect(_at(broken, _width ~/ 2, _height ~/ 2), Vector3(1.0, 0.0, 1.0));

    final sound = _render(_showing(DebugView.nonFinite));
    final grey = _at(sound, _width ~/ 2, _height ~/ 2);
    expect(grey.x, grey.y);
    expect(grey.x, lessThan(0.5));
  });
}
