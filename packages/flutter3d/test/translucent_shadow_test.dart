/// `ShadowSettings.translucentCasters`: a see-through caster shades the sun's
/// light by what its material lets through.
///
///     flutter test test/translucent_shadow_test.dart
///
/// **A shadow map holds one depth per texel**, so until this a pane of clear
/// glass cast a shadow as dark as a wall, and a blue liquid a grey one. The
/// claims, each against the same floor and the same card over it:
///
///  * clear glass still darkens the floor, and much less than an opaque card;
///  * a blue liquid darkens it to blue: what reaches the floor is bluer than
///    the light that fell;
///  * with nothing see-through in the scene, turning it on changes no pixel.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 64;

/// A floor and a card over it, lit at forty-five degrees so the shadow lands
/// clear of the card's footprint, seen from above.
Future<List<int>> _frame({
  required Material? card,
  required bool translucent,
  bool casting = true,
  TextureHandle Function(CpuDevice device)? map,
  ShadowCastingMode? mode,
  double sun = 1.0,
}) async {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(6, 0.1, 6)).build(),
        ),
        Material(name: 'floor', baseColor: Vector4(0.9, 0.9, 0.9, 1.0)),
      )..setPosition(0.0, -1.0, 0.0),
    )
    ..add(
      LightNode(intensity: sun, castsShadow: true)
        ..setPosition(4.0, 5.0, 0.01)
        ..lookAt(Vector3.zero()),
    )
    ..add(
      CameraNode()
        ..setPosition(0.0, 5.0, 0.01)
        ..lookAt(Vector3.zero()),
    );
  if (card != null) {
    if (map != null) card.albedo = map(device);
    scene.add(
      MeshNode(
          DeviceMesh.upload(
            device,
            // A painted card is one surface: a slab's underside reads its
            // map mirrored, and would put the black half over the white.
            map != null
                ? const PlaneShape(width: 2, depth: 2).build()
                : CuboidShape(size: Vector3(2, 0.05, 2)).build(),
          ),
          card,
        )
        ..setPosition(0.0, 1.0, 0.0)
        ..shadowCasting =
            mode ?? (casting ? ShadowCastingMode.on : ShadowCastingMode.off),
    );
  }
  final frame = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: scene.cameras.single,
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: RenderSettings(
      shadows: ShadowSettings(translucentCasters: translucent),
      look: const LookSettings(dither: 0),
    ),
  );
  final bytes = await device.readPixels(frame.frame);
  return <int>[for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i)];
}

Material _opaque() =>
    Material(name: 'wall', baseColor: Vector4(0.8, 0.8, 0.8, 1.0));

Material _glass() => Material(
  name: 'glass',
  lighting: LightingModel.pbrLayered,
  baseColor: Vector4(0.95, 0.97, 1.0, 0.12),
  alphaMode: MaterialAlphaMode.blend,
  doubleSided: true,
  extensions: MaterialExtensions(transmission: 0.95, ior: 1.5),
);

Material _blueLiquid() => Material(
  name: 'liquid',
  lighting: LightingModel.pbrLayered,
  baseColor: Vector4(0.15, 0.3, 0.95, 0.8),
  alphaMode: MaterialAlphaMode.blend,
  extensions: MaterialExtensions(transmission: 0.6, ior: 1.33),
);

/// The floor pixels a solid card shadows: where [solid] is darker than [lit].
List<int> _shadowed(List<int> solid, List<int> lit) => <int>[
  for (var i = 0; i < solid.length; i += 4)
    if (solid[i] < lit[i] - 8) i,
];

/// The mean red, green and blue over [pixels] of [frame].
(double, double, double) _mean(List<int> frame, List<int> pixels) {
  var r = 0.0, g = 0.0, b = 0.0;
  for (final i in pixels) {
    r += frame[i];
    g += frame[i + 1];
    b += frame[i + 2];
  }
  final n = pixels.length.toDouble();
  return (r / n, g / n, b / n);
}

