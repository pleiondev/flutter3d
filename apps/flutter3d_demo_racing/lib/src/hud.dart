/// What the player is told, over the top of the picture.
///
/// Plain Flutter widgets rather than anything drawn in the scene: the engine
/// hands back a texture and Flutter composites over it, so a heads-up display
/// costs no draw calls and gets text layout, scaling and accessibility for
/// nothing.
///
/// The data this reads is [RaceReadout], in its own file; the panel, the line
/// and the speedometer are `hud_pieces.dart`; the map is `mini_map.dart`. What
/// is left here is the one thing none of those are: the layout that puts them
/// all on the same screen.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';

import 'hud_pieces.dart';
import 'mini_map.dart';
import 'race_readout.dart';

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
            child: HudPanel(
              children: <Widget>[
                if (readout.mode != RaceMode.freeRoam) ...<Widget>[
                  HudLine(
                    label: 'LAP',
                    value: '${math.min(readout.lap + 1, readout.laps)}'
                        '/${readout.laps}',
                  ),
                  if (readout.mode == RaceMode.race)
                    HudLine(
                      label: 'POS',
                      value: '${readout.position}/${readout.racers}',
                    ),
                  HudLine(label: 'TIME', value: formatLapTime(readout.lapTime)),
                  HudLine(
                    label: 'BEST',
                    value: readout.bestLap == null
                        ? '--:--.---'
                        : formatLapTime(readout.bestLap!),
                  ),
                  HudLine(
                    label: readout.recordJustSet ? 'RECORD!' : 'RECORD',
                    value: readout.record == null
                        ? '--:--.---'
                        : formatLapTime(readout.record!),
                    accent: readout.recordJustSet,
                  ),
                ],
                if (readout.damage > 0.02)
                  HudLine(
                    label: 'DAMAGE',
                    value: '${(readout.damage * 100).round()}%',
                    // A quarter gone is a car losing a tenth of its engine and
                    // a driver who can still race. Past a half it is a decision
                    // about whether to stop.
                    accent: readout.damage > 0.5,
                  ),
                HudLine(
                  label: 'TYRES',
                  value: readout.tyresRefused
                      ? 'STOP FIRST'
                      : readout.tyres.toUpperCase(),
                  accent: readout.tyresRefused,
                ),
              ],
            ),
          ),
          Positioned(right: 16, bottom: 16, child: Speedometer(readout: readout)),
          Positioned(
            left: 16,
            bottom: 16,
            child: MiniMap(readout: readout),
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
