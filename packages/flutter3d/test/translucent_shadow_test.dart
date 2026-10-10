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

const int _size = 64;

/// A floor and a card over it, lit at forty-five degrees so the shadow lands
/// clear of the card's footprint, seen from above.
Future<List<int>> _frame({
  required RenderMaterial? card,
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
        RenderMaterial(
          name: 'floor',
          baseColor: LinearColor.fromSrgb(0.9, 0.9, 0.9, 1.0),
        ),
      )..setPosition(0.0, -1.0, 0.0),
    )
    ..add(
      LightNode(intensity: sun * Photometric.legacyUnit, castsShadow: true)
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
        clearColorSrgb: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: RenderSettings(
      shadows: ShadowSettings(translucentCasters: translucent),
      look: const LookSettings(dither: 0),
    ),
  );
  final bytes = await device.readback(frame.frame);
  return <int>[for (var i = 0; i < _size * _size * 4; i++) bytes.getUint8(i)];
}

RenderMaterial _opaque() => RenderMaterial(
  name: 'wall',
  baseColor: LinearColor.fromSrgb(0.8, 0.8, 0.8, 1.0),
);

RenderMaterial _glass() => RenderMaterial(
  name: 'glass',
  lighting: LightingModel.pbrLayered,
  baseColor: LinearColor.fromSrgb(0.95, 0.97, 1.0, 0.12),
  alphaMode: MaterialAlphaMode.blend,
  doubleSided: true,
  extensions: MaterialExtensions(transmission: 0.95, ior: 1.5),
);

RenderMaterial _blueLiquid() => RenderMaterial(
  name: 'liquid',
  lighting: LightingModel.pbrLayered,
  baseColor: LinearColor.fromSrgb(0.15, 0.3, 0.95, 0.8),
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
      );
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
      card: RenderMaterial(
        name: 'lens picture',
        lighting: LightingModel.pbrLayered,
        baseColor: LinearColor.fromSrgb(2.0, 2.0, 2.0, 1.0),
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

  test('an empty glass tube has a hairline edge, not a dark band', () async {
    // A thin-walled glass tube standing in the sun. At its silhouette the
    // light grazes the walls and is reflected nearly whole, but reflected at
    // grazing it is hardly turned, and lands beside where it would have.
    // Mutation: count every reflected ray as lost again, and the darkest
    // pixel falls to under two thirds of the lit floor.
    const size = 128;
    Future<List<int>> draw(RenderMaterial? material) async {
      final device = CpuDevice(
        width: size,
        height: size,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      final scene = Scene()
        ..add(
          MeshNode(
            DeviceMesh.upload(
              device,
              CuboidShape(size: Vector3(6, 0.1, 6)).build(),
            ),
            RenderMaterial(
              name: 'floor',
              baseColor: LinearColor.fromSrgb(0.9, 0.9, 0.9, 1.0),
            ),
          )..setPosition(0.0, -1.0, 0.0),
        )
        ..add(
          LightNode(castsShadow: true)
            ..setPosition(4.0, 5.0, 0.01)
            ..lookAt(Vector3.zero()),
        )
        ..add(
          CameraNode()
            ..setPosition(-0.8, 5.0, 0.01)
            ..lookAt(Vector3(-0.8, 0.0, 0.0)),
        );
      if (material != null) {
        scene.add(
          MeshNode(
            DeviceMesh.upload(
              device,
              LatheShape(
                profile: [Vector2(0.3, -0.95), Vector2(0.3, 0.6)],
                segments: 48,
              ).build(),
            ),
            material,
          )..shadowCasting = ShadowCastingMode.shadowsOnly,
        );
      }
      final frame = Renderer.create(device: device).render(
        width: size,
        height: size,
        scene: scene,
        views: <RenderView>[RenderView(camera: scene.cameras.single)],
        settings: const RenderSettings(
          shadows: ShadowSettings(translucentCasters: true),
          look: LookSettings(dither: 0),
        ),
      );
      final bytes = await device.readback(frame.frame);
      return <int>[for (var i = 0; i < size * size * 4; i++) bytes.getUint8(i)];
    }

    final lit = await draw(null);
    final solid = await draw(_opaque()..doubleSided = true);
    final glass = await draw(
      RenderMaterial(
        name: 'glass',
        lighting: LightingModel.pbrLayered,
        baseColor: LinearColor.fromSrgb(0.97, 0.99, 1.0, 0.22),
        alphaMode: MaterialAlphaMode.blend,
        doubleSided: true,
        extensions: MaterialExtensions(transmission: 1.0, ior: 1.5),
      ),
    );
    final region = _shadowed(solid, lit);
    expect(region.length, greaterThan(100), reason: 'the tube casts nothing');
    final (litR, _, _) = _mean(lit, region);
    final darkest = region.map((i) => glass[i]).reduce((a, b) => a < b ? a : b);
    expect(darkest, greaterThan(0.75 * litR));
  });

  test('copyWith keeps the setting', () {
    // `copyWith` has dropped fields before, and `settingsFrom` calls it every
    // frame, so a field it forgets is a setting nobody can turn on.
    const settings = ShadowSettings(translucentCasters: true);
    expect(settings.copyWith(strength: 0.5).translucentCasters, isTrue);
  });
}
