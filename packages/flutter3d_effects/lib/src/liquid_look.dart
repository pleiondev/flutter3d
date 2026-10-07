/// The water's material: `assets_src/liquid.f3dmat`, compiled into the
/// bundle the package ships, bound to a renderer and moved every frame.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:vector_math/vector_math.dart';

/// How a [LiquidView]'s surface is lit: ripples the flow carries, the sky
/// mirrored as strongly as Fresnel says, the sun's glint, the colour a
/// depth of water gives the bed under it, and froth where there is air.
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
    renderer.addMaterials(await device.loadShaders(bundle));
    return LiquidLook.of(bundle);
  }

  /// The look from [bundle] without binding its stages: for a renderer that
  /// already has them, or a test that reads what the material declares.
  factory LiquidLook.of(ByteData bundle) {
    final materials = BundledMaterials.read(bundle);
    return LiquidLook._(
      Material(
        name: 'water',
        lighting: materials[model],
        parameters: materials.parameters(model),
        alphaMode: MaterialAlphaMode.blend,
      ),
    );
  }

  /// What a water surface is drawn with.
  final Material material;

  void _set(String uniform, List<double> values) =>
      material.parameters[uniform]!.setAll(0, values);

  /// The frame's clock and where the eye is: ripples run on [seconds], and
  /// those too far from [eye] to span a few pixels fade before they alias.
  void update({required double seconds, required Vector3 eye}) {
    _set('time', <double>[seconds]);
    _set('eye', eye.storage);
  }

  /// How steep the ripples are, one for still air; a wind roughens them.
  set chop(double value) => _set('chop', <double>[value]);

  /// The sun: the direction its light travels along, and its colour times
  /// its intensity.
  void sun({required Vector3 along, required Vector3 light}) {
    _set('toSun', (-along).normalized().storage);
    _set('sunColor', light.storage);
  }

  /// The liquid's own colour: of a thin layer over the bed and of a deep
  /// one, and the share of light a metre of it lets through — 0.15 for
  /// water, nearly none for oil or molten rock.
  void tint({
    required Vector3 shallow,
    required Vector3 deep,
    required double clearness,
  }) {
    _set('shallow', shallow.storage);
    _set('deep', deep.storage);
    _set('clearness', <double>[clearness]);
  }

  /// Light the liquid gives off itself, as molten rock does: brightest
  /// where its flow breaks the crust. Nought for anything cold.
  set glow(Vector3 value) => _set('glow', value.storage);

  /// The sky the water mirrors: what the scene's sky draws overhead and at
  /// the horizon.
  void sky({required Vector3 zenith, required Vector3 horizon}) {
    _set('zenith', zenith.storage);
    _set('horizon', horizon.storage);
  }
}
