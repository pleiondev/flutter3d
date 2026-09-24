/// The scene's lights, as a contributor's own stage reads them — `N6`.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why. It
/// has to be: the choosing is [Renderer._drawLightsFor]'s and the list is
/// `renderer_light_list.dart`'s, both private, and the point of this type is
/// that a contributor gets the same answer a mesh would rather than a copy of
/// the question.
part of 'renderer.dart';

final class _ContributorLights implements ContributorLights {
  _ContributorLights(this._renderer);

  final Renderer _renderer;

  /// The view's lights while its contributors run, and null outside them.
  LightBuffer? _frame;
  RenderSettings _settings = const RenderSettings();

  /// Its own scratch rather than [Renderer._drawLights]: a contributor binds
  /// between mesh draws, and sharing the buffer would hand the next mesh a
  /// selection made for a puff of smoke.
  final LightBuffer _draw = LightBuffer();
  final ContributorLightInfoBlock _block = ContributorLightInfoBlock();

  /// Points this at [lights] for the contributors of one view.
  void begin(LightBuffer lights, RenderSettings settings) {
    _frame = lights;
    _settings = settings;
  }

  void end() => _frame = null;

  @override
  void bind(
    PassEncoder encoder,
    ShaderHandle stage, {
    required vm.Vector3 centre,
    required double radius,
  }) {
    final frame = _frame;
    if (frame == null) return;
    final renderer = _renderer;

    // The same three cases [Renderer._drawLightsFor] makes, with no channel
    // of its own to ask for: a contributor's draw is on every channel, as a
    // mesh is by default.
    final LightBuffer draw;
    if (frame.overflow == 0 && !frame.anyChannelled) {
      draw = frame;
    } else if (frame.overflow == 0) {
      draw = _draw..gatherMatchingFrom(frame, LightChannels.all);
    } else {
      draw = _draw
        ..gatherNearFrom(
          frame,
          centre,
          radius,
          // With cells a light that leaves the slots is still in the tail,
          // as for a mesh.
          fadeBand: renderer._clustersActive ? 0.0 : _settings.lightFadeBand,
        );
    }

    _block.lightPosition.setAll(0, draw.positions);
    _block.lightColor.setAll(0, draw.colors);
    _block.lightDirection.setAll(0, draw.directions);
    _block.lightCone.setAll(0, draw.cones);
    _block.slots[0] = draw.count.toDouble();
    encoder.bindBlock(stage, _block);
    renderer._bindLightList(
      encoder,
      stage,
      draw,
      renderer._buildLightList(frame),
    );
  }
}
