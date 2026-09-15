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
    // `selectElements` is the one command named differently from the tool
    // that reaches it: `select` predates the command (`tut-05`) and keeps
    // its own historic name and JSON shape (`objects`/`object`/`level`/
    // `elements`) rather than being renamed to match — every existing MCP
    // client already calls it `select`.
    const differentTool = <String, String>{'selectElements': 'select'};
    final uncovered = modelCommandNames
        .toSet()
        .difference(namesOf(modelTools))
        .difference(differentTool.keys.toSet());
    expect(
      uncovered,
      isEmpty,
      reason:
          'a command exists that this server cannot call, and an agent '
          'reading tools/list has no way to find out that it is missing',
    );
    for (final MapEntry<String, String> renamed in differentTool.entries) {
      expect(
        namesOf(modelTools),
        contains(renamed.value),
        reason: '${renamed.key} is meant to be reachable as "${renamed.value}"',
      );
    }
  });

  test('every tool is a command or one of the named session verbs', () {
    const beyondTheCommands = <String>{
      'list',
      'listMaterials',
      // `tut-05`: runs a real command (`SelectElements`) underneath now, but
      // under this tool's own historic name and JSON shape rather than the
      // command's — see the "every model command is offered as a tool" test
      // above for the other half of that exception.
      'select',
      // `tut-03`: adjusts whatever step is on top of the undo stack, of
      // whichever command that step happens to be — there is no one
      // command name this tool could equal.
      'amend',
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
      // `paintWeights` used to be here too, as a session recipe over a
      // function that could not be a command — it now has a real one
      // (`PaintWeights`) behind it, runs through `_command('paintWeights')`
      // like every other command tool, and its tool name equals its own
      // command name, so it is not one of these exceptions any more.
      'autoRig',
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

    test('autoRig through the session appears in the journal as setRig, '
        'and undo takes back the whole rig — doc-36d', () async {
      final session = ModelSession(ModelHistory(const ModelProject()));
      await toolNamed(
        'addPrimitive',
      ).run(session, <String, Object?>{'kind': 'box'});
      await toolNamed('bakeToMesh').run(session, <String, Object?>{'id': 1});

      const markers = <String, List<double>>{
        'hips': <double>[0, 1.0, 0],
        'spine': <double>[0, 1.2, 0],
        'chest': <double>[0, 1.4, 0],
        'neck': <double>[0, 1.6, 0],
        'head': <double>[0, 1.75, 0],
        'leftShoulder': <double>[0.2, 1.4, 0],
        'leftElbow': <double>[0.5, 1.4, 0],
        'leftWrist': <double>[0.8, 1.4, 0],
        'leftHip': <double>[0.1, 1.0, 0],
        'leftKnee': <double>[0.1, 0.5, 0],
        'leftAnkle': <double>[0.1, 0.05, 0],
      };

      final rigged = await toolNamed('autoRig').run(session, <String, Object?>{
        'template': 'humanoid',
        'markers': markers,
        'skinObjectId': 1,
      });
      expect(rigged.did, isTrue, reason: rigged.says);
      expect(session.history.project.skeletons, hasLength(1));
      expect(session.history.project[1]!.skeletonIndex, 0);

      // The whole point of `doc-36d`: today's auto-rig used to commit a
      // `ReplaceDocument`, which `command.dart` deliberately keeps out of
      // `modelCommandNames` — so it never reached the journal at all. It is
      // `setRig` now.
      expect(session.history.journal.last.name, 'setRig');
      expect(session.history.journal.last, isA<SetRig>());

      expect(session.history.canUndo, isTrue);
      expect(session.history.undo(), isTrue);
      expect(session.history.project.skeletons, isEmpty);
      expect(session.history.project[1]!.skeletonIndex, isNull);
      expect(session.history.project.objects, hasLength(1));
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
