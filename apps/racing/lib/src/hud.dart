/// What the player is told, over the top of the picture.
///
/// Plain Flutter widgets rather than anything drawn in the scene: the engine
/// hands back a texture and Flutter composites over it, so a heads-up display
/// costs no draw calls and gets text layout, scaling and accessibility for
/// nothing.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter3d_racing/flutter3d_racing.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

/// Everything the display needs, gathered once a frame.
///
/// A record of values rather than the simulation itself, so that the widgets
/// cannot reach into a car and cannot be the reason a lap counter changed.
class RaceReadout {
  const RaceReadout({
    required this.speed,
    required this.lap,
    required this.laps,
    required this.position,
    required this.racers,
    required this.lapTime,
    required this.bestLap,
    required this.record,
    required this.tyres,
    this.recordJustSet = false,
    this.tyresRefused = false,
    required this.wrongWay,
    required this.countdown,
    required this.mode,
    required this.outline,
    required this.carsOnMap,
    this.behind = false,
    this.paused = false,
    this.notice,
  });

  /// Metres per second. Turned into something a driver reads at the last
  /// moment, because the simulation has no opinion about miles.
  final double speed;

  final int lap;
  final int laps;
  final int position;
  final int racers;
  final double lapTime;
  final double? bestLap;

  /// The quickest lap ever driven here, across every launch, or null before
  /// there is one. **Not [bestLap]**, which starts again with every race: a
  /// number that resets when the window closes is a readout, and what a driver
  /// is actually chasing is the one that does not.
  final double? record;

  /// Whether that record was set a moment ago, so the line can say so.
  final bool recordJustSet;

  /// What the car is standing on the road with.
  final String tyres;

  /// Whether a change was asked for and refused, which happens at any speed
  /// above a walk. Said rather than ignored: a key that does nothing and says
  /// nothing is a key a player decides is broken.
  final bool tyresRefused;
  final bool wrongWay;

  /// Seconds left on the lights, or null once they have gone out.
  final double? countdown;

  final RaceMode mode;

  /// The circuit as a flat outline, in world XZ.
  final List<Vector2> outline;

  /// Where each car is, in the same space. The first is the player.
  final List<Vector2> carsOnMap;

  /// Whether the machine is not keeping up.
  ///
  /// A count of dropped steps means nothing to a player; what it means is that
  /// the race is running in slow motion and saying nothing about it. This game
  /// could not tell at all until the loop arrived.
  final bool behind;

  /// Whether the player has stopped the race.
  final bool paused;

  /// What is said across the screen between circuits, and when the season ends.
  ///
  /// A race that is won and says nothing is a race that looks broken, which is
  /// what this game did: the finish line was crossed, the simulation marked it,
  /// and the car kept driving round an empty circuit forever.
  final String? notice;

}

String formatLapTime(double seconds) {
  if (seconds <= 0) return '--:--.---';
  final minutes = seconds ~/ 60;
  final rest = seconds - minutes * 60;
  final whole = rest.floor();
  final thousandths = ((rest - whole) * 1000).round();
  return '$minutes:${whole.toString().padLeft(2, '0')}'
      '.${thousandths.toString().padLeft(3, '0')}';
}

class RaceHud extends StatelessWidget {
  const RaceHud({super.key, required this.readout});

