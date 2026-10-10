/// The animation graph tools — N1: an agent sets a character's graph by
/// name over the project's clips, is told where a wrong one is wrong, and
/// removes it again.
///
///     dart test test/animation_graph_tools_test.dart
library;

import 'package:flutter3d_mcp/model.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

ModelTool _tool(String name) =>
    modelTools.firstWhere((ModelTool it) => it.name == name);

void main() {
  test('setAnimationGraph sets one over the clips, removeAnimationGraph '
      'takes it away', () async {
    final session = ModelSession(
      ModelHistory(
        const ModelProject(
          clips: <ProjectClip>[
            ProjectClip(name: 'idle', tracks: <ProjectTrack>[]),
            ProjectClip(name: 'walk', tracks: <ProjectTrack>[]),
          ],
        ),
      ),
    );
    final graph = <String, Object?>{
      'parameters': <Object?>[
        <String, Object?>{'name': 'speed', 'type': 'float'},
      ],
      'states': <Object?>[
        <String, Object?>{'name': 'idle', 'clip': 'idle'},
        <String, Object?>{'name': 'walk', 'clip': 'walk'},
      ],
      'transitions': <Object?>[
        <String, Object?>{
          'from': 'idle',
          'to': 'walk',
          'conditions': <Object?>[
            <String, Object?>{
              'parameter': 'speed',
              'compare': 'greater',
              'value': 0.1,
            },
          ],
          'duration': 0.2,
        },
      ],
    };
    final set = await _tool(
      'setAnimationGraph',
    ).run(session, <String, Object?>{'graphName': 'hero', 'graph': graph});
    expect(set.did, isTrue, reason: set.says);
    // Kept as it will be written: the entry, first by default, named.
    expect(session.history.project.animationGraphs['hero'], <String, Object?>{
      ...graph,
      'entry': 'idle',
    });

    final wrong = await _tool('setAnimationGraph').run(
      session,
      <String, Object?>{
        'graphName': 'hero',
        'graph': <String, Object?>{
          ...graph,
          'states': <Object?>[
            <String, Object?>{'name': 'idle', 'clip': 'idle', 'speed': 'slow'},
          ],
        },
      },
    );
    expect(wrong.did, isFalse);
    expect(wrong.says, contains('states[0].speed is "slow", not a number'));

    final removed = await _tool(
      'removeAnimationGraph',
    ).run(session, <String, Object?>{'graphName': 'hero'});
    expect(removed.did, isTrue);
    expect(session.history.project.animationGraphs, isEmpty);
    final again = await _tool(
      'removeAnimationGraph',
    ).run(session, <String, Object?>{'graphName': 'hero'});
    expect(again.did, isFalse);
    expect(again.says, contains('there is no animation graph "hero"'));
  });
}
