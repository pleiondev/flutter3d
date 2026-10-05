/// Whether a level's behaviour trees read, and whether its entities name
/// trees it has.
library;

import '../level/level.dart';
import '../level/level_issue.dart';
import '../level/level_rule.dart';
import 'behaviour_tree.dart';

/// A [LevelRule] a game brings with its own [kinds]: every tree in
/// `Level.behaviours` reads, and every entity's [property] names one of them.
///
/// **The game's, not the validator's**, because what a leaf kind means is
/// the game's: a tree with an `attack` leaf is a good tree in a game that
/// registers one and a broken one in a game that does not, and only the game
/// knows which it is.
final class BehavioursRead extends LevelRule {
  const BehavioursRead(this.kinds, {this.property = 'behaviour'});

  final BehaviourKinds kinds;

  /// The entity property that names a tree.
  final String property;

  @override
  void check(Level level, List<LevelIssue> out) {
    for (final MapEntry(key: name, value: document)
        in level.behaviours.entries) {
      for (final problem in BehaviourTree.read(document, kinds).problems) {
        out.add(
          LevelIssue(LevelIssueSeverity.error, 'behaviour "$name": $problem'),
        );
      }
    }
    for (final entity in level.entities) {
      final named = entity.properties[property];
      if (named == null) continue;
      if (named is! String || !level.behaviours.containsKey(named)) {
        out.add(
          LevelIssue(
            LevelIssueSeverity.error,
            '${entity.name ?? entity.type} runs behaviour "$named", which '
            'the level does not have',
          ),
        );
      }
    }
  }
}
