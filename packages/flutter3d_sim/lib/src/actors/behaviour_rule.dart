/// Whether a level's behaviour trees read, and whether its entities name
/// trees it has.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Severity;

import '../level/level_issue.dart';
import '../level/level_rule.dart';
import 'behaviour_tree.dart';

/// A [LevelRule] a game brings with its own [kinds]: every tree in
/// `Level.behaviors` reads, and every entity's [property] names one of them.
///
/// **The game's, not the validator's**, because what a leaf kind means is
/// the game's: a tree with an `attack` leaf is a good tree in a game that
/// registers one and a broken one in a game that does not, and only the game
/// knows which it is.
final class BehaviorsRead extends LevelRule {
  const BehaviorsRead(this.kinds, {this.property = 'behavior'});

  final BehaviorKinds kinds;

  /// The entity property that names a tree: `behavior`, which a level
  /// before format 5 spelled `behaviour` and its lift renames.
  final String property;

  @override
  void check(LevelCheck check) {
    final level = check.level;
    final out = check.out;
    for (final MapEntry(key: name, value: document)
        in level.behaviors.entries) {
      for (final problem in BehaviorTree.read(document, kinds).problems) {
        out.add(LevelIssue(Severity.error, 'behaviour "$name": $problem'));
      }
    }
    for (final entity in level.entities) {
      final named = entity.properties[property];
      if (named == null) continue;
      if (named is! String || !level.behaviors.containsKey(named)) {
        out.add(
          LevelIssue(
            Severity.error,
            '${entity.name ?? entity.type} runs behaviour "$named", which '
            'the level does not have',
          ),
        );
      }
    }
  }
}
