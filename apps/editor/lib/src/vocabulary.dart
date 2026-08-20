import 'package:flutter3d_game/flutter3d_game.dart';

/// A kind for a type nobody here can vouch for.
///
/// **An editor has no vocabulary of its own, and must not invent one.** A
/// level document says `monster` or `coin` or `checkpoint`, and what those are
/// worth is the game's business — the engine's own registry doc says so at
/// length, and its first version shipped a list of fourteen kinds that a second
/// game silently validated its levels against.
///
/// So this accepts whatever the document happens to name and vouches for none
/// of it: an entity of an unknown type is a coordinate with a word attached,
/// which is exactly what it is to an editor that does not know the game.
final class OpenKind extends EntityKind {
  const OpenKind(super.type);
}

/// A registry made of whatever [level] already names.
///
/// Everything therefore validates, which is the point rather than a compromise:
/// the checks an editor can honestly make are about geometry, materials and
/// lights, and reporting "unknown entity type: coin" for a game whose levels
/// are full of coins would be noise nobody could turn off.
///
/// A game that wants its own vocabulary checked has one already — the same
/// registry it loads with — and can hand it to [Editing.issuesFor].
EntityRegistry vocabularyOf(Level level) => EntityRegistry(<EntityKind>[
      for (final type in level.entities.map((EntityDef e) => e.type).toSet())
        OpenKind(type),
    ]);
