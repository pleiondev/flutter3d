/// What the glass does to a picture: a bright lamp throws ghosts and a halo
/// across the frame, the frame bows outwards or pinches in, and the colours
/// go through a table written by a grading tool.
///
/// Quoted by `lens_effects.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

// #region tables
/// A warm grade as a `.cube` file: the eight corners of the colour cube,
/// red running fastest. Black is lifted a little towards blue, white is
/// pulled towards amber, and everything between is blended from the corners.
const String _warmCube = '''
TITLE "Warm highlights"
LUT_3D_SIZE 2
0.04 0.02 0.06
1.00 0.10 0.02
0.06 0.92 0.04
1.00 0.96 0.10
0.02 0.06 0.80
0.95 0.10 0.78
0.06 0.95 0.86
1.00 0.97 0.88
''';

/// A contrast curve as a 1D `.cube`: the same S on each channel, darker
/// shadows and brighter highlights with the middle left where it was.
const String _curveCube = '''
TITLE "S curve"
LUT_1D_SIZE 5
0.00 0.00 0.00
0.15 0.15 0.15
0.50 0.50 0.50
0.85 0.85 0.85
1.00 1.00 1.00
''';
// #endregion tables

final class LensEffectsDemo extends ShowcaseDemo {
  bool flare = true;
  double halo = 0.5;
  double distortion = 0.15;

  /// 0 for no table, 1 for the warm 3D one, 2 for the 1D curve.
  int table = 1;

  late final CubeLut _warm;
  late final List<TextureHandle?> _strips;
  late LookSettings _look;

  @override
  void configureView(DemoContext context) => PostStage.frame(context);

  @override
  Scene build(DemoContext context) {
    // #region load
    _warm = CubeLut.parse(_warmCube);
    _strips = <TextureHandle?>[
      null,
      _warm.upload(context.device),
      CubeLut.parse(_curveCube).upload(context.device),
    ];
    // #endregion load

    // #region lamp
    // A lamp far brighter than the display can show, up and to the left, so
    // its glow is strong enough to flare and its ghosts cross the middle.
    final MeshNode lamp = MeshNode(
      DeviceMesh.upload(
        context.device,
        const SphereShape(radius: 0.25).build(),
      ),
      RenderMaterial(
        name: 'lamp',
        baseColor: LinearColor.fromSrgb(0.1, 0.1, 0.1, 1.0),
        emissive: LinearColor(1.0, 0.85, 0.6),
        emissiveStrength: 40.0 * Photometric.legacyNits,
      ),
      name: 'lamp',
    )..setPosition(-3.2, 2.8, -2.0);
    // #endregion lamp
    return PostStage.build(context).scene..add(lamp);
  }

  @override
  RenderSettings settings(DemoContext context) {
    // #region lens
    final BloomSettings bloom = BloomSettings(
      // Three levels rather than five keep the glow, and so each ghost,
      // tight enough to read as a disc rather than a wash.
      levels: 3,
      lensFlare: LensFlareSettings(enabled: flare, halo: halo),
    );
    _look = LookSettings(distortion: distortion, lut: _strips[table]);
    // #endregion lens
    return RenderSettings(bloom: bloom, look: _look);
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Lens flare',
      value: () => flare,
      onChanged: (bool v) => flare = v,
    ),
    SliderControl(
      'Halo',
      min: 0,
      max: 1,
      value: () => halo,
      onChanged: (double v) => halo = v,
    ),
    SliderControl(
      'Distortion (pincushion to barrel)',
      min: -0.4,
      max: 0.4,
      value: () => distortion,
      onChanged: (double v) => distortion = v,
      format: (double v) => v.toStringAsFixed(2),
    ),
    ChoiceControl(
      'Table',
      options: const <String>['None', 'Warm (3D)', 'S curve (1D)'],
      index: () => table,
      onChanged: (int i) => table = i,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // The flare is a pass of its own, drawn from the glow.
    if (flare && !passRan(frame, 'lens flare')) {
      throw StateError('the lens flare did not run: ${frame.skipped}');
    }
    // The table reads back what the file says at a corner, and a middle grey
    // comes out of it warmer than it went in: more red than blue.
    final (double r, double g, double b) = _warm.lookup(1.0, 1.0, 1.0);
    // Held as 32-bit floats, so compared to within a millionth.
    if ((r - 1.0).abs() > 1e-6 ||
        (g - 0.97).abs() > 1e-6 ||
        (b - 0.88).abs() > 1e-6) {
      throw StateError('white maps to ($r, $g, $b), not the file\'s corner');
    }
    final (double gr, _, double gb) = _warm.lookup(0.5, 0.5, 0.5);
    if (gr <= gb + 0.05) {
      throw StateError('mid grey is not warmer: red $gr, blue $gb');
    }
    if (table != 0 && (_strips[table] == null || !_look.gradesThroughLut)) {
      throw StateError('the table did not reach the device');
    }
    // The composite bends the frame and reads the table.
    if (!passRan(frame, 'composite')) {
      throw StateError('the composite pass is absent');
    }
    // #endregion check
  }
}
