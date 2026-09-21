/// Unwrapping a level's brush faces onto an atlas, and baking the light the
/// walls throw on each other into it.
///
/// Quoted by `lightmap_bake.md` and shown whole in the Source tab.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class LightmapBakeDemo extends ShowcaseDemo {
  late final String _report;

  double lightX = 2.0;
  double bounces = 1.0;
  double samples = 8.0;
  double texels = 2.0;

  bool _dirty = true;
  bool _busy = false;
  ui.Image? _atlas;
  String _stats = '';

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = Material(
      name: 'closet',
      baseColor: Vector4(0.8, 0.8, 0.7, 1.0),
    );
    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    if (_dirty && !_busy) {
      _dirty = false;
      _busy = true;
      unawaited(_rebake().whenComplete(() => _busy = false));
    }
  }

  /// Bakes the closet again with whatever the sliders say, and turns the
  /// atlas into a picture: each texel's irradiance, clamped to what a screen
  /// can show.
  Future<void> _rebake() async {
    // #region live
    final Level level = Level(
      name: 'closet',
      brushes: <Brush>[
        Brush(centre: Vector3(2, 0, 2), size: Vector3(4, 0.2, 4)),
        Brush(centre: Vector3(2, 2, 0), size: Vector3(4, 4, 0.2)),
      ],
      lights: <LevelLight>[
        LevelLight(position: Vector3(lightX, 3, 2), intensity: 6.0),
      ],
    );
    final LightmapLayout layout = LightmapLayout.plan(
      level,
      texelsPerMetre: texels,
    );
    final Lightmap lightmap = LightmapBaker(
      bounces: bounces.round(),
      samples: samples.round(),
    ).bake(level, layout: layout);
    // #endregion live
    // A closet's light is a small number, so the picture is exposed for the
    // brightest texel in it, the way a photograph would be.
    var brightest = 1e-6;
    for (var y = 0; y < lightmap.height; y++) {
      for (var x = 0; x < lightmap.width; x++) {
        final Vector3 light = lightmap.irradianceAt(x, y);
        brightest = math.max(brightest, math.max(light.x, math.max(light.y, light.z)));
      }
    }
    final Uint8List rgba = Uint8List(lightmap.texelCount * 4);
    var lit = 0;
    for (var y = 0; y < lightmap.height; y++) {
      for (var x = 0; x < lightmap.width; x++) {
        final Vector3 light = lightmap.irradianceAt(x, y);
        final int at = (y * lightmap.width + x) * 4;
        // Square-rooted, since a screen shows most of its range in the darks.
        rgba[at] = (math.sqrt(light.x / brightest) * 255).round();
        rgba[at + 1] = (math.sqrt(light.y / brightest) * 255).round();
        rgba[at + 2] = (math.sqrt(light.z / brightest) * 255).round();
        rgba[at + 3] = 255;
        if (light.x + light.y + light.z > 0.0) lit++;
      }
    }
    final Completer<ui.Image> decoded = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      lightmap.width,
      lightmap.height,
      ui.PixelFormat.rgba8888,
      decoded.complete,
    );
    final ui.Image image = await decoded.future;
    _stats =
        '${layout.faces.length} faces in a ${layout.width}x${layout.height} '
        'atlas, $lit of ${lightmap.texelCount} texels lit';
    _atlas = image;
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) {
    final ui.Image? atlas = _atlas;
    return ColoredBox(
      color: const Color(0xFF14161A),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'the baked atlas: what each texel of the closet receives. $_stats',
              style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 15),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: atlas == null
                  ? const Center(child: Text('baking…'))
                  : Center(
                      child: AspectRatio(
                        aspectRatio: atlas.width / atlas.height,
                        child: RawImage(
                          image: atlas,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.none,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Light position',
      min: 0.4,
      max: 3.6,
      value: () => lightX,
      onChanged: (double v) {
        lightX = v;
        _dirty = true;
      },
      format: (double v) => '${v.toStringAsFixed(1)} m',
    ),
    SliderControl(
      'Bounces',
      min: 0,
      max: 3,
      value: () => bounces,
      onChanged: (double v) {
        bounces = v.roundToDouble();
        _dirty = true;
      },
      format: (double v) => v.round().toString(),
    ),
    SliderControl(
      'Samples per texel',
      min: 1,
      max: 32,
      value: () => samples,
      onChanged: (double v) {
        samples = v.roundToDouble();
        _dirty = true;
      },
      format: (double v) => v.round().toString(),
    ),
    SliderControl(
      'Texels per metre',
      min: 1,
      max: 8,
      value: () => texels,
      onChanged: (double v) {
        texels = v.roundToDouble();
        _dirty = true;
      },
      format: (double v) => v.round().toString(),
    ),
  ];

  static String _run() {
    // #region level
    final level = Level(
      name: 'closet',
      brushes: <Brush>[
        Brush(centre: Vector3(2, 0, 2), size: Vector3(4, 0.2, 4)),
        Brush(centre: Vector3(2, 2, 0), size: Vector3(4, 4, 0.2)),
      ],
      lights: <LevelLight>[
        LevelLight(position: Vector3(2, 3, 2), intensity: 6.0),
      ],
    );
    // #endregion level

    // #region layout
    final layout = LightmapLayout.plan(level, texelsPerMetre: 2.0);
    // #endregion layout

    // #region bake
    const baker = LightmapBaker(bounces: 1, samples: 8);
    final lightmap = baker.bake(level, layout: layout);
    final anyLight = lightmap.pixels.any((int byte) => byte > 0);
    // #endregion bake

    return '${layout.faces.length} faces packed into a '
        '${layout.width}x${layout.height} atlas\n'
        'the baked map is ${lightmap.width}x${lightmap.height}, '
        'and holds some light: $anyLight';
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the closet marker was not drawn');
    }
    if (!_report.contains('holds some light: true')) {
      throw StateError(
        'a room with a light in it should bake a lightmap '
        'that is not entirely black',
      );
    }
  }
}
