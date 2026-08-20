import 'tire_model.dart';

/// A set of tyres: the curve, what each surface is worth to them, and how much
/// grip they have to give.
///
/// **The three numbers were already there and were kept apart.** A car's
/// [TireModel] said where its grip peaks and what is left past the peak, a
/// [GripTable] said what each surface is worth, and `VehicleTuning.gripLimit`
/// said how many gravities there were to divide up — and that last one sat in
/// the table of engine, brakes and steering with a doc comment beginning "how
/// many gravities of grip **the tyres** have". Three properties of one object,
/// filed under three headings, which is why a game could not offer a player a
/// choice between them without passing three arguments that had to agree.
///
/// Here they are one thing, and the thing has a name a driver would use.
///
/// ## Why the difference is a trade and not a ladder
///
/// [slicks] are quicker than [road] everywhere the road is a road, and worse
/// than useless the moment a wheel touches grass. [rally] gives up more than a
/// tenth of a gravity on tarmac and keeps most of its grip off it. So the
/// choice is a real one on a circuit made of asphalt and grass, which is what
/// both of the shipped ones are made of: a driver who can keep it between the
/// lines is faster on slicks, and a driver who runs wide loses more than they
/// gained.
///
/// The shape matters as much as the number. Slicks peak sooner and keep less
/// past the peak, so the limit arrives without warning and letting go of it is
/// sudden; rally tyres peak later and hold on, so the car slides progressively
/// and comes back. That is the difference between a fast tyre and a forgiving
/// one, and it is two numbers rather than a difficulty setting.
final class Tyres {
  Tyres({
    required this.name,
    TireModel? model,
    this.grips = const GripTable.common(),
    this.limit = 1.05,
  }) : model = model ?? TireModel();

  /// What a driver calls them. Shown on screen, saved in a document.
  final String name;

  /// Where the grip peaks and what is left past the peak.
  final TireModel model;

  /// What each named surface is worth **to these tyres**. Not a property of
  /// the track: grass is the same grass either way, and what changes is what
  /// is standing on it.
  final GripTable grips;

  /// How many gravities of grip there are on a surface worth `1.0`.
  final double limit;

  /// What the game has always had. A road car on road tyres: enough grip to
  /// race on, enough left off the road to survive a mistake.
  static final Tyres road = Tyres(name: 'road');

  /// Racing slicks. A tenth of a gravity more on tarmac, a third of what road
  /// tyres have on grass, and a limit that arrives without announcing itself.
  static final Tyres slicks = Tyres(
    name: 'slicks',
    limit: 1.24,
    model: TireModel(
      peakSlipAngle: 0.12,
      lateralTail: 0.58,
      peakSlipRatio: 0.11,
      longitudinalTail: 0.7,
    ),
    grips: const GripTable(<String, double>{
      'asphalt': 1.0,
      'concrete': 0.95,
      'kerb': 0.8,
      'dirt': 0.34,
      'gravel': 0.26,
      'grass': 0.2,
      'sand': 0.16,
      'wet': 0.44,
      'ice': 0.12,
    }),
  );

  /// Knobbly tyres. Slower on the road and nearly as good off it, and they
  /// slide a long way before they let go.
  static final Tyres rally = Tyres(
    name: 'rally',
    limit: 0.92,
    model: TireModel(
      peakSlipAngle: 0.21,
      lateralTail: 0.86,
      peakSlipRatio: 0.18,
      longitudinalTail: 0.9,
    ),
    grips: const GripTable(<String, double>{
      'asphalt': 1.0,
      'concrete': 1.0,
      'kerb': 0.95,
      'dirt': 0.92,
      'gravel': 0.88,
      'grass': 0.82,
      'sand': 0.7,
      'wet': 0.85,
      'ice': 0.3,
    }),
  );

  /// The sets a player can be on, in the order they are cycled through.
  static final List<Tyres> all = <Tyres>[road, slicks, rally];

  /// The next set after [current], wrapping. Null and anything unrecognised
  /// come back as the first, so a saved name this build no longer ships reads
  /// as the tyres every car starts on rather than as a crash.
  static Tyres after(Tyres? current) {
    final index = current == null ? -1 : all.indexOf(current);
    return all[(index + 1) % all.length];
  }

  /// The set called [name], or [road] if nothing is.
  static Tyres named(String? name) => all.firstWhere(
        (Tyres tyres) => tyres.name == name,
        orElse: () => road,
      );

  @override
  String toString() => 'Tyres($name)';
}
