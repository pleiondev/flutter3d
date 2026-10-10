/// A project's animation graphs, set and removed by name — the modeller's
/// half of N1: the graph a game runs for a character, authored beside the
/// clips it plays and exported with them.
part of 'command.dart';

/// Sets graph [graphName] to [graph], as `AnimationGraphJson` writes one,
/// replacing one of that name.
///
/// **Refused unless it would run.** The JSON must read as a graph, and the
/// graph must have none of `AnimationStateMachine.problems` against the
/// project's own clips: a state that plays a clip the project does not
/// have is a character frozen in the game, and the sentence is cheaper
/// here.
final class SetAnimationGraph extends ModelCommand {
  const SetAnimationGraph({required this.graphName, required this.graph});

  final String graphName;
  final Map<String, Object?> graph;

  @override
  String get name => 'setAnimationGraph';

  @override
  String get says => 'set animation graph "$graphName"';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'graphName': graphName,
    'graph': graph,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (graphName.isEmpty) return Outcome.refused('a graph needs a name');
    final AnimationStateMachine machine;
    try {
      machine = AnimationGraphJson.decode(graph);
    } on AnimationGraphFormatException catch (error) {
      return Outcome.refused(error.message);
    }
    final problems = machine.problems(<AnimationClip>[
      for (final ProjectClip clip in project.clips)
        if (clip.name case final String name)
          AnimationClip(name: name, tracks: const <AnimationTrack>[]),
    ]);
    if (problems.isNotEmpty) return Outcome.refused(problems.join(' '));
    return Outcome.done(
      project.copyWith(
        animationGraphs: <String, Map<String, Object?>>{
          ...project.animationGraphs,
          // As it will be written: the defaults left out, every field in its
          // own place, so what was set is what a reader gets back.
          graphName: AnimationGraphJson.encode(machine),
        },
      ),
    );
  }
}

/// Removes graph [graphName]; refused when there is none of that name.
final class RemoveAnimationGraph extends ModelCommand {
  const RemoveAnimationGraph({required this.graphName});

  final String graphName;

  @override
  String get name => 'removeAnimationGraph';

  @override
  String get says => 'remove animation graph "$graphName"';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'graphName': graphName,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (!project.animationGraphs.containsKey(graphName)) {
      final names = project.animationGraphs.keys;
      return Outcome.refused(
        'there is no animation graph "$graphName"'
        '${names.isEmpty ? '' : '; there are ${names.join(', ')}'}',
      );
    }
    return Outcome.done(
      project.copyWith(
        animationGraphs: <String, Map<String, Object?>>{
          for (final MapEntry(:key, :value) in project.animationGraphs.entries)
            if (key != graphName) key: value,
        },
      ),
    );
  }
}
