/// The floor under a sea: `assets_src/seabed.f3dmat`, lit through the
/// surface's ripples and coloured by the water over it.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:vector_math/vector_math.dart';

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
    renderer.addMaterials(await device.loadShaders(bundle));
    return SeabedLook.of(bundle);
  }

  /// The look from [bundle] without binding its stages.
  factory SeabedLook.of(ByteData bundle) {
    final materials = BundledMaterials.read(bundle);
    return SeabedLook._(
      Material(
        name: 'seabed',
        lighting: materials[model],
        parameters: materials.parameters(model),
      ),
    );
  }

  /// What a sea floor is drawn with; its base colour is the floor's own.
  final Material material;

  void _set(String uniform, List<double> values) =>
      material.parameters[uniform]!.setAll(0, values);

  /// The frame's clock, where the eye is, and the sea's surface height:
  /// the same clock the surface's [LiquidLook] runs on, so the caustics
  /// move with the ripples that make them.
  void update({
    required double seconds,
    required Vector3 eye,
    required double level,
  }) {
    _set('time', <double>[seconds]);
    _set('eye', eye.storage);
    _set('level', <double>[level]);
  }

  /// How steep the ripples are, as [LiquidLook.chop] says.
  set chop(double value) => _set('chop', <double>[value]);

  /// The sun: the direction its light travels along, and its light.
  void sun({required Vector3 along, required Vector3 light}) {
    _set('toSun', (-along).normalized().storage);
    _set('sunColor', light.storage);
  }

  /// The water: what a metre of it takes out of red, green and blue, per
  /// metre, and the colour of the light it scatters back.
  void water({required Vector3 absorb, required Vector3 scatter}) {
    _set('absorb', absorb.storage);
    _set('scatter', scatter.storage);
  }
}
