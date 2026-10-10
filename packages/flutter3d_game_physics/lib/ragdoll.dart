/// Actors that fall as bodies when they die: [RagdollCorpses], handed to
/// `ActorVisuals` as its `corpses`, takes a dead actor's skeleton over and
/// lets it fall in the physics core against the level. Under it,
/// [SkeletonRagdoll] makes any scene skeleton a ragdoll by a
/// [RagdollProfile] of joint names, and [RagdollGetUp] fades one back into
/// the animation.
///
/// A library, not a plugin: it is a part of how actors are drawn, handed in
/// where a game builds its visuals, and registers nothing with the engine.
library;

export 'src/ragdoll/ragdoll_corpses.dart';
export 'src/ragdoll/skeleton_ragdoll.dart';
