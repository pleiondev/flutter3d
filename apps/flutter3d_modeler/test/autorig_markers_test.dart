/// `anim-23`'s own unit coverage: the eight-to-eleven marker bridge
/// (`onScreenMarkerKeys`/`startingMarkers`/`deriveMarkers`), the bone
/// segments `createRig` binds against, the frontal-view screen-to-world
/// conversion, and `createRig` itself — building, binding, mirroring and
/// landing a rig as one journal step, including the row's own literal
/// acceptance: RobotExpressive gives a skeleton of no more than 64 bones in
/// exactly one history step.
///
///     flutter test test/autorig_markers_test.dart
library;

import 'dart:io';
import 'dart:ui' show Offset, Size;

import 'package:flutter3d/flutter3d.dart'
    show CameraNode, OrthographicProjection;
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/autorig_markers.dart';
import 'package:flutter3d_modeler/src/element_picking.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A tiny two-joint [BuiltRig] — `root` at the origin, `child` a unit above
/// it — the same shape `rig_template.dart`'s own tests use for checking the
/// geometry [boneSegmentsOf] reads back out.
BuiltRig _twoJointRig() {
  final objects = <ModelObject>[
    ModelObject(
      id: 1,
      name: 'root',
      geometry: const SocketGeometry(),
      transform: Matrix4.translation(Vector3(0, 1, 0)),
    ),
    ModelObject(
      id: 2,
      name: 'child',
      geometry: const SocketGeometry(),
      transform: Matrix4.translation(Vector3(0, 1, 0)),
      parent: 1,
    ),
  ];
  return BuiltRig(
    objects: objects,
    skeleton: ProjectSkeleton(
      joints: <int>[1, 2],
      inverseBindMatrices: <Matrix4>[
        Matrix4.inverted(Matrix4.translation(Vector3(0, 1, 0))),
        Matrix4.inverted(Matrix4.translation(Vector3(0, 2, 0))),
      ],
    ),
  );
}

/// A camera on `+Z`, looking down `-Z` (where a node with no rotation
/// already looks) — `element_picking_test.dart`'s own fixture shape, an
/// orthographic lens rather than a perspective one to match this dialog's
/// own.
PickingView _frontalView({
  double eyeZ = 5.0,
  Size size = const Size(200, 100),
}) => PickingView(
  camera: CameraNode(
    projection: const OrthographicProjection(height: 4.0, near: 0.1, far: 100),
  )..setPosition(0.0, 0.0, eyeZ),
  size: size,
);

/// [seed]'s own single object, wrapped in a fresh [ModelHistory] — every
/// `createRig` test that does not need a real mesh to bind against starts
/// here.
ModelHistory _historyWith(ModelObject object, {int nextId = 2}) =>
    ModelHistory(ModelProject(objects: <ModelObject>[object], nextId: nextId));

Map<String, Vector3> _humanoidMarkers() => deriveMarkers(
  RigTemplate.humanoid,
  startingMarkers(
    RigTemplate.humanoid,
    Aabb3.minMax(Vector3(-1, -1, -1), Vector3(1, 1, 1)),
  ),
);

