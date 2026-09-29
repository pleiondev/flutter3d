import 'package:flame/components.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;

import '../host/has_flutter3d.dart';

/// A day of [AtmosphereCycle] run on Flame's clock, on the 3D world of the
/// `HasFlutter3d` game it is in: the sky, the ambient light and [sun].
///
/// [time] advances by [rate] a second (a game whose day lasts a race sets
/// it so), and [current] is the air right now. The fog is the one part a
/// scene does not hold: a game's `renderSettings` reads [fog].
class AtmosphereComponent extends Component {
  AtmosphereComponent({
    required this.cycle,
    this.sun,
    this.time = 0.0,
    this.rate = 1.0,
  }) : current = cycle.at(time);

  final AtmosphereCycle cycle;

  /// The light the sun's colour and intensity go onto, if any.
  final LightNode? sun;

  /// Where in the cycle the day is.
  double time;

  /// How much [time] passes a second of play.
  double rate;

  /// The air now.
  Atmosphere current;

  /// The fog to draw with now.
  FogSettings get fog => current.fog;

  @override
  void update(double dt) {
    super.update(dt);
    time += dt * rate;
    current = cycle.at(time);
    final game = findGame();
    if (game is HasFlutter3d && game.has3d) {
      current.applyTo(game.scene, sun: sun, clearColor: game.clearColor);
    }
  }
}
