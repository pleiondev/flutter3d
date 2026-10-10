/// The floor under a sea: `assets_src/seabed.f3dmat`, lit through the
/// surface's ripples and coloured by the water over it.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import 'liquid_look.dart';
import 'materials.g.dart';

/// How the floor under a sea is lit: the caustics the surface's ripples
/// focus on it, worked out from the same ripples [LiquidLook] draws, and the
/// colour the water takes out of the light on its way down and back up to
/// the eye — red first, as Beer and Lambert say for water.
final class SeabedLook {
  SeabedLook._(this.material);

  /// Where an application's asset bundle holds the compiled material.
  static const String asset =
      'packages/flutter3d_effects/assets/seabed.f3dshaders';

  /// The material's name in its bundle.
  static const String model = 'Seabed';

  /// The look from the compiled [bundle], its stages added to [renderer].
  static Future<SeabedLook> load({
    required GraphicsDevice device,
    required Renderer renderer,
    required ByteData bundle,
  }) async {
    renderer.renderSteps.addMaterials(await device.loadShaders(bundle));
    return SeabedLook.of(bundle);
  }

  /// The look from [bundle] without binding its stages.
  factory SeabedLook.of(ByteData bundle) {
    final materials = BundledMaterials.read(bundle);
    return SeabedLook._(
      RenderMaterial(
        name: 'seabed',
        lighting: materials[model],
        parameters: materials.parameters(model),
      ),
    );
  }

  /// What a sea floor is drawn with; its base colour is the floor's own.
  final RenderMaterial material;

  /// Anything else under the same sea — a rock, a wreck's timbers, a
  /// diver — in its own colour, lit through the same surface and coloured
  /// by the same water: the floor's stages and the floor's very parameters,
  /// so one [update] moves the caustics on all of them.
  RenderMaterial under(
    String name,
    Vector4 baseColor, {
    double roughness = 0.9,
  }) => RenderMaterial(
    name: name,
    lighting: material.lighting,
    parameters: material.parameters,
    baseColor: _fromSrgb(baseColor),
    roughness: roughness,
  );

  /// The uniforms, typed — generated from `seabed.f3dmat`.
  SeabedParameters get _params => SeabedParameters(material.parameters);

  /// The frame's clock, where the eye is, and the sea's surface height:
  /// the same clock the surface's [LiquidLook] runs on, so the caustics
  /// move with the ripples that make them.
  void update({
    required double seconds,
    required Vector3 eye,
    required double level,
  }) {
    _params
      ..time = seconds
      ..eye = eye
      ..level = level;
  }

  /// The wind over the water above, m/s, as [LiquidLook.wind] says.
  set wind(double speed) => _params.chop = rippleSteepness(speed);

  /// The sun: the direction its light travels along, and its light.
  void sun({required Vector3 along, required Vector3 light}) {
    _params
      ..toSun = (-along).normalized()
      ..sunColor = light;
  }

  /// What the water over it does to light, as [LiquidLook.optics]: pure
  /// water's at first.
  set optics(LiquidOptics value) {
    _params
      ..absorb = value.absorb
      ..scatter = value.scatter;
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
