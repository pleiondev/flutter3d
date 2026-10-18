import 'package:flutter3d_sim/flutter3d_sim.dart';

/// [document], a level as a generator authored it, in the shape the engine
/// writes: read by `Level.fromJson` and written back by `Level.toJson`.
///
/// **The generators author in the version-1 shape and ship the current one.**
/// Their numbers were chosen in the units of the first format (a light's
/// strength in the pre-1.0 unit, `texelsPerMetre`, `behaviours`), and the
/// reader is what knows how each version lifts to the next. Going through it
/// gives the envelope, the American keys and candela and lux without a second
/// copy of that arithmetic here, and a document the editor saves unchanged.
/// The level's digest is taken over the body as version 4 spelled it, so a
/// run recorded against the version-1 document still names this one.
Map<String, Object?> asWritten(Map<String, Object?> document) =>
    Level.fromJson(document).toJson();
