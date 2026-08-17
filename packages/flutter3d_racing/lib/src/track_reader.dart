import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'sky.dart';
import 'track.dart';

/// A track file: the circuit, and the level built around it.
///
/// Two halves because they are authored by different things and validated by
/// different things. The circuit is a curve with numbers hung off it, and only
/// this package knows what those numbers mean; the level is an ordinary
/// [Level] — brushes, materials, lights, entities — and the engine has read and
/// validated those since the first game. A racing app loads one file and gets
/// both.
///
/// Written by a generator, not by hand. The rule this repository already keeps
/// for levels holds here for the same reason: a circuit is hundreds of numbers
/// that have to agree with each other, and a person editing them in a text
/// editor is a person introducing a corner that is four metres wide for one
/// control point.
final class TrackDocument {
  TrackDocument({required this.track, this.level, SkyPreset? sky})
      : sky = sky ?? SkyPresets.morning;

  factory TrackDocument.fromJson(Map<String, Object?> json) {
    final track = json['track'];
    if (track == null) {
      throw LevelFormatException('"track" is required');
    }

    final level = json['level'];
    final sky = json['sky'];
    return TrackDocument(
      track: _trackFromJson(track.asJsonObject('track')),
      level: level == null ? null : Level.fromJson(level.asJsonObject('level')),
      sky: sky == null
          ? null
          : SkyPreset.fromJson(sky.asJsonObject('sky')),
    );
  }

  final TrackSpline track;

  /// The scenery, barriers and furniture around the circuit. Absent in a
  /// fixture that is only interested in the driving.
  final Level? level;

  /// The time of day the circuit is raced at.
  ///
  /// Never absent, because there is no such thing as a track in no weather: a
  /// file with no `"sky"` block gets [SkyPresets.morning], the same way a car
  /// with no model gets a box. The level's own `fogColor` and `fogDensity` are
  /// derived from this by the generator and are not read back — the application
  /// asks the preset, which knows which way the camera is pointing and can
  /// therefore answer something the level file cannot.
  final SkyPreset sky;
}

TrackSpline _trackFromJson(Map<String, Object?> json) {
  if (!json.flagOr('closed', fallback: true)) {
    // Point-to-point tracks are a different lap counter, a different grid and a
    // different idea of what "position" means. Refusing now is cheaper than a
    // circuit that loads and counts laps that cannot happen.
    throw LevelFormatException('only closed circuits are supported');
  }

  final points = json.objects('points');
  if (points.length < 3) {
    throw LevelFormatException('"points" needs at least three entries');
  }

  final positions = <Vector3>[];
  final widths = <double>[];
  final banks = <double>[];
  for (final point in points) {
    positions.add(point.vector3('at'));
    widths.add(point.numberOr('width', 12.0));
    // Authored in degrees. Radians are what the maths wants and degrees are what
    // a person setting the camber of a corner has an opinion about.
    banks.add(point.numberOr('bank', 0.0) * _degrees);
  }

  final centre = CatmullRom(positions);

  return TrackSpline(
    centre: centre,
    widths: widths,
    banks: banks,
    shoulder: json.numberOr('shoulder', 4.0),
    surfaces: <SurfaceBand>[
      for (final band in json.objects('surfaces'))
        SurfaceBand(
          fromS: band.numberOr('fromS', 0.0),
          toS: band.numberOr('toS', centre.length),
          // Spelt out because `Snapshot`'s reader is on the same type and also
          // has a `text`, and the two are exported through one barrel.
          centre: JsonObjectReader(band).text('centre'),
          shoulder: JsonObjectReader(band).text('shoulder'),
        ),
    ],
    barriers: <BarrierBand>[
      for (final band in json.objects('barriers'))
        BarrierBand(
          fromS: band.numberOr('fromS', 0.0),
          toS: band.numberOr('toS', centre.length),
          left: band.flagOr('left'),
          right: band.flagOr('right'),
        ),
    ],
    checkpoints: <double>[
      for (final checkpoint in json.objects('checkpoints'))
        checkpoint.numberOr('s', 0.0),
    ],
    grid: _gridFromJson(json),
  );
}

StartGrid _gridFromJson(Map<String, Object?> json) {
  final grid = json['grid'];
  if (grid == null) return const StartGrid();

  final fields = grid.asJsonObject('grid');
  final columns = JsonObjectReader(fields).integer('columns') ?? 2;
  if (columns < 1) {
    throw LevelFormatException('"grid.columns" must be at least one');
  }
  return StartGrid(
    s: fields.numberOr('s', -12.0),
    columns: columns,
    rowGap: fields.numberOr('rowGap', 6.0),
    columnGap: fields.numberOr('columnGap', 3.5),
  );
}

const double _degrees = 3.1415926535897932 / 180.0;
