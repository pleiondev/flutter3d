import 'lighting_model.dart';
import 'surface_material.dart';

/// What a control for one value should look like.
///
/// **A description for a person, never a rule for the reader.** A hint saying
/// `range 0..1` does not make `readFmat` refuse a roughness of 1.5: the number
/// in the file is what the shader receives either way, and a reader that
/// clamped it would be changing what the engine draws in order to tidy up an
/// editor's slider. Every golden picture in this repository was rendered with
/// the numbers the files actually carry, and a hint is not allowed to move
/// them. So this hierarchy answers one question — how should somebody be shown
/// this value — and nothing else.
///
/// An open set, grown only here: `abstract final` so nobody outside adds a
/// kind, and not sealed, so a kind a later release adds breaks no inspector.
/// A `switch` over the kinds ends with a wildcard that shows the value as it
/// is.
abstract final class MaterialHintKind {
  const MaterialHintKind();
}

/// A number with two ends and, when it is not continuous, an increment.
///
/// [step] is null for a value a slider may land anywhere in; a step of `0.01`
/// is what makes a spinner move in hundredths rather than in whole units.
final class RangeHint extends MaterialHintKind {
  /// A range from [min] to [max], continuous unless [step] is given.
  const RangeHint(this.min, this.max, {this.step});

  /// In the unit of the value the hint is for.
  final double min;

  /// In the unit of the value the hint is for.
  final double max;

  /// In the unit of the value the hint is for.
  final double? step;
}

/// A colour of [channels] components — three for a tint, four when the fourth
/// is opacity.
///
/// The count rather than a flag, because the two are the same question asked
/// once: a swatch that offers an alpha slider for `emissive` is offering to set
/// a number the shader never reads.
final class ColorHint extends MaterialHintKind {
  /// A colour of [channels] components, four unless told otherwise.
  const ColorHint({this.channels = 4});

  /// Count of components a swatch offers: three for RGB, four with alpha.
  final int channels;
}

/// A path to an image, and what a file picker should offer.
final class TextureHint extends MaterialHintKind {
  /// A picker filtered to [extensions], every format this engine decodes
  /// unless told otherwise.
  const TextureHint({this.extensions = imageSuffixes});

  /// What this engine can decode, and so the default filter.
  static const List<String> imageSuffixes = <String>[
    '.png',
    '.jpg',
    '.jpeg',
    '.ktx2',
  ];

  /// The suffixes a file picker offers, dot included, lower case.
  final List<String> extensions;
}

/// One of [values], and nothing else.
final class EnumHint extends MaterialHintKind {
  /// A choice among [values].
  const EnumHint(this.values);

  /// The choices, in the order a picker lists them.
  final List<EnumHintValue> values;
}

/// One choice in an [EnumHint]: what is written into the file, and what a
/// person reads in the list.
///
/// Two strings rather than one, because the two audiences differ — `Pbr` is a
/// shader entry point and `PBR (GGX)` is what a picker should say. A choice
/// given no label is its own label, which is the common case for a value that
/// was already a word.
final class EnumHintValue {
  /// A choice writing [value], shown as [label]; null shows [value].
  const EnumHintValue(this.value, {String? label}) : label = label ?? value;

  /// What is written into the file when this choice is picked: `Pbr`.
  final String value;

  /// What a person reads in the list: `PBR (GGX)`.
  final String label;
}

/// A [kind] with the words that go around it.
///
/// [label] replaces the field's own name in a UI; [help] is the sentence shown
/// beside it. Both optional: a parameter named `windStrength` needs neither to
/// be usable, and a hint that had to carry them would be a hint nobody writes.
final class MaterialHint {
  /// A hint of [kind], with [label] and [help] when given.
  const MaterialHint(this.kind, {this.label, this.help});

  /// The control the value is shown with.
  final MaterialHintKind kind;

  /// The name a UI shows instead of the field's own; null shows the
  /// field's name.
  final String? label;

  /// The sentence shown beside the control; null shows none.
  final String? help;
}

/// Hints for the fields every material has, held here rather than written into
/// every file.
///
/// **Why the engine keeps this and `.fmat` does not.** The fields below are the
/// same in every material ever authored: roughness runs nought to one in all of
/// them, and `baseColor` is a colour in all of them. Writing that into each file
/// would put a hundred lines of identical text in front of the six lines an
/// artist actually edits, and the readable diff is the property the format was
/// chosen for. A file carries hints only for the parameters this table cannot
/// know about — the ones a studio's own shader declares.
///
/// So an inspector reads a field's hint from here and a parameter's from
/// [MaterialDocument.hints], and a field the table says nothing about is shown
/// however the inspector shows an unhinted number.
final Map<String, MaterialHint> builtInMaterialHints = <String, MaterialHint>{
  'baseColor': const MaterialHint(
    ColorHint(),
    label: 'Base colour',
    help: 'The colour the surface is painted, and its opacity.',
  ),
  'metallic': const MaterialHint(
    RangeHint(0.0, 1.0, step: 0.01),
    label: 'Metallic',
    help:
        'Nought is a dielectric, one is bare metal. The values between the '
        'two describe no real material and are there for blending between them.',
  ),
  'roughness': const MaterialHint(
    RangeHint(0.0, 1.0, step: 0.01),
    label: 'Roughness',
    help: 'How wide the highlight spreads. Nought is a mirror.',
  ),
  'occlusionStrength': const MaterialHint(
    RangeHint(0.0, 1.0, step: 0.01),
    label: 'Occlusion strength',
    help: 'How much of the occlusion map is applied. Nought ignores it.',
  ),
  'normalScale': const MaterialHint(
    RangeHint(0.0, 1.0, step: 0.01),
    label: 'Normal scale',
    help: 'How far the normal map is allowed to tilt the surface.',
  ),
  'emissive': const MaterialHint(
    ColorHint(channels: 3),
    label: 'Emissive',
    help:
        'The colour the surface glows in. It has no alpha: a surface does '
        'not glow transparently.',
  ),
  // Both enums are derived from the lists the engine already keeps rather than
  // spelled out again. `SurfaceAlphaMode.values` in a `switch` with no default
  // is what makes a fourth mode a compile error here instead of a picker that
  // quietly cannot offer it; `LightingModel.builtIn` is described where it is
  // declared as the list a picker should show, and this is that picker.
  'alphaMode': MaterialHint(
    EnumHint(<EnumHintValue>[
      for (final mode in SurfaceAlphaMode.values)
        EnumHintValue(
          mode.name,
          label: switch (mode) {
            SurfaceAlphaMode.opaque => 'Opaque',
            SurfaceAlphaMode.mask => 'Cut out at the threshold',
            SurfaceAlphaMode.blend => 'Blended',
            _ => mode.name,
          },
        ),
    ]),
    label: 'Alpha',
  ),
  'lightingModel': MaterialHint(
    EnumHint(<EnumHintValue>[
      for (final model in LightingModel.builtIn)
        EnumHintValue(model.shaderName, label: model.label),
    ]),
    label: 'Shader',
    help:
        'The shaders this engine ships. A material may name one of its own '
        'instead, and must then say what that shader binds.',
  ),
};