void main() {
  group('onScreenMarkerKeys', () {
    test('humanoid is the eight-marker set the dialog draws', () {
      expect(onScreenMarkerKeys(RigTemplate.humanoid), <String>[
        'hips',
        'chest',
        'neck',
        'head',
        'leftShoulder',
        'leftWrist',
        'leftHip',
        'leftAnkle',
      ]);
    });

    test('quadruped has no elbow/knee to derive, so every required key is '
        'on screen', () {
      expect(
        onScreenMarkerKeys(RigTemplate.quadruped),
        requiredMarkers(RigTemplate.quadruped),
      );
    });
  });

  group('deriveMarkers', () {
    test('spine, elbow and knee are exact midpoints', () {
      final onScreen = startingMarkers(
        RigTemplate.humanoid,
        Aabb3.minMax(Vector3(-1, -1, -1), Vector3(1, 1, 1)),
      );
      final derived = deriveMarkers(RigTemplate.humanoid, onScreen);

      Vector3 mid(Vector3 a, Vector3 b) => (a + b) * 0.5;
      expect(derived['spine'], mid(onScreen['hips']!, onScreen['chest']!));
      expect(
        derived['leftElbow'],
        mid(onScreen['leftShoulder']!, onScreen['leftWrist']!),
      );
      expect(
        derived['leftKnee'],
        mid(onScreen['leftHip']!, onScreen['leftAnkle']!),
      );

      // Every key `requiredMarkers` names is now present.
      for (final key in requiredMarkers(RigTemplate.humanoid)) {
        expect(derived.containsKey(key), isTrue, reason: key);
      }
    });

    test('quadruped is left as given — nothing to derive', () {
      final onScreen = startingMarkers(
        RigTemplate.quadruped,
        Aabb3.minMax(Vector3(-1, -1, -1), Vector3(1, 1, 1)),
      );
      expect(deriveMarkers(RigTemplate.quadruped, onScreen), onScreen);
    });
  });

  group('startingMarkers', () {
    test(
      'every on-screen key is present, and left markers sit to one side',
      () {
        final bounds = Aabb3.minMax(Vector3(-1, -2, -1), Vector3(1, 2, 1));
        final markers = startingMarkers(RigTemplate.humanoid, bounds);
        for (final key in onScreenMarkerKeys(RigTemplate.humanoid)) {
          expect(markers.containsKey(key), isTrue, reason: key);
        }
        // Centreline markers sit on the mirror plane; the side ones do not.
        expect(markers['hips']!.x, 0.0);
        expect(markers['leftShoulder']!.x, isNot(0.0));
        expect(
          markers['leftAnkle']!.y,
          lessThan(bounds.min.y + (bounds.max.y - bounds.min.y) * 0.1),
          reason: 'the ankle should sit near the bottom of the bounds',
        );
        expect(markers['head']!.y, lessThan(bounds.max.y));
      },
    );
  });

  group('boneSegmentsOf', () {
    test('the root is a degenerate segment; the child spans root to child', () {
      final segments = boneSegmentsOf(_twoJointRig());
      expect(segments, hasLength(2));
      expect(segments[0].head, Vector3(0, 1, 0));
      expect(segments[0].tail, Vector3(0, 1, 0));
      expect(segments[0].name, 'root');
      expect(segments[1].head, Vector3(0, 1, 0));
      expect(segments[1].tail, Vector3(0, 2, 0));
      expect(segments[1].name, 'child');
    });
  });

  group('markerFromScreen', () {
    test('the screen centre lands on the view axis at depthZ', () {
      final view = _frontalView();
      final world = markerFromScreen(view, const Offset(100, 50), 1.0);
      expect(world.x, closeTo(0.0, 1e-6));
      expect(world.y, closeTo(0.0, 1e-6));
      expect(world.z, closeTo(1.0, 1e-6));
    });

    test('moving across the screen moves x, not depth', () {
      final view = _frontalView();
      final left = markerFromScreen(view, const Offset(50, 50), 0.5);
      final right = markerFromScreen(view, const Offset(150, 50), 0.5);
      expect(right.x, greaterThan(left.x));
      expect(left.z, closeTo(0.5, 1e-6));
      expect(right.z, closeTo(0.5, 1e-6));
    });
  });

  group('createRig', () {
    test('refuses a marker set missing a required key', () async {
      final history = _historyWith(
        ModelObject(
          id: 1,
          name: 'figure',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
        ),
      );
      final markers = _humanoidMarkers()..remove('head');
      final refused = await createRig(
        history: history,
        template: RigTemplate.humanoid,
        markers: markers,
        skinObjectId: 1,
        bind: (BindWeightsJobRequest request) => request.run(),
      );
      expect(refused, contains('missing markers'));
      expect(history.canUndo, isFalse);
    });

    test('refuses a skinObjectId that names nothing', () async {
      final history = _historyWith(
        ModelObject(
          id: 1,
          name: 'figure',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
        ),
      );
      final refused = await createRig(
        history: history,
        template: RigTemplate.humanoid,
        markers: _humanoidMarkers(),
        skinObjectId: 99,
        bind: (BindWeightsJobRequest request) => request.run(),
      );
      expect(refused, contains('there is no object'));
      expect(history.canUndo, isFalse);
    });

    test(
      'with no skinObjectId, lands the skeleton alone as one step',
      () async {
        final history = _historyWith(
          ModelObject(
            id: 1,
            name: 'figure',
            geometry: EditedGeometry(EditMesh.cuboid()),
            transform: Matrix4.identity(),
          ),
        );
        final refused = await createRig(
          history: history,
          template: RigTemplate.humanoid,
          markers: _humanoidMarkers(),
          bind: (BindWeightsJobRequest request) => request.run(),
        );
        expect(refused, isNull);
        expect(history.project.skeletons, hasLength(1));
        expect(history.project[1]!.skeletonIndex, isNull);
        expect(history.canUndo, isTrue);
        expect(history.undo(), isTrue);
        expect(history.canUndo, isFalse, reason: 'exactly one journal step');
        expect(history.project.skeletons, isEmpty);
      },
    );

    test('with primary weights off, binds the skeleton without touching the '
        'mesh', () async {
      final history = _historyWith(
        ModelObject(
          id: 1,
          name: 'figure',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
        ),
      );
      final refused = await createRig(
        history: history,
        template: RigTemplate.humanoid,
        markers: _humanoidMarkers(),
        skinObjectId: 1,
        bindPrimaryWeights: false,
        bind: (BindWeightsJobRequest request) => request.run(),
      );
      expect(refused, isNull);
      expect(history.project[1]!.skeletonIndex, 0);
      expect(history.canUndo, isTrue);
      expect(history.undo(), isTrue);
      expect(history.canUndo, isFalse, reason: 'exactly one journal step');
    });

    test('with primary weights on, the mesh actually carries a bind', () async {
      final mesh = EditMesh.cuboid();
      final history = _historyWith(
        ModelObject(
          id: 1,
          name: 'figure',
          geometry: EditedGeometry(mesh),
          transform: Matrix4.identity(),
        ),
      );
      final refused = await createRig(
        history: history,
        template: RigTemplate.humanoid,
        markers: _humanoidMarkers(),
        skinObjectId: 1,
        bind: (BindWeightsJobRequest request) => request.run(),
      );
      expect(refused, isNull);
      final rebound = history.project[1]!.geometry as EditedGeometry;
      var anyBound = false;
      for (var v = 0; v < rebound.mesh.vertexSlotCount; v++) {
        if (!rebound.mesh.isVertexAlive(v)) continue;
        if (weightsOf(rebound.mesh, v).isNotEmpty) anyBound = true;
      }
      expect(anyBound, isTrue, reason: 'binding should touch some vertex');
      expect(history.canUndo, isTrue);
      expect(history.undo(), isTrue);
      expect(history.canUndo, isFalse, reason: 'exactly one journal step');
    });

    test('a cancelled bind refuses without touching the history', () async {
      final history = _historyWith(
        ModelObject(
          id: 1,
          name: 'figure',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
        ),
      );
      final refused = await createRig(
        history: history,
        template: RigTemplate.humanoid,
        markers: _humanoidMarkers(),
        skinObjectId: 1,
        bind: (BindWeightsJobRequest request) async => null,
      );
      expect(refused, contains('cancelled'));
      expect(history.canUndo, isFalse);
    });
  });

  group('anim-23: RobotExpressive', () {
    test(
      'gives a skeleton of no more than 64 bones, in one history step',
      () async {
        final document = await GltfLoader().load(
          File(
            '../../packages/flutter3d_samples/assets/RobotExpressive.glb',
          ).readAsBytesSync(),
        );
        var project = fromModelDocument(document);
        // `import` alone leaves every mesh as flat `ImportedGeometry` — real
        // topology is a separate step, the same one `rig_pipeline_mcp_test
        // .dart`'s own `anim-30` scenario takes for the same reason.
        for (final object in project.objects) {
          if (object.geometry case ImportedGeometry(:final data)) {
            final (mesh, _, _) = importMeshData(data);
            project = project.withObject(
              object.copyWith(geometry: EditedGeometry(mesh)),
            );
          }
        }
        expect(
          project.objects.any((o) => o.geometry is EditedGeometry),
          isTrue,
        );

        // RobotExpressive's own skin comes across through `fromModelDocument`
        // already — `createRig` adds a second skeleton alongside it, so the
        // acceptance reads the one it just appended rather than assuming
        // there is only ever one in the project.
        final int skeletonsBefore = project.skeletons.length;

        final history = ModelHistory(project);
        // No `skinObjectId`/binding here — this row's own acceptance is about
        // the skeleton and the journal, not about whether RobotExpressive's
        // own node hierarchy happens to line up with a bind-weights pass one
        // marker set could ever get exactly right; `createRig`'s own binding
        // path is already covered above, against a mesh built for it.
        final refused = await createRig(
          history: history,
          template: RigTemplate.humanoid,
          markers: _humanoidMarkers(),
          bind: (BindWeightsJobRequest request) => request.run(),
        );
        expect(refused, isNull, reason: refused);
        expect(history.project.skeletons, hasLength(skeletonsBefore + 1));
        expect(
          history.project.skeletons.last.jointCount,
          lessThanOrEqualTo(64),
        );
        expect(history.canUndo, isTrue);
        expect(history.undo(), isTrue);
        expect(history.canUndo, isFalse, reason: 'exactly one history step');
      },
    );
  });
}