  final RaceReadout readout;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 16,
            top: 16,
            child: _Panel(
              children: <Widget>[
                if (readout.mode != RaceMode.freeRoam) ...<Widget>[
                  _Line(
                    label: 'LAP',
                    value: '${math.min(readout.lap + 1, readout.laps)}'
                        '/${readout.laps}',
                  ),
                  if (readout.mode == RaceMode.race)
                    _Line(
                      label: 'POS',
                      value: '${readout.position}/${readout.racers}',
                    ),
                  _Line(label: 'TIME', value: formatLapTime(readout.lapTime)),
                  _Line(
                    label: 'BEST',
                    value: readout.bestLap == null
                        ? '--:--.---'
                        : formatLapTime(readout.bestLap!),
                  ),
                  _Line(
                    label: readout.recordJustSet ? 'RECORD!' : 'RECORD',
                    value: readout.record == null
                        ? '--:--.---'
                        : formatLapTime(readout.record!),
                    accent: readout.recordJustSet,
                  ),
                ],
                _Line(
                  label: 'TYRES',
                  value: readout.tyresRefused
                      ? 'STOP FIRST'
                      : readout.tyres.toUpperCase(),
                  accent: readout.tyresRefused,
                ),
              ],
            ),
          ),
          Positioned(right: 16, bottom: 16, child: _Speedometer(readout: readout)),
          Positioned(
            left: 16,
            bottom: 16,
            child: _MiniMap(readout: readout),
          ),
          if (readout.wrongWay)
            const Positioned(
              left: 0,
              right: 0,
              top: 90,
              child: Center(
                child: Text(
                  'WRONG WAY',
                  style: TextStyle(
                    color: Color(0xFFFF4D3D),
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
              ),
            ),
          if (readout.notice != null)
            Positioned(
              left: 0,
              right: 0,
              top: 90,
              child: Center(
                child: Text(
                  readout.notice!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          if (readout.countdown != null)
            Positioned.fill(
              child: Center(
                child: Text(
                  readout.countdown! > 0
                      ? readout.countdown!.ceil().toString()
                      : 'GO',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 120,
                    fontWeight: FontWeight.w900,
                    shadows: <Shadow>[
                      Shadow(blurRadius: 24, color: Colors.black87),
                    ],
                  ),
                ),
              ),
            ),
          if (readout.behind)
          Positioned(
            right: 24,
            top: 24,
            child: Text(
              'This machine is behind — the race is running slowly.',
              style: TextStyle(
                color: Colors.amber.withValues(alpha: 0.9),
                fontSize: 13,
                shadows: const <Shadow>[
                  Shadow(blurRadius: 8, color: Colors.black87),
                ],
              ),
            ),
          ),
        if (readout.paused)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xAA000000),
              child: Center(
                child: Text(
                  'Paused — Escape to drive on',
                  style: TextStyle(color: Colors.white, fontSize: 22),
                ),
              ),
            ),
          ),
      ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.accent = false});

  final String label;
  final String value;

  /// Whether this line has just become true. Colour, because a driver reading
  /// it is doing something else at the time.
  final bool accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 52,
              child: Text(
                label,
                style: TextStyle(
                  color: accent ? _accent : const Color(0xFF9AA4B2),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: accent ? _accent : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                // Tabular figures, or the whole line jitters as the
                // thousandths tick over.
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ],
        ),
      );

  /// The colour the flag is, which is the one thing on this screen that already
  /// meant "you have done it".
  static const Color _accent = Color(0xFFFFD166);
}

class _Speedometer extends StatelessWidget {
  const _Speedometer({required this.readout});

  final RaceReadout readout;

  @override
  Widget build(BuildContext context) {
    // Kilometres an hour, because that is the number on a car. The simulation
    // works in metres a second and is right to.
    final kph = (readout.speed * 3.6).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '$kph',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.w800,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'km/h',
            style: TextStyle(
              color: Color(0xFF9AA4B2),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.readout});

  final RaceReadout readout;

  @override
  Widget build(BuildContext context) => Container(
        width: 150,
        height: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: CustomPaint(
          painter: _MapPainter(
            outline: readout.outline,
            cars: readout.carsOnMap,
          ),
        ),
      );
}

class _MapPainter extends CustomPainter {
  const _MapPainter({required this.outline, required this.cars});

  final List<Vector2> outline;
  final List<Vector2> cars;

  @override
  void paint(Canvas canvas, Size size) {
    if (outline.length < 2) return;

    // Fitted to the box rather than drawn at a fixed scale: a circuit is
    // whatever size it is, and a map that assumed one would put half of every
    // other track outside the corner it is drawn in.
    var minX = outline.first.x;
    var maxX = minX;
    var minY = outline.first.y;
    var maxY = minY;
    for (final point in outline) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
    }
    final span = math.max(maxX - minX, maxY - minY);
    if (span <= 0) return;
    final scale = math.min(size.width, size.height) / span;

    Offset place(Vector2 point) => Offset(
          (point.x - (minX + maxX) / 2) * scale + size.width / 2,
          (point.y - (minY + maxY) / 2) * scale + size.height / 2,
        );

    final path = Path()..moveTo(place(outline.first).dx, place(outline.first).dy);
    for (final point in outline.skip(1)) {
      final at = place(point);
      path.lineTo(at.dx, at.dy);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF7E8794),
    );

    for (var i = 0; i < cars.length; i++) {
      canvas.drawCircle(
        place(cars[i]),
        i == 0 ? 4.5 : 3.0,
        Paint()..color = i == 0 ? Colors.white : const Color(0xFFE0553F),
      );
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => true;
}
