/// What Play puts the document into — `ux-50`.
///
/// **Three, because the question "does this work?" has three shapes.** A
/// character is asked whether it reads in motion; a prop is asked whether it
/// reads from the distance somebody walks past it; a scene is asked whether
/// it can be walked through at all. Each answers a different one, and a
/// single "run it" that always did the same thing would answer only the
/// first.
library;

/// One of Play's own three templates.
enum PlayTemplate {
  /// The document rides the walking body, seen from behind — the shape a
  /// character is judged in.
  character('Character', 'The document walks, seen from behind.'),

  /// The document stands where it is and the body walks around it, seen
  /// through the body's own eyes — the shape a prop is judged in.
  prop('Prop in a level', 'Walk around the document, at eye height.'),

  /// The same as [prop], from further out and facing the whole document
  /// rather than its middle — the shape a room is judged in.
  walkthrough('Scene walkthrough', 'Walk through the document at scale.');

  const PlayTemplate(this.label, this.about);

  /// What the picker shows.
  final String label;

  /// One sentence for the picker's own subtitle, the same shape `ux-18` gave
  /// every tool in the rail.
  final String about;

  /// Whether the document is carried by the body rather than standing still.
  bool get ridesTheBody => this == PlayTemplate.character;

  /// How far back the camera sits from the body, in metres. Nought is the
  /// body's own eyes.
  double get cameraBack => switch (this) {
    PlayTemplate.character => 4.0,
    PlayTemplate.prop => 0.0,
    PlayTemplate.walkthrough => 0.0,
  };

  /// Where the body starts, in metres along -Z from the origin — far enough
  /// out to see what it is about to walk towards.
  double get startsBack => switch (this) {
    PlayTemplate.character => 0.0,
    PlayTemplate.prop => 3.5,
    PlayTemplate.walkthrough => 8.0,
  };
}
