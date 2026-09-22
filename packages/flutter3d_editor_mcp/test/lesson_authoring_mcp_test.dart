/// `edu-01`'s own claim, driven through the real protocol rather than
/// through `Editing` calls in the same process: a five-step teardown, an
/// annotation and a clip plane, assembled from nothing but the tools this
/// server already had before `edu-01` started — `place`, `setField`,
/// `select` and `turn`. No tool here is new; the point of this file is that
/// none needed to be.
///
/// The same scenario as
/// `packages/flutter3d_editor_core/test/lesson_authoring_test.dart`, one
/// layer further out: that file proves the commands build the right
/// document when called directly against `Editing`, this one proves an
/// agent reaches the same commands through `tools/call` with no server code
/// written for `edu_step`/`edu_annotation`/`edu_clip_plane` at all — the
/// open vocabulary `doc/edu-00-interactive-format.md` §1 describes, exercised
/// over an actual socket rather than read from a docstring.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_editor_mcp/flutter3d_editor_mcp.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late MCPClient client;
  late ServerConnection connection;
  late String started;

  setUp(() async {
    workspace = Directory.systemTemp.createTempSync(
      'flutter3d_editor_mcp_lesson',
    );
    started = '${workspace.path}/engine-lesson.json';
    File(started).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'name': 'engine-lesson',
        'entities': <Object?>[
          <String, Object?>{
            'type': 'model',
            'name': 'engine-body',
            'at': <double>[0.0, 0.0, 0.0],
            'asset': 'assets/models/engine.f3d',
          },
        ],
      }),
    );

    final pipe = StreamChannelController<String>(sync: true);
    EditorMcpServer(pipe.local, session: EditorSession.open(started));

    client = MCPClient(
      Implementation(name: 'the suite', version: editorMcpVersion),
    );
    connection = client.connectServer(pipe.foreign);
    final ready = await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    expect(ready.capabilities.tools, isNotNull);
    connection.notifyInitialized();
  });

  tearDown(() async {
    await client.shutdown();
    workspace.deleteSync(recursive: true);
  });

  Future<({bool did, String says})> call(
    String name, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    final result = await connection.callTool(
      CallToolRequest(name: name, arguments: arguments),
    );
    final content = result.content.single;
    expect(content.isText, isTrue, reason: '$name answered with $content');
    return (did: result.isError != true, says: (content as TextContent).text);
  }

  test(
    'a five-step teardown is assembled from place/setField/select/turn alone',
    () async {
      // Entity 0 is the model the level started with. `place` always adds
      // to the end of the same list, so every index below follows from the
      // order these calls are made in — the same thing an agent reading
      // this server's own `list` output between calls would see.
      final sequencePlaced = await call('place', <String, Object?>{
        'kind': 'entity',
        'what': 'edu_sequence',
        'at': <double>[0.0, 0.0, 0.0],
      });
      expect(sequencePlaced.did, isTrue, reason: sequencePlaced.says);
      const sequenceIndex = 1;
      expect(
        (await call('setField', {
          'key': 'name',
          'value': 'engine-teardown',
        })).did,
        isTrue,
      );
      expect(
        (await call('setField', {
          'key': 'title',
          'value': 'Разборка двигателя',
        })).did,
        isTrue,
      );
      expect(
        (await call('setField', {'key': 'steps', 'value': <String>[]})).did,
        isTrue,
      );

      const captions = <String>[
        'Двигатель в сборе',
        'Снимаем крышку клапанов',
        'Момент затяжки',
        'Снимаем прокладку',
        'Готово',
      ];
      final stepNames = <String>[];
      for (var i = 0; i < captions.length; i++) {
        final name = 'step-${i + 1}';
        final placed = await call('place', <String, Object?>{
          'kind': 'entity',
          'what': 'edu_step',
          'at': <double>[1.0, 1.5, -0.5],
        });
        expect(placed.did, isTrue, reason: placed.says);
        expect(
          (await call('setField', {'key': 'name', 'value': name})).did,
          isTrue,
        );
        expect(
          (await call('setField', {
            'key': 'caption',
            'value': captions[i],
          })).did,
          isTrue,
        );

        stepNames.add(name);
        expect(
          (await call('select', {
            'kind': 'entity',
            'index': sequenceIndex,
          })).did,
          isTrue,
        );
        expect(
          (await call('setField', {
            'key': 'steps',
            'value': List<String>.of(stepNames),
          })).did,
          isTrue,
        );
      }

      // Step two's valve cover lifts a quarter metre. Entity 3 is step-2:
      // entity 1 is the sequence, entities 2..6 are the five steps in order.
      const stepTwoIndex = 3;
      expect(
        (await call('select', {'kind': 'entity', 'index': stepTwoIndex})).did,
        isTrue,
      );
      expect(
        (await call('setField', {
          'key': 'offsets',
          'value': <String, Object?>{
            'engine-body#valve_cover': <double>[0.0, 0.25, 0.0],
          },
        })).did,
        isTrue,
      );

      // An annotation, attached to the same node.
      final annotationPlaced = await call('place', <String, Object?>{
        'kind': 'entity',
        'what': 'edu_annotation',
        'at': <double>[1.0, 1.5, -0.5],
      });
      expect(annotationPlaced.did, isTrue, reason: annotationPlaced.says);
      expect(
        (await call('setField', {'key': 'name', 'value': 'note-1'})).did,
        isTrue,
      );
      expect(
        (await call('setField', {
          'key': 'widget',
          'value': 'torque-spec-card',
        })).did,
        isTrue,
      );
      expect(
        (await call('setField', {
          'key': 'attachTo',
          'value': 'engine-body#valve_cover',
        })).did,
        isTrue,
      );
      expect(
        (await call('select', {'kind': 'entity', 'index': stepTwoIndex})).did,
        isTrue,
      );
      expect(
        (await call('setField', {
          'key': 'annotations',
          'value': <String>['note-1'],
        })).did,
        isTrue,
      );

      // A clip plane, dropped and turned — `turn` is the same tool every
      // other entity already answers to; nothing new was registered for
      // `edu_clip_plane`.
      final clipPlaced = await call('place', <String, Object?>{
        'kind': 'entity',
        'what': 'edu_clip_plane',
        'at': <double>[0.0, 1.0, 0.0],
      });
      expect(clipPlaced.did, isTrue, reason: clipPlaced.says);
      expect(
        (await call('setField', {'key': 'name', 'value': 'cutaway-1'})).did,
        isTrue,
      );
      final turned = await call('turn', {'by': 1.5707963267948966});
      expect(turned.did, isTrue, reason: turned.says);

      // No brush and no light in this minimal fixture, so validate has its
      // own two complaints about the level as a *playable space* — neither
      // of them about the `edu_*` entities, which is the thing this test is
      // actually checking: an open vocabulary raises nothing about a type
      // it has never heard of.
      final validated = await call('validate');
      expect(validated.says, isNot(contains('edu_')));

      final saved = await call('save', <String, Object?>{
        'path': '${workspace.path}/finished.json',
      });
      expect(saved.did, isTrue, reason: saved.says);

      // Read back with the same `Level`/vocabulary this whole format rests
      // on — not through the MCP session, which never had to learn what an
      // `edu_step` is to get this far.
      final finished = Level.fromJson(
        jsonDecode(File('${workspace.path}/finished.json').readAsStringSync())
            as Map<String, Object?>,
      );
      final sequence = finished.named('engine-teardown')!;
      expect((sequence.properties['steps']! as List).cast<String>(), stepNames);

      final registry = vocabularyOf(finished);
      for (final type in <String>[
        'edu_sequence',
        'edu_step',
        'edu_annotation',
        'edu_clip_plane',
      ]) {
        expect(registry.knows(type), isTrue, reason: type);
      }

      final stepTwo = finished.named('step-2')!;
      expect(stepTwo.properties['offsets'], <String, Object?>{
        'engine-body#valve_cover': <double>[0.0, 0.25, 0.0],
      });
      expect(
        (stepTwo.properties['annotations']! as List).cast<String>(),
        <String>['note-1'],
      );

      final note = finished.named('note-1')!;
      expect(note.string('widget'), 'torque-spec-card');

      final clip = finished.named('cutaway-1')!;
      expect(clip.yaw, closeTo(1.5707963267948966, 1e-4));
    },
  );
}
