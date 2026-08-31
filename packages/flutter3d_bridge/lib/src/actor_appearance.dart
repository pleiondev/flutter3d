import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

/// What a monster is made of, which is the one thing the bridge cannot know.
///
/// Called every frame with the monster's current state, so a game is free to
/// answer with a shared material per kind, a brightened one for a monster that
/// was just hit, or something built on the spot.
abstract interface class ActorAppearance {
  /// The material to draw `monster` with right now.
  Material materialFor(Actor actor);

  /// A key that two actors share exactly when they should share one capsule
  /// mesh. The game's own answer, because the engine has no idea what makes
  /// two of its actors the same kind of thing.
  String meshKeyFor(Actor actor);

  /// The model to draw [actor] as, or null to leave it a capsule.
  ///
  /// Per actor rather than per key, because two actors of the same kind can be
  /// drawn differently and nothing here should decide they cannot. Actors
  /// sharing a path share one loaded [ModelAsset]; each gets its own instance.
  ///
  /// **A null is a perfectly good answer.** A turret, a trigger volume and a
  /// director are actors too, and a capsule is what the placeholder has always
  /// been — this adds a door rather than closing one.
  String? modelFor(Actor actor);

  /// Which of the model's clips [actor] should be playing, best first.
  ///
  /// **A list rather than a name, and the models are why.** These are
  /// third-party exports and they do not carry the same clips: one may have
  /// `Run` where another has only `Walk`, and the same gesture is spelled two
  /// ways across two files. A game says what it would like in order; this tries
  /// each until the model has one, which only this side can do — the appearance
  /// does not know what is in the file and should not have to.
  ///
  /// Empty leaves whatever is playing alone, which is what a model with no
  /// animation in it wants.
  ///
  /// Named rather than indexed on purpose: an index is a promise about the
  /// order inside somebody else's export.
  List<String> clipsFor(Actor actor);
}