void main() {
  test('clear glass casts a faint shadow, an opaque card a dark one', () async {
    final lit = await _frame(
      card: _opaque(),
      translucent: true,
      casting: false,
    );
    final solid = await _frame(card: _opaque(), translucent: true);
    final asBefore = await _frame(card: _glass(), translucent: false);
    final glass = await _frame(card: _glass(), translucent: true);
    final region = _shadowed(solid, lit);
    expect(region.length, greaterThan(40), reason: 'the fixture casts nothing');

    final (litR, _, _) = _mean(lit, region);
    final (solidR, _, _) = _mean(solid, region);
    final (beforeR, _, _) = _mean(asBefore, region);
    final (glassR, _, _) = _mean(glass, region);

    // Off, the glass is a wall — the defect. Mutation: draw see-through
    // casters into the atlas regardless of the setting, and this moves.
    expect(beforeR, closeTo(solidR, 2.0));
    // On, it lets most of the light through, but not all of it: four
    // surfaces each reflect some away. Mutation: skip the Fresnel loss, and
    // the shadow is gone; draw the glass as opaque, and it is a wall again.
    expect(glassR, greaterThan(solidR + 0.5 * (litR - solidR)));
    expect(glassR, lessThan(litR - 1.0));
  });

  test('a blue liquid casts a blue shadow', () async {
    final lit = await _frame(
      card: _opaque(),
      translucent: true,
      casting: false,
    );
    final solid = await _frame(card: _opaque(), translucent: true);
    final liquid = await _frame(card: _blueLiquid(), translucent: true);
    final region = _shadowed(solid, lit);

    final (litR, _, litB) = _mean(lit, region);
    final (r, _, b) = _mean(liquid, region);
    // Bluer than the light that fell: the red is taken more than the blue.
    // Mutation: write the same number into all three channels, and the
    // ratio stays the floor's.
    expect(b / r, greaterThan(1.3 * litB / litR));
    // And darker than no shadow at all.
    expect(r, lessThan(litR - 8.0));
  });

  test('with nothing see-through, turning it on changes no pixel', () async {
    final off = await _frame(card: _opaque(), translucent: false);
    final on = await _frame(card: _opaque(), translucent: true);
    // Mutation: clear the atlas's free channels to ones, or set the flag on
    // a draw whose atlas carries none, and the floor goes black.
    expect(on, off);
  });

  test('a painted card can take light away and gather it', () async {
    // A caster that is only a shadow, carrying a picture of where the light
    // went: black on one half, white on the other, and a colour of two, so
    // the white half lets twice the light through. Mutation: hold the colour
    // or the stored value to one, and nothing is brightened; drop the map,
    // and both halves read alike.
    TextureHandle halves(CpuDevice device) {
      final pixels = Uint8List.fromList(<int>[
        0, 0, 0, 255, /**/ 255, 255, 255, 255, //
        0, 0, 0, 255, /**/ 255, 255, 255, 255,
      ]);
      return device.createTextureFromPixels(
        width: 2,
        height: 2,
        pixels: ByteData.sublistView(pixels),
        format: TextureFormat.r8g8b8a8UNormInt,
      )!;
    }

    // A dimmer sun than the other tests, so the lit floor sits where the
    // tone curve still has room above it; and every card a shadow only, so
    // none of them hides the half of its shadow the light falls past it on.
    final lit = await _frame(card: null, translucent: true, sun: 0.3);
    final solid = await _frame(
      card: _opaque(),
      translucent: true,
      sun: 0.3,
      mode: ShadowCastingMode.shadowsOnly,
    );
    final region = _shadowed(solid, lit);
    final painted = await _frame(
      sun: 0.3,
      card: Material(
        name: 'lens picture',
        lighting: LightingModel.pbrLayered,
        baseColor: Vector4(2.0, 2.0, 2.0, 1.0),
        extensions: MaterialExtensions(transmission: 1.0, ior: 1.0),
      ),
      translucent: true,
      map: halves,
      mode: ShadowCastingMode.shadowsOnly,
    );
    var darker = 0, brighter = 0;
    for (final i in region) {
      if (painted[i] < lit[i] - 20) darker++;
      if (painted[i] > lit[i] + 3) brighter++;
    }
    expect(darker, greaterThan(region.length ~/ 5));
    expect(brighter, greaterThan(region.length ~/ 5));
  });

  test('copyWith keeps the setting', () {
    // `copyWith` has dropped fields before, and `settingsFrom` calls it every
    // frame, so a field it forgets is a setting nobody can turn on.
    const settings = ShadowSettings(translucentCasters: true);
    expect(settings.copyWith(strength: 0.5).translucentCasters, isTrue);
  });
}
