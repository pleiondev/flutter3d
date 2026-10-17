/// Which of the elements' steps are drawn and heard: fire's, water's, the
/// sound, and each plugin element's by its id.
///
/// Plain values, here with the simulation because an element's hook is
/// told them ([ElementFrame.switches]) and the engine's registry of switches
/// fills them in ([ElementSwitches.defaults]); what reads them is the view
/// (`Elements`, `FireView`, `LiquidView` in `flutter3d_effects`). None of
/// them changes a step.
library;

import 'element_hook.dart'
    show ElementFrame, ElementHook, ElementSwitch, ElementSwitches;

/// Which of the elements' steps are taken, each on its own: the fires'
/// ([FireSteps]), the waters' ([LiquidSteps]) and the sound. A step
/// switched off costs nothing and leaves nothing of itself drawn or heard;
/// the world steps the same whatever is switched off, so a game's run does
/// not change with them — any combination.
///
/// **Open to plugin elements.** Fire and water have fields of their own;
/// an element a plugin adds ([ElementHook]) has a switch by its id in
/// [elements], asked through [isOn]. One nobody set is at the default the
/// element declares ([ElementSwitch.onByDefault]) — unless [otherElements]
/// is off, as in [none], which switches every element nobody named off.
/// [ElementSwitches] lists the switches an engine's elements declared.
final class ElementsSteps {
  const ElementsSteps({
    this.fire = FireSteps.all,
    this.liquid = LiquidSteps.all,
    this.sound = true,
    this.elements = const <String, bool>{},
    this.otherElements = true,
  });

  /// Every step.
  static const ElementsSteps all = ElementsSteps();

  /// None: the world steps and nothing of it is drawn or heard.
  static const ElementsSteps none = ElementsSteps(
    fire: FireSteps.none,
    liquid: LiquidSteps.none,
    sound: false,
    otherElements: false,
  );

  final FireSteps fire;
  final LiquidSteps liquid;
  final bool sound;

  /// Plugin elements switched by id: drawn and heard when true, neither
  /// when false. The world steps them the same either way.
  final Map<String, bool> elements;

  /// Whether a plugin element not in [elements] is at its own default
  /// (true) or off (false).
  final bool otherElements;

  /// Whether the plugin element [id] is drawn and heard; [byDefault] is
  /// what it declared for when nobody said.
  bool isOn(String id, {bool byDefault = true}) =>
      elements[id] ?? (otherElements && byDefault);

  /// These switches with element [id] set to [on].
  ElementsSteps withElement(String id, {required bool on}) =>
      copyWith(elements: <String, bool>{...elements, id: on});

  ElementsSteps copyWith({
    FireSteps? fire,
    LiquidSteps? liquid,
    bool? sound,
    Map<String, bool>? elements,
    bool? otherElements,
  }) => ElementsSteps(
    fire: fire ?? this.fire,
    liquid: liquid ?? this.liquid,
    sound: sound ?? this.sound,
    elements: elements == null
        ? this.elements
        : Map<String, bool>.unmodifiable(elements),
    otherElements: otherElements ?? this.otherElements,
  );
}

/// Which steps a `FireView` takes, each on its own: the tongues of flame,
/// the smoke, the embers, the light the fires give the scene, and the
/// charring of the looks it watches. A step switched off costs nothing and
/// leaves nothing of itself drawn; the others are drawn as they would be
/// with it — any combination.
final class FireSteps {
  const FireSteps({
    this.flames = true,
    this.smoke = true,
    this.embers = true,
    this.firelight = true,
    this.charring = true,
  });

  /// Every step.
  static const FireSteps all = FireSteps();

  /// None: the fires burn in the world and nothing of them is drawn.
  static const FireSteps none = FireSteps(
    flames: false,
    smoke: false,
    embers: false,
    firelight: false,
    charring: false,
  );

  final bool flames, smoke, embers, firelight, charring;

  FireSteps copyWith({
    bool? flames,
    bool? smoke,
    bool? embers,
    bool? firelight,
    bool? charring,
  }) => FireSteps(
    flames: flames ?? this.flames,
    smoke: smoke ?? this.smoke,
    embers: embers ?? this.embers,
    firelight: firelight ?? this.firelight,
    charring: charring ?? this.charring,
  );
}

/// Which steps a `LiquidView` takes, each on its own: the water's surface,
/// the sheet falling off a lip, the drops in the air, the mist where they
/// land, and the bubbles a plunge drives down. A step switched off costs
/// nothing and leaves nothing of itself drawn; the others are drawn as they
/// would be with it — any combination.
final class LiquidSteps {
  const LiquidSteps({
    this.surface = true,
    this.sheet = true,
    this.drops = true,
    this.mist = true,
    this.bubbles = true,
  });

  /// Every step.
  static const LiquidSteps all = LiquidSteps();

  /// None: the water flows in the world and nothing of it is drawn.
  static const LiquidSteps none = LiquidSteps(
    surface: false,
    sheet: false,
    drops: false,
    mist: false,
    bubbles: false,
  );

  final bool surface, sheet, drops, mist, bubbles;

  LiquidSteps copyWith({
    bool? surface,
    bool? sheet,
    bool? drops,
    bool? mist,
    bool? bubbles,
  }) => LiquidSteps(
    surface: surface ?? this.surface,
    sheet: sheet ?? this.sheet,
    drops: drops ?? this.drops,
    mist: mist ?? this.mist,
    bubbles: bubbles ?? this.bubbles,
  );
}
