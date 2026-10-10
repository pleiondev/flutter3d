/// Four marks a player has to tell apart, in the colours their roles give
/// them, drawn as someone missing a cone sees them or corrected for them, and
/// the same four in the colours a player chose instead.
///
/// Quoted by `colour_vision.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

// #region roles
/// What the colours on this page mean. A HUD asks for "danger", never for
/// red, so the player can move one of them without touching the others.
final ColorRoles _roles = ColorRoles(const <ColorRole>[
  ColorRole('danger', 'Danger', Color(0xFFD03A2C)),
  ColorRole('safe', 'Safe ground', Color(0xFF3C9A3A)),
  ColorRole('loot', 'Loot', Color(0xFFE8C547)),
  ColorRole('water', 'Water', Color(0xFF3A7BD5)),
]);

/// A player who picked from Okabe and Ito's eight in the Colours section:
/// each number is the place in `ColorRoles.choices`, nought being the
/// role's own colour. Vermillion, blue, yellow and sky blue.
GameSettings _chosen() => const GameSettings()
    .withValue(GameSettingKeys.colorRole('danger'), 7)
    .withValue(GameSettingKeys.colorRole('safe'), 6)
    .withValue(GameSettingKeys.colorRole('loot'), 5)
    .withValue(GameSettingKeys.colorRole('water'), 3);
// #endregion roles

/// The picture the page draws: as it is, as each deficiency sees it, or
/// corrected for each.
const List<String> _pictures = <String>[
  'As drawn',
  'Seen protan',
  'Seen deutan',
  'Seen tritan',
  'Corrected for protan',
  'Corrected for deutan',
  'Corrected for tritan',
];

final class ColourVisionDemo extends ShowcaseDemo {
  int picture = 2;
  bool playerColours = false;

  final GameSettings _defaults = const GameSettings();
  final GameSettings _player = _chosen();
  final List<(ColorRole, RenderMaterial)> _marks =
      <(ColorRole, RenderMaterial)>[];
  final Map<int, TextureHandle?> _tables = <int, TextureHandle?>{};
  late final GraphicsDevice _device;
  late LookSettings _look;

  @override
  void configureView(DemoContext context) => PostStage.frame(context);

  @override
  Scene build(DemoContext context) {
    _device = context.device;
    final Scene scene = Scene()
      ..ambientIntensity = 0.45 * Photometric.legacyUnit
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 10, depth: 6).build(),
          ),
          RenderMaterial(
            name: 'floor',
            baseColor: LinearColor.fromSrgb(0.5, 0.5, 0.52, 1.0),
          ),
          name: 'floor',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.5 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.9, -0.4)),
      );
    final DeviceMesh slab = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(1.4, 1.4, 0.4)).build(),
    );
    for (var i = 0; i < _roles.roles.length; i++) {
      final ColorRole role = _roles.roles[i];
      final material = RenderMaterial(name: role.name, roughness: 0.8);
      _marks.add((role, material));
      scene.add(
        MeshNode(slab, material, name: role.name)
          ..setPosition(-2.7 + i * 1.8, 0.7, 0.0),
      );
    }
    _paint();
    return scene;
  }

  // #region paint
  /// Each mark in the colour its role has for whoever is playing. A swatch
  /// is a display colour, so it is taken to linear light for the material.
  void _paint() {
    final GameSettings config = playerColours ? _player : _defaults;
    for (final (ColorRole role, RenderMaterial material) in _marks) {
      final Color c = _roles.of(role, config);
      material.baseColor = LinearColor.fromSrgb(
        _linear(c.r),
        _linear(c.g),
        _linear(c.b),
        1,
      );
    }
  }
  // #endregion paint

  static double _linear(double c) =>
      c < 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  // #region table
  /// The colour table for [picture]: a matrix baked into the strip the
  /// composite reads after the tone map, made once per choice.
  TextureHandle? _table(int picture) => _tables.putIfAbsent(picture, () {
    if (picture == 0) return null;
    final ColorVisionDeficiency kind =
        ColorVisionDeficiency.values[(picture - 1) % 3];
    final ColorVision vision = picture <= 3
        ? ColorVision.simulate(kind)
        : ColorVision.correct(kind);
    return vision.upload(_device);
  });

  @override
  RenderSettings settings(DemoContext context) {
    _look = LookSettings(lut: _table(picture));
    return RenderSettings(look: _look);
  }
  // #endregion table

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Picture',
      options: _pictures,
      index: () => picture,
      onChanged: (int i) => picture = i,
    ),
    ToggleControl(
      'The player\'s own colours',
      value: () => playerColours,
      onChanged: (bool v) {
        playerColours = v;
        _paint();
      },
    ),
  ];

  // #region lint
  /// How far apart danger and safe ground look to someone missing the
  /// middle cone, in CIE 1976 ΔE, in the colours [config] gives them —
  /// corrected for that first when [corrected].
  double _deutanGap(GameSettings config, {bool corrected = false}) {
    const ColorVision seen = ColorVision.simulate(ColorVisionDeficiency.deutan);
    const ColorVision fix = ColorVision.correct(ColorVisionDeficiency.deutan);
    (double, double, double) through(String name) {
      final Color c = _roles.of(_roles.named(name)!, config);
      final (double r, double g, double b) = corrected
          ? fix.applyEncoded(c.r, c.g, c.b)
          : (c.r, c.g, c.b);
      return seen.applyEncoded(r, g, b);
    }

    return ColorVision.difference(through('danger'), through('safe'));
  }
  // #endregion lint

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // The lint finds the pair a deutan runs together in the game's colours,
    // and nothing at all in the colours the player chose.
    final names = <String>['danger', 'safe', 'loot', 'water'];
    final found = _roles.confusions(names, _defaults);
    if (!found.any(
      (c) =>
          c.a == 'danger' &&
          c.b == 'safe' &&
          c.by == ColorVisionDeficiency.deutan,
    )) {
      throw StateError('the lint missed red against green for a deutan');
    }
    if (_roles.confusions(names, _player).isNotEmpty) {
      throw StateError('the player\'s colours still run together');
    }
    // As a deutan sees them: the game's red and green are closer than the
    // player's vermillion and blue, and closer than the correction leaves
    // them.
    final double asDrawn = _deutanGap(_defaults);
    final double remapped = _deutanGap(_player);
    final double corrected = _deutanGap(_defaults, corrected: true);
    if (!(asDrawn < 20.0 && remapped > 3 * asDrawn && corrected > asDrawn)) {
      throw StateError(
        'deutan gaps: as drawn $asDrawn, remapped $remapped, '
        'corrected $corrected',
      );
    }
    // #endregion check
    if (_table(picture) != null && !_look.gradesThroughLut) {
      throw StateError('the colour table would not be sampled this frame');
    }
    if (!passRan(frame, 'composite')) {
      throw StateError('the composite pass, which reads the table, is absent');
    }
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
  }
}
