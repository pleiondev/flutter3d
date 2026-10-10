// A project written against flutter3d 0.8.5, one use of each kind of
// change the 1.0 migration carries out. `after/` is what
// `dart run flutter3d_build:migrate` leaves of it.
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'models.dart';

/// `rewrite`: deprecated capability getters on a device.
bool canDrawLines(GraphicsDevice device) => device.supportsWireframe;

int colourTargets(GraphicsDevice device) => device.maxColorAttachments;

/// `moved`: no longer re-exported by `package:flutter3d/flutter3d.dart`.
const AbsolutePixels shadowAtlas = AbsolutePixels(2048, 2048);

/// `rename`: a static constant under its old name.
const TonemapCurve curve = TonemapCurve.agxFull;

/// `implementsToWith`: a type 1.0 made a `base mixin class`.
class Passenger implements Rider {
  @override
  Collider? get carriedBy => null;
}

/// `manual`: deprecated, and a shape rather than a rename.
GameLoop loopFor(InputState input) =>
    GameLoop(input: input, onStep: (double dt) {});

/// The new name in the facade, against the project's own.
String label() => textureBytes('fixture');

/// A name the facade still exports, so its import stays.
Scene emptyScene() => Scene();
