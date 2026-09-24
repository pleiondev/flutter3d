/// `gfx-60n`: a cut-out caster casts its cut-out, not its quad.
///
///     flutter test test/masked_shadow_test.dart
///
/// **The defect this closes is visible in the first screenshot of any outdoor
/// scene.** A leaf card is a quad whose texture is transparent almost
/// everywhere, and the shadow pass wrote depth unconditionally, so a tree cast
/// the shadow of its bounding rectangles: a stack of dark slabs where the eye
/// expects dappled light. Nothing in the lit pass can repair it, because by
/// then the shadow map already says the ground is in shadow.
///
/// Two claims, and the second is the one that lets this land at all: a caster
/// with a mask casts the mask, and a caster without one casts exactly what it
/// cast before, because it still goes through the stage it always went
/// through.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 64;

/// A two-by-two texture: opaque on the left, transparent on the right.
///
/// Two texels rather than a photograph of a leaf, so the picture the test
/// reads is a half a person can point at rather than a shape somebody has to
/// take on trust.
TextureHandle _halfMask(CpuDevice device) {
  final pixels = Uint8List.fromList(<int>[
    255, 255, 255, 255, /**/ 255, 255, 255, 0, //
    255, 255, 255, 255, /**/ 255, 255, 255, 0,
  ]);
  return device.createTextureFromPixels(
    width: 2,
    height: 2,
    pixels: ByteData.sublistView(pixels),
    format: TextureFormat.r8g8b8a8UNormInt,
  )!;
}

/// A floor with a quad hanging over it, lit from straight above, with the
/// shadow read off the floor.
Future<List<int>> _frame({
  required bool masked,
  bool withTexture = true,
  double cutoff = 0.5,
  bool casting = true,
}) async {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);

  final caster = Material(
    name: 'card',
    baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
    alphaMode: masked ? MaterialAlphaMode.mask : MaterialAlphaMode.opaque,
    alphaCutoff: cutoff,
  );
  if (withTexture) caster.albedo = _halfMask(device);

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
      MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3(2, 0.05, 2)).build(),
          ),
          caster,
        )
        ..setPosition(0.0, 1.0, 0.0)
        ..shadowCasting = casting
            ? ShadowCastingMode.on
            : ShadowCastingMode.off,
    )
    ..add(
      // Angled rather than straight down, because a light directly above puts
      // the shadow underneath the card and the camera never sees it: the
      // caster is between the two. At forty-five degrees the shadow lands
      // clear of the card's own footprint.
      LightNode(intensity: 6.0, castsShadow: true)
        ..setPosition(4.0, 5.0, 0.01)
        ..lookAt(Vector3.zero()),
    )
    ..add(
      CameraNode()
        ..setPosition(0.0, 5.0, 0.01)
        ..lookAt(Vector3.zero()),
    );

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
    // Undithered: the frames are compared byte for byte, a caster discarded
    // and a caster switched off draw the same floor to within the last bits
    // of a float, and
    // the dither would round those bits into a step on part of the pattern.
    settings: const RenderSettings(
      shadows: ShadowSettings(enabled: true),
      look: LookSettings(dither: 0),
    ),
  );
  final bytes = await device.readPixels(frame.frame);
  return <int>[for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i)];
}

/// How many pixels differ in any colour channel.
int _changed(List<int> a, List<int> b) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) count++;
  }
  return count;
}

/// How many pixels [frame] has in shadow, measured against [lit], the same
/// frame with nothing casting.
///
/// Counted against a reference rather than by a brightness threshold, because
/// a floor lit at an angle is not one value and a threshold would be a number
/// chosen to make the test pass.
int _inShadow(List<int> frame, List<int> lit) {
  var count = 0;
  for (var i = 0; i < frame.length; i += 4) {
    if (frame[i] < lit[i] - 2) count++;
  }
  return count;
}

