/// What each level's hazards are drawn as, and what stands about them to
/// be drawn too: which pits hold water and which molten metal, where water
/// spills into them over a ledge, where wood floats on them and where fires
/// burn.
///
/// **A table of this game's own levels, and nothing in it reaches the
/// simulation.** A hazard named here is still the same trigger volume it
/// always was, hurting as it always did; the table only says what
/// `LevelElements` puts in its place on the screen. A level the table does
/// not name keeps the red boxes it has always had.
library;

/// Water welling up at ([x], [z]) on a ledge over the pit named [into], at
/// [rate] m³/s, and running to the ledge's lip through a culvert [culvert]
/// metres under the ledge's top and [width] metres wide, whose mouth it
/// pours out of. [roughness] is the culvert's bed, Manning's: what holds the
/// stream in it to a culvert's pace.
typedef Pour = ({
  String into,
  double x,
  double z,
  double rate,
  double culvert,
  double width,
  double roughness,
});

/// A piece of wood floating on the pit named [pool], put in at ([x], [z]);
/// a [raft] of three logs where it is true, a plank where it is not.
typedef Afloat = ({String pool, double x, double z, bool raft});

/// What one level dresses its hazards as.
final class Dressing {
  const Dressing({
    this.water = const <String, double>{},
    this.molten = const <String, double>{},
    this.spills = const <Pour>[],
    this.afloat = const <Afloat>[],
    this.braziers = const <(double, double, double)>[],
    this.heaps = const <(double, double, double)>[],
  });

  /// The hazards drawn as water, by name, and the height its surface is
  /// filled to, m: a little under the floor round the pit, so the bank
  /// stands over it.
  final Map<String, double> water;

  /// The hazards drawn as molten metal, by name, and its surface's height.
  final Map<String, double> molten;

  /// Where water spills into a pit over a ledge.
  final List<Pour> spills;

  /// The wood on the water.
  final List<Afloat> afloat;

  /// Iron braziers of burning coal and wood, by where each stands.
  final List<(double, double, double)> braziers;

  /// Heaps of burning coal lying on the floor of a molten pit, by where
  /// each lies.
  final List<(double, double, double)> heaps;

  /// Whether there is anything at all to draw.
  bool get isEmpty =>
      water.isEmpty && molten.isEmpty && braziers.isEmpty && heaps.isEmpty;

  /// What the level named [name] dresses its hazards as; nothing for a
  /// level this table does not know.
  static Dressing of(String name) => _levels[name] ?? const Dressing();

  static const Map<String, Dressing> _levels = <String, Dressing>{
    // The cisterns: four sunk pools. The two the runner wades are shallow,
    // a hand over the shin; the two that drown stand nearly to the walkways.
    // Each is fed out of a culvert in a wall over it: the gallery's mouth
    // high in its face, falling four metres into the spill; one in the
    // quay's face, a little weir into the shallows, and one more into the
    // race.
    'Cisterns': Dressing(
      water: <String, double>{
        'the shallows': -0.85,
        'the race': -0.8,
        'the deep': -0.45,
        'the spill': -0.45,
      },
      spills: <Pour>[
        // A culvert's mouth is no spout: what comes out of it at a walking
        // pace peels off the wall and lands a metre out, which is what the
        // rough bed holds it to. The pool under it is three and a half
        // metres deep and hardly feels that roughness.
        (
          into: 'the spill',
          x: 12.0,
          z: 143.6,
          rate: 0.08,
          culvert: 0.7,
          width: 1.5,
          roughness: 2.5,
        ),
        (
          into: 'the shallows',
          x: -12.0,
          z: 0.6,
          rate: 0.08,
          culvert: 0.3,
          width: 1.5,
          roughness: 0.14,
        ),
        (
          into: 'the race',
          x: 14.0,
          z: 65.4,
          rate: 0.08,
          culvert: 0.25,
          width: 1.5,
          roughness: 0.14,
        ),
      ],
      afloat: <Afloat>[
        (pool: 'the shallows', x: -7.0, z: 16.0, raft: false),
        (pool: 'the shallows', x: 10.0, z: 18.0, raft: false),
        (pool: 'the race', x: -14.0, z: 47.0, raft: false),
        (pool: 'the deep', x: -16.0, z: 88.0, raft: true),
        (pool: 'the deep', x: -15.5, z: 104.0, raft: true),
        (pool: 'the deep', x: 11.8, z: 100.0, raft: true),
        (pool: 'the spill', x: 9.0, z: 134.0, raft: false),
      ],
      braziers: <(double, double, double)>[
        (-17.5, 0.0, -12.0),
        (17.5, 0.0, -12.0),
        (-17.5, 0.0, 28.0),
        (17.5, 0.0, 28.0),
        (-17.5, 4.0, 168.0),
        (17.5, 4.0, 168.0),
      ],
    ),
    // The foundry: the pour a film of metal over the pit's floor, under the
    // pads that throw the runner out of it, which must stay in sight; a pool
    // of it at the bottom of the tap hole, six metres down; each fed by a
    // spout off the floor above it, so the metal moves and its crust
    // breaks; coal burning in both.
    'Foundry': Dressing(
      molten: <String, double>{'the shallow pour': -2.44, 'the tap hole': -5.7},
      spills: <Pour>[
        (
          into: 'the shallow pour',
          x: 9.0,
          z: 39.2,
          rate: 0.04,
          culvert: 0.3,
          width: 1.0,
          roughness: 0.05,
        ),
        (
          into: 'the tap hole',
          x: -9.0,
          z: 103.2,
          rate: 0.04,
          culvert: 0.3,
          width: 1.0,
          roughness: 0.05,
        ),
      ],
      heaps: <(double, double, double)>[
        (-19.0, -2.5, 43.0),
        (19.0, -2.5, 53.0),
        (-8.5, -2.5, 54.0),
        (-17.0, -6.0, 110.0),
        (8.0, -6.0, 116.0),
        (18.0, -6.0, 106.0),
      ],
    ),
    // The ascent's three gaps, crossed on barges and floes: water up to the
    // underside of the floors either side, so no gap of nothing shows
    // between them, a little of it running off the floor into the gulf.
    'Ascent': Dressing(
      water: <String, double>{
        'the first drop': -1.05,
        'the gulf': -1.05,
        'the crevasse': -1.05,
      },
      spills: <Pour>[
        (
          into: 'the gulf',
          x: -45.0,
          z: 55.3,
          rate: 0.2,
          culvert: 0.3,
          width: 1.0,
          roughness: 0.14,
        ),
      ],
      afloat: <Afloat>[
        (pool: 'the gulf', x: -40.0, z: 62.0, raft: true),
        (pool: 'the gulf', x: 22.0, z: 61.0, raft: false),
        (pool: 'the crevasse', x: -6.0, z: 140.0, raft: false),
      ],
    ),
  };
}
