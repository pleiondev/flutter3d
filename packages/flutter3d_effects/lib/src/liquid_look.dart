/// The water's material: `assets_src/liquid.f3dmat`, compiled into the
/// bundle the package ships, bound to a renderer and moved every frame.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import 'materials.g.dart';

/// What a liquid does to light: what a metre of it takes out of red, green
/// and blue, [absorb], 1/m, and what a metre of it sends back the way the
/// light came, [backscatter], 1/m. The surface ([LiquidLook]) and the floor
/// under it ([SeabedLook]) are coloured by the same pair.
final class LiquidOptics {
  const LiquidOptics({required this.absorb, required this.backscatter});

  /// Pure water: its absorption at 610, 550 and 470 nm (Pope and Fry,
  /// Applied Optics 36, 1997), and half its scattering there, Morel's
  /// b = 0.00288 (λ/500)^−4.32 (Morel, Optical Aspects of Oceanography,
  /// 1974) — what a clear sea or a spring is, deep blue where it is deep.
  /// A pond, a river or a crypt's pool has what is dissolved and carried in
  /// it besides, and is the game's to measure.
  static final LiquidOptics pureWater = LiquidOptics(
    absorb: Vector3(0.264, 0.0565, 0.0106),
    backscatter: Vector3(0.00061, 0.00095, 0.00188),
  );

  /// 1/m.
  final Vector3 absorb, backscatter;

  /// The share of the light it takes that it sends back, b_b / (a + b_b),
  /// red, green and blue: the colour a deep body of it is lit.
  Vector3 get scatter => Vector3(
    _share(backscatter.x, absorb.x),
    _share(backscatter.y, absorb.y),
    _share(backscatter.z, absorb.z),
  );

  static double _share(double b, double a) => a + b <= 0 ? 0.0 : b / (a + b);
}

/// How steep a water's ripples are for a wind of [speed] m/s over it,
/// against the ripples [LiquidLook] draws at a steepness of one: the mean
/// square slope of a sea surface, 0.003 + 5.12·10⁻³ U, U the wind 12.5 m
/// above it (Cox and Munk, J. Opt. Soc. Am. 44, 1954), over the nine
/// ripples' own, half the sum of their slopes squared.
double rippleSteepness(double speed) =>
    math.sqrt((0.003 + 5.12e-3 * speed.abs()) / _rippleSlopes);

/// Half the sum of the squares of the nine ripples' slopes at a steepness of
/// one, as `liquid.f3dmat` and `seabed.f3dmat` write them.
const double _rippleSlopes =
    0.5 *
    (0.032 * 0.032 +
        0.032 * 0.032 +
        0.03 * 0.03 +
        0.029 * 0.029 +
        0.028 * 0.028 +
        0.027 * 0.027 +
        0.026 * 0.026 +
        0.026 * 0.026 +
        0.024 * 0.024);

/// How a [LiquidView]'s surface is lit: ripples the flow carries, the sky
/// mirrored as strongly as Fresnel says, the sun's glint, the colour a
/// depth of water gives the bed under it, and froth where there is air or
/// the flow runs fast enough to break.
///
/// One look serves every water in a scene; [update] it once a frame.
final class LiquidLook {
  LiquidLook._(this.material);

  /// Where an application's asset bundle holds the compiled material:
  /// `rootBundle.load(LiquidLook.asset)`.
  static const String asset =
      'packages/flutter3d_effects/assets/liquid.f3dshaders';

  /// The material's name in its bundle.
  static const String model = 'Liquid';

  /// The look from the compiled [bundle] — what [asset] holds — with its
  /// stages added to [renderer] for [device].
  static Future<LiquidLook> load({
    required GraphicsDevice device,
    required Renderer renderer,
    required ByteData bundle,
  }) async {
    renderer.renderSteps.addMaterials(await device.loadShaders(bundle));
    return LiquidLook.of(bundle);
  }

  /// The look from [bundle] without binding its stages: for a renderer that
  /// already has them, or a test that reads what the material declares.
  factory LiquidLook.of(ByteData bundle) {
    final materials = BundledMaterials.read(bundle);
    return LiquidLook._(
      RenderMaterial(
        name: 'water',
        lighting: materials[model],
        parameters: materials.parameters(model),
        alphaMode: MaterialAlphaMode.blend,
        // Seen from below too, where it is Snell's window.
        doubleSided: true,
      ),
    );
  }

  /// What a water surface is drawn with.
  final RenderMaterial material;

  /// The uniforms, typed — generated from `liquid.f3dmat`.
  LiquidParameters get _params => LiquidParameters(material.parameters);

  /// The frame's clock, where the eye is, and the angle one of the
  /// screen's pixels spans, radians — 2·tan(fov/2) over the viewport's
  /// height: ripples run on [seconds], and those too fine to span a few
  /// pixels fade before they alias.
  void update({
    required double seconds,
    required Vector3 eye,
    double pixel = 0.001,
  }) {
    _params
      ..time = seconds
      ..eye = eye
      ..pixel = pixel;
  }

  /// The wind over the water, m/s: how steep its ripples are, as Cox and
  /// Munk measured the sea's slopes ([rippleSteepness]).
  set wind(double speed) => _params.chop = rippleSteepness(speed);

  /// The sun: the direction its light travels along, and its colour times
  /// its intensity.
  void sun({required Vector3 along, required Vector3 light}) {
    _params
      ..toSun = (-along).normalized()
      ..sunColor = light;
  }

  /// What the liquid does to light: pure water's at first.
  set optics(LiquidOptics value) {
    _params
      ..absorb = value.absorb
      ..scatter = value.scatter;
  }

  /// Light the liquid gives off itself, as molten rock does: brightest
  /// where its flow breaks the crust. Nought for anything cold.
  set glow(Vector3 value) => _params.glow = value;

  /// The sky the water mirrors: what the scene's sky draws overhead and at
  /// the horizon.
  void sky({required Vector3 zenith, required Vector3 horizon}) {
    _params
      ..zenith = zenith
      ..horizon = horizon;
  }
}