void main() {
  test('a cut-out caster casts less shadow than a solid one', () async {
    // **The row's claim, measured in a way that does not depend on which way
    // the card's texture is wound.** Three frames: nothing casting, a solid
    // caster, and the same caster cut out. The cut-out one has to land
    // strictly between the other two, because half its texture is
    // transparent: less shadow than solid, more than none.
    final lit = await _frame(masked: false, casting: false);
    final solid = await _frame(masked: false);
    final cut = await _frame(masked: true);

    final solidArea = _inShadow(solid, lit);
    final cutArea = _inShadow(cut, lit);

    expect(
      solidArea,
      greaterThan(0),
      reason: 'the fixture casts no shadow at all, so it measures nothing',
    );
    expect(
      cutArea,
      lessThan(solidArea),
      reason:
          'the transparent half of the card still cast a shadow, which is '
          'the defect this row exists to close',
    );
    expect(
      cutArea,
      greaterThan(0),
      reason: 'the opaque half stopped casting too, which is the other bug',
    );
  });

  test('removing a caster does not add shadow anywhere', () async {
    // A mask can only take a blocker away, so the shadowed area has to shrink
    // and no pixel may go meaningfully darker. This is what would catch the
    // stage discarding the wrong half or the comparison running the wrong way
    // round, either of which darkens a large area by a lot.
    //
    // **One step of slack, and it is a measured one rather than a cushion.**
    // The filter is PCSS: it searches for blockers and sizes its penumbra from
    // what it finds, so taking a blocker away re-estimates the penumbra and
    // moves the boundary. Measured here: 41 pixels of 4096 go darker and every
    // one of them goes darker by exactly one. The bound below is eighty, which
    // is twice the measurement and still a fiftieth of the frame; a mask
    // discarding the wrong half darkens a region, not a rim.
    final lit = await _frame(masked: false, casting: false);
    final solid = await _frame(masked: false);
    final cut = await _frame(masked: true);

    expect(_inShadow(cut, lit), lessThan(_inShadow(solid, lit)));

    var darker = 0;
    for (var i = 0; i < solid.length; i += 4) {
      final delta = solid[i] - cut[i];
      if (delta > 0) darker++;
      expect(
        delta,
        lessThanOrEqualTo(1),
        reason:
            'pixel ${i ~/ 4} went darker by $delta when the caster was cut '
            'out, which is more than a penumbra re-estimate',
      );
    }
    expect(
      darker,
      lessThan(80),
      reason: 'a rim of boundary pixels is a filter; a region is a bug',
    );
  });

  test('a caster with no map keeps the shadow it always cast', () async {
    // **The half that lets this land.** A material that is not cut out goes
    // through the stage it has always gone through, with no sampler in the
    // pipeline and no texture bound per draw, so the forty-four goldens
    // recorded against that stage cannot move. Asking for MASK with no map to
    // read is the same case: there is nothing to cut out.
    final plain = await _frame(masked: false, withTexture: false);
    final asked = await _frame(masked: true, withTexture: false);

    expect(asked, plain);
  });

  test('a cutoff nothing reaches removes the caster entirely', () async {
    // The threshold is `Material.alphaCutoff` and the comparison is glTF's
    // MASK rule, so a cutoff above every alpha in the map discards every
    // fragment and the floor comes back as though nothing were above it.
    final lit = await _frame(masked: false, casting: false);
    final none = await _frame(masked: true, cutoff: 1.01);

    expect(_changed(none, lit), 0);
  });

  test('and a cutoff below every alpha keeps the whole quad', () async {
    // The other end, which is what catches a comparison that ignores the
    // number: at a cutoff of zero every texel passes, so a cut-out caster
    // casts exactly what a solid one does.
    final solid = await _frame(masked: false);
    final all = await _frame(masked: true, cutoff: 0.0);
    final lit = await _frame(masked: false, casting: false);

    expect(_inShadow(all, lit), _inShadow(solid, lit));
  });
}
