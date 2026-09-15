/// What this server offers, held against the list of commands that exists.
///
/// **The drift this file exists to stop has a shape.** `modelCommandNames`
/// lives beside the sealed hierarchy it describes, and a server keeping its
/// own copy is a server that silently cannot call the thirty-ninth command,
/// with nothing to say so until somebody asks for it. So the copy is checked,
/// both ways round, rather than trusted.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  Set<String> namesOf(Iterable<ModelTool> tools) =>
      tools.map((ModelTool it) => it.name).toSet();

  test('every model command is offered as a tool', () {
    expect(
      modelCommandNames.toSet().difference(namesOf(modelTools)),
      isEmpty,
      reason:
          'a command exists that this server cannot call, and an agent '
          'reading tools/list has no way to find out that it is missing',
    );
  });

  test('every tool is a command or one of the named session verbs', () {
    const beyondTheCommands = <String>{
      'list',
      'listMaterials',
      'select',
      'undo',
      'redo',
      'check',
      'save',
      'export',
      'import',
      'journal',
      'cleanup',
      'makeGameReady',
      'buildFrom',
      'inspect',
      // `anim-30`: session recipes over real functions that are not, and
      // cannot be (`command.dart`'s own sealed hierarchy), a `ModelCommand`
      // — see `model_session.dart`'s own "anim-30" section. `addShape` is
      // the one exception with a command underneath it (`AddShapeFromMesh`,
      // already offered as `addShapeFromMesh` too); it is a second name
      // for that same command, not a session recipe, and belongs here for
      // the same reason: this set is "what a tool is besides its own
      // command name," and `addShape`'s own command name is not "addShape".
      'autoRig',
      'paintWeights',
      'retargetClip',
      'bakeIk',
      'bakeDrivers',
      'addShape',
      'validateRig',
    };
    expect(
      namesOf(modelTools).difference(modelCommandNames.toSet()),
      beyondTheCommands,
      reason:
          'a tool was added or dropped that is not one of the document '
          'commands; say what it is here so the set stays a decision',
    );
  });

  test('no tool is offered twice', () {
    expect(namesOf(modelTools), hasLength(modelTools.length));
  });

  test('every tool describes itself in a sentence', () {
    for (final offered in modelTools) {
      expect(
        offered.tool.description,
        isNotNull,
        reason:
            '${offered.name} has no description, so nothing tells an agent '
            'when to call it',
      );
      expect(offered.tool.description!.length, greaterThan(40));
    }
  });

  test(
    'an argument the format cannot read is refused, not defaulted',
    () async {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final rename = modelTools.firstWhere(
        (ModelTool it) => it.name == 'rename',
      );
      final refused = await rename.run(session, <String, Object?>{
        'id': 'not a number',
        'to': 'anything',
      });
      expect(refused.did, isFalse);
      expect(refused.says, contains('cannot be read'));
    },
  );

  test('a command that runs is recorded, one that refuses is not', () async {
    final session = ModelSession(ModelHistory(const ModelProject()));
    final addPrimitive = modelTools.firstWhere(
      (ModelTool it) => it.name == 'addPrimitive',
    );
    final rename = modelTools.firstWhere((ModelTool it) => it.name == 'rename');

    await addPrimitive.run(session, <String, Object?>{'kind': 'box'});
    // Refuses: there is no object 99 yet.
    await rename.run(session, <String, Object?>{'id': 99, 'to': 'ghost'});

    final journaled = session.journal(
      '${Directory.systemTemp.createTempSync('model_mcp_test').path}/j.jsonl',
    );
    expect(journaled.says, contains('wrote 1 journal lines'));
  });

  group('refusals the skill quotes verbatim', () {
    ModelTool toolNamed(String name) =>
        modelTools.firstWhere((ModelTool it) => it.name == name);

    test('a mesh command on a still-parametric object', () async {
      final session = ModelSession(ModelHistory(const ModelProject()));
      await toolNamed(
        'addPrimitive',
      ).run(session, <String, Object?>{'kind': 'cylinder'});
      session.select(objects: <int>[1]);
      final refused = await toolNamed(
        'extrude',
      ).run(session, <String, Object?>{'distance': 1.0});
      expect(refused.did, isFalse);
      expect(refused.says, contains('Convert it to a mesh first'));
    });

    test('setParametric on a mesh that has been baked', () async {
      final session = ModelSession(ModelHistory(const ModelProject()));
      await toolNamed(
        'addPrimitive',
      ).run(session, <String, Object?>{'kind': 'box'});
      await toolNamed('bakeToMesh').run(session, <String, Object?>{'id': 1});
      final refused = await toolNamed('setParametric').run(
        session,
        <String, Object?>{
          'id': 1,
          'to': <String, Object?>{
            'shape': 'cuboid',
            'size': <double>[1, 1, 1],
          },
        },
      );
      expect(refused.did, isFalse);
      expect(refused.says, contains('a mesh has no parameters to set'));
    });

    test('save with no path and none from opening', () async {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final refused = await toolNamed(
        'save',
      ).run(session, const <String, Object?>{});
      expect(refused.did, isFalse);
      expect(refused.says, contains('no path of its own'));
    });

    test(
      'removeMaterial or duplicateMaterial on a row that is not there',
      () async {
        final session = ModelSession(ModelHistory(const ModelProject()));
        final refused = await toolNamed(
          'removeMaterial',
        ).run(session, <String, Object?>{'index': 4});
        expect(refused.did, isFalse);
        expect(refused.says, contains('there is no material 4'));
      },
    );
  });

  group('the rig and keyframe tools reach the real commands, not just '
      'a matching schema', () {
    ModelTool toolNamed(String name) =>
        modelTools.firstWhere((ModelTool it) => it.name == name);

    test('setProfileLimits changes the project\'s own limits', () async {
      final session = ModelSession(ModelHistory(const ModelProject()));
      final result = await toolNamed(
        'setProfileLimits',
      ).run(session, <String, Object?>{'maxJoints': 32, 'maxInfluences': 2});
      expect(result.did, isTrue);
      expect(session.history.project.profile.maxJoints, 32);
      expect(session.history.project.profile.maxInfluences, 2);
    });

    test('addJoint and mirrorJoints refuse a skeleton that is not there — '
        'a real refusal from the command, not a schema mismatch', () async {
      final session = ModelSession(ModelHistory(const ModelProject()));
      await toolNamed(
        'addPrimitive',
      ).run(session, <String, Object?>{'kind': 'box'});

      final addJoint = await toolNamed(
        'addJoint',
      ).run(session, <String, Object?>{'skeletonIndex': 0, 'objectId': 1});
      expect(addJoint.did, isFalse);
      expect(addJoint.says, contains('there is no skeleton 0'));

      final mirror = await toolNamed('mirrorJoints').run(
        session,
        <String, Object?>{
          'skeletonIndex': 0,
          'axis': 0,
          'jointMirror': <String, Object?>{'0': 1},
        },
      );
      expect(mirror.did, isFalse);
      expect(mirror.says, contains('there is no skeleton 0'));
    });

    test('addShapeFromMesh, setShapeWeight, renameShape and deleteShape all '
        'reach the real shape set', () async {
      final session = ModelSession(ModelHistory(const ModelProject()));
      await toolNamed(
        'addPrimitive',
      ).run(session, <String, Object?>{'kind': 'box'});
      await toolNamed('bakeToMesh').run(session, <String, Object?>{'id': 1});

      final added = await toolNamed(
        'addShapeFromMesh',
      ).run(session, <String, Object?>{'id': 1, 'shapeName': 'smile'});
      expect(added.did, isTrue);
      expect(session.history.project[1]!.shapeSet.keys.single.name, 'smile');

      final weighted = await toolNamed('setShapeWeight').run(
        session,
        <String, Object?>{'id': 1, 'shapeIndex': 0, 'weight': 0.6},
      );
      expect(weighted.did, isTrue);
      expect(session.history.project[1]!.shapeSet.weights, <double>[0.6]);

      final renamed = await toolNamed(
        'renameShape',
      ).run(session, <String, Object?>{'id': 1, 'shapeIndex': 0, 'to': 'grin'});
      expect(renamed.did, isTrue);
      expect(session.history.project[1]!.shapeSet.keys.single.name, 'grin');

      final deleted = await toolNamed(
        'deleteShape',
      ).run(session, <String, Object?>{'id': 1, 'shapeIndex': 0});
      expect(deleted.did, isTrue);
      expect(session.history.project[1]!.shapeSet.keys, isEmpty);
    });

    test('setKey, setInterpolation, moveKeys, setTangent and deleteKeys all '
        'reach a real track', () async {
      var project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'a',
          geometry: const SocketGeometry(),
          transform: Matrix4.identity(),
        ),
      );
      project = project.copyWith(
        clips: <ProjectClip>[
          ProjectClip(
            name: 'idle',
            tracks: <ProjectTrack>[
              ProjectTrack(
                objectId: 1,
                track: AnimationTrack(
                  nodeIndex: 0,
                  path: AnimationPath.translation,
                  interpolation: AnimationInterpolation.linear,
                  componentCount: 3,
                  times: Float32List.fromList(<double>[0, 1]),
                  values: Float32List.fromList(<double>[0, 0, 0, 1, 1, 1]),
                ),
              ),
            ],
          ),
        ],
      );
      final session = ModelSession(ModelHistory(project));

      final keyed = await toolNamed('setKey').run(session, <String, Object?>{
        'clipIndex': 0,
        'trackIndex': 0,
        'time': 0.5,
        'values': <double>[5, 5, 5],
      });
      expect(keyed.did, isTrue);
      expect(
        session.history.project.clips.single.tracks.single.track.keyCount,
        3,
      );

      final interpolated = await toolNamed('setInterpolation').run(
        session,
        <String, Object?>{
          'clipIndex': 0,
          'trackIndex': 0,
          'interpolation': 'step',
        },
      );
      expect(interpolated.did, isTrue);
      expect(
        session.history.project.clips.single.tracks.single.track.interpolation,
        AnimationInterpolation.step,
      );

      final moved = await toolNamed('moveKeys').run(session, <String, Object?>{
        'clipIndex': 0,
        'trackIndex': 0,
        'indices': <int>[0],
        'deltaTime': 10.0,
      });
      expect(moved.did, isTrue);

      final tangented = await toolNamed('setTangent').run(
        session,
        <String, Object?>{'clipIndex': 0, 'trackIndex': 0, 'index': 0},
      );
      expect(tangented.did, isTrue);

      final deleted = await toolNamed('deleteKeys').run(
        session,
        <String, Object?>{
          'clipIndex': 0,
          'trackIndex': 0,
          'indices': <int>[0],
        },
      );
      expect(deleted.did, isTrue);
      expect(
        session.history.project.clips.single.tracks.single.track.keyCount,
        2,
      );
    });

    test(
      'poseJoint keys the object\'s own live transform, not an argument',
      () async {
        var project = const ModelProject().added(
          (int id) => ModelObject(
            id: id,
            name: 'a',
            geometry: const SocketGeometry(),
            transform: Matrix4.identity()..setTranslationRaw(1, 2, 3),
          ),
        );
        project = project.copyWith(
          clips: <ProjectClip>[
            const ProjectClip(name: 'idle', tracks: <ProjectTrack>[]),
          ],
        );
        final session = ModelSession(ModelHistory(project));

        final posed = await toolNamed('poseJoint').run(
          session,
          <String, Object?>{
            'joint': 1,
            'path': 'translation',
            'clipIndex': 0,
            'frame': 0,
          },
        );
        expect(posed.did, isTrue);
        final track = session.history.project.clips.single.tracks.single.track;
        expect(track.path, AnimationPath.translation);
        final out = Float32List(3);
        track.sample(0.0, out);
        expect(out, <double>[1, 2, 3]);
      },
    );

    test('extractRootMotion and bakeRootMotionIntoClip reach a real track, '
        'exactly reversing each other', () async {
      var project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'a',
          geometry: const SocketGeometry(),
          transform: Matrix4.identity(),
        ),
      );
      project = project.copyWith(
        clips: <ProjectClip>[
          ProjectClip(
            name: 'walk',
            tracks: <ProjectTrack>[
              ProjectTrack(
                objectId: 1,
                track: AnimationTrack(
                  nodeIndex: 0,
                  path: AnimationPath.translation,
                  interpolation: AnimationInterpolation.linear,
                  componentCount: 3,
                  times: Float32List.fromList(<double>[0, 1]),
                  values: Float32List.fromList(<double>[0, 0, 0, 2, 0, 0]),
                ),
              ),
            ],
          ),
        ],
      );
      final session = ModelSession(ModelHistory(project));

      final extracted = await toolNamed(
        'extractRootMotion',
      ).run(session, <String, Object?>{'clipIndex': 0, 'rootJoint': 1});
      expect(extracted.did, isTrue);
      final flat = session.history.project.clips.single.tracks.single.track;
      final out = Float32List(3);
      flat.sample(1.0, out);
      expect(out, <double>[0, 0, 0]);

      final baked = await toolNamed(
        'bakeRootMotionIntoClip',
      ).run(session, <String, Object?>{'clipIndex': 0, 'rootJoint': 1});
      expect(baked.did, isTrue);
      final restored = session.history.project.clips.single.tracks.single.track;
      restored.sample(1.0, out);
      expect(out, <double>[2, 0, 0]);
      expect(session.history.project.clips.single.extras, isNull);
    });

    test('addSkeleton, bindSkin and addClip reach the real project — a '
        'skeleton and a clip neither existed before', () async {
      final project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'a',
          geometry: const SocketGeometry(),
          transform: Matrix4.identity(),
        ),
      );
      final session = ModelSession(ModelHistory(project));

      final skeleton = await toolNamed(
        'addSkeleton',
      ).run(session, <String, Object?>{'skeletonName': 'rig'});
      expect(skeleton.did, isTrue);
      expect(session.history.project.skeletons.single.name, 'rig');

      final bound = await toolNamed(
        'bindSkin',
      ).run(session, <String, Object?>{'objectId': 1, 'skeletonIndex': 0});
      expect(bound.did, isTrue);
      expect(session.history.project[1]!.skeletonIndex, 0);

      final clip = await toolNamed(
        'addClip',
      ).run(session, <String, Object?>{'clipName': 'idle'});
      expect(clip.did, isTrue);
      expect(session.history.project.clips.single.name, 'idle');
      expect(session.history.project.clips.single.tracks, isEmpty);
    });

    test(
      'removeNode reaches the real command: it deletes the node and '
      'unlinks a dangling reference to it, not just a schema match',
      () async {
        final session = ModelSession(
          ModelHistory(
            ModelProject(
              materials: <ProjectMaterial>[
                ProjectMaterial(surface: SurfaceMaterial()),
              ],
            ),
          ),
        );
        final added = await toolNamed('addNode').run(session, <String, Object?>{
          'materialIndex': 0,
          'kind': 'color',
          'fields': <String, Object?>{
            'value': <double>[1, 0, 0, 1],
          },
        });
        expect(added.did, isTrue);
        final colorId =
            session.history.project.materials.single.graph!.nodes.single.id;

        final addedOutput = await toolNamed(
          'addNode',
        ).run(session, <String, Object?>{'materialIndex': 0, 'kind': 'output'});
        expect(addedOutput.did, isTrue);
        final outputId =
            session.history.project.materials.single.graph!.nodes.last.id;

        final linked = await toolNamed('link').run(session, <String, Object?>{
          'materialIndex': 0,
          'nodeId': outputId,
          'input': 'result',
          'from': colorId,
        });
        expect(linked.did, isTrue);

        final removed = await toolNamed('removeNode').run(
          session,
          <String, Object?>{'materialIndex': 0, 'nodeId': colorId},
        );
        expect(removed.did, isTrue);

        final graph = session.history.project.materials.single.graph!;
        expect(graph.nodeById(colorId), isNull);
        final output = graph.nodeById(outputId)! as OutputTextureNode;
        expect(output.result, isNull);
      },
    );
  });
}
