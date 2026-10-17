import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Severity;

import 'level.dart';
import 'level_issue.dart';

/// A whole-level rule a game brings with it.
///
/// **Not every game is a shooter, and the validator used to assume one.** It
/// required exactly one `player_spawn` and warned about a missing `exit`, which
/// are rules about a genre rather than about the format: a game with several
/// starting points, or one that ends by a script rather than by walking into a
/// door, failed a check the engine had no business making.
///
/// What is left in the validator is what any level in this format must be true
/// of whatever the game is — names unique, references resolving, brushes not
/// degenerate, something to stand on, something to see by. Anything about
/// *which entities* a level ought to contain arrives here.
abstract base class LevelRule {
  const LevelRule();

  /// Adds what is wrong with the check's level to its [LevelCheck.out].
  void check(LevelCheck check);
}

/// What [LevelRule.check] is handed: the level, and the list its problems go
/// in.
///
/// **One object, so a minor can hand a rule more** — the registry of entity
/// kinds, the document's version — without breaking a rule written against
/// 1.0.
final class LevelCheck {
  const LevelCheck({required this.level, required this.out});

  /// The level being checked.
  final Level level;

  /// Where its problems go.
  final List<LevelIssue> out;
}

/// There must be exactly this many of a type, no more and no fewer.
///
/// The rule a player spawn wants: none and the player starts at the origin,
/// which is usually inside the floor; two and nothing decides which is used.
final class ExactlyOne extends LevelRule {
  const ExactlyOne(this.type, {this.because});

  final String type;

  /// What goes wrong when the count is not one. Worth saying, because "there
  /// are 2 player_spawn entities" tells an author what and not why.
  final String? because;

  @override
  void check(LevelCheck check) {
    final level = check.level;
    final out = check.out;
    final count = level.ofType(type).length;
    if (count == 1) return;
    out.add(
      LevelIssue(
        Severity.error,
        count == 0
            ? 'no $type${because == null ? '' : ': $because'}'
            : 'there are $count $type entities and nothing decides which is '
                  'used',
      ),
    );
  }
}

/// There should be at least one of a type, or the level is missing something.
final class AtLeastOne extends LevelRule {
  const AtLeastOne(this.type, {this.because, this.severity = Severity.warning});

  final String type;
  final String? because;
  final Severity severity;

  @override
  void check(LevelCheck check) {
    final level = check.level;
    final out = check.out;
    if (level.ofType(type).isNotEmpty) return;
    out.add(
      LevelIssue(severity, 'no $type${because == null ? '' : ': $because'}'),
    );
  }
}
