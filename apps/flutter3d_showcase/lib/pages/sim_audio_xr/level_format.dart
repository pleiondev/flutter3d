/// The document a level is: brushes, entities and lights, and the validator
/// that reports what is wrong with one before it is ever played.
///
/// Quoted by `level_format.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class LevelFormatDemo extends ShowcaseDemo {
  late final String _report;

  double gap = -1.0;
  bool withSpawn = true;

  bool _dirty = true;
  late final MeshNode _first;
  late final MeshNode _second;
  late final MeshNode _spawn;
  late final List<MeshNode> _issues;

  static const int _lamps = 6;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 13.0
      ..pitch = 0.9
      ..yaw = 0.0;
    context.orbit.target.setValues(1.5, 0.0, 1.0);
  }

  @override
  Scene build(DemoContext context) {
    _report = _run();
    _first = blockNode(
      context,
      'brush 1',
      Vector3(4.0, 2.0, 4.0),
      Vector4(0.55, 0.65, 0.8, 1.0),
    );
    _second = blockNode(
      context,
      'brush 2',
      Vector3(4.0, 1.9, 4.0),
      Vector4(0.8, 0.65, 0.5, 1.0),
    );
    _spawn = ballNode(context, 'spawn', 0.35, Vector4(0.4, 0.9, 0.5, 1.0));
    _issues = <MeshNode>[
      for (var i = 0; i < _lamps; i++)
        ballNode(
          context,
          'issue $i',
          0.25,
          Vector4(0.9, 0.3, 0.3, 1.0),
          at: Vector3(-2.5 + i * 0.8, 0.3, 4.5),
        ),
    ];
    return sceneOf(<SceneNode>[
      floorNode(context, width: 16.0, depth: 12.0),
      _first,
      _second,
      _spawn,
      ..._issues,
    ]);
  }

  @override
  void update(DemoContext context, double dt) {
    if (!_dirty) return;
    _dirty = false;
    // #region live
    // The level of the first step, with the second brush slid along by the
    // slider (a negative gap is an overlap) and the spawn optional, written to
    // JSON, read back and validated.
    final Level level = Level(
      name: 'sample',
      brushes: <Brush>[
        Brush(centre: Vector3(0, 0, 0), size: Vector3(4, 2, 4)),
        Brush(centre: Vector3(4.0 + gap, 0, 0), size: Vector3(4, 2, 4)),
      ],
      entities: <EntityDef>[
        if (withSpawn) EntityDef(type: 'spawn', name: 'start'),
      ],
    );
    final Level reread = Level.fromJson(level.toJson());
    final List<LevelIssue> issues = LevelValidator(
      registry: EntityRegistry(const <EntityKind>[]),
    ).validate(reread);
    // #endregion live
    _first.setPosition(0.0, 1.0, 0.0);
    _second.setPosition(4.0 + gap, 0.95, 0.0);
    _spawn.visible = withSpawn;
    _spawn.setPosition(0.0, 2.35, 0.0);
    for (var i = 0; i < _lamps; i++) {
      _issues[i].visible = i < issues.length;
    }
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Gap between the brushes',
      min: -2.0,
      max: 2.0,
      value: () => gap,
      onChanged: (double v) {
        gap = v;
        _dirty = true;
      },
      format: (double v) => v < 0
          ? 'overlap ${(-v).toStringAsFixed(1)} m'
          : '${v.toStringAsFixed(1)} m',
    ),
    ToggleControl(
      'A spawn point',
      value: () => withSpawn,
      onChanged: (bool v) {
        withSpawn = v;
        _dirty = true;
      },
    ),
  ];

  static String _run() {
    // #region level
    // Two brushes that overlap by a metre, which nothing in this format
    // forbids outright but which the validator flags as worth a look.
    final level = Level(
      name: 'sample',
      brushes: <Brush>[
        Brush(centre: Vector3(0, 0, 0), size: Vector3(4, 2, 4)),
        Brush(centre: Vector3(3, 0, 0), size: Vector3(4, 2, 4)),
      ],
      entities: <EntityDef>[EntityDef(type: 'spawn', name: 'start')],
    );
    // #endregion level

    // #region write
    final json = level.toJson();
    final reread = Level.fromJson(json);
    // #endregion write

    // #region validate
    final validator = LevelValidator(
      registry: EntityRegistry(const <EntityKind>[]),
    );
    final issues = validator.validate(reread);
    // #endregion validate

    return '${reread.brushes.length} brushes round-tripped through JSON\n'
        '${issues.length} issue(s): ${issues.map((LevelIssue i) => i.message).join(' | ')}';
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the level marker was not drawn');
    }
    if (!_report.contains('2 brushes round-tripped')) {
      throw StateError('every brush should survive a trip through JSON');
    }
    if (_report.contains('0 issue(s)')) {
      throw StateError(
        'two overlapping brushes should be reported by the validator',
      );
    }
  }
}
