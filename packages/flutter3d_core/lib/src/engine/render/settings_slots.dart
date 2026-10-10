/// Typed settings slots: the settings an addon owns, carried by
/// [RenderSettings] without the kernel knowing their type.
///
/// **A part of `render_settings.dart`**, so the built-in slots can read and
/// write the fields [RenderSettings] has always had without either side
/// publishing an accessor for the other.
part of 'render_settings.dart';

/// A kind of settings [RenderSettings] carries for whoever defined it — the
/// key [RenderSettings.extension] reads by and [RenderSettings.withExtension]
/// writes by.
///
/// **What lets an addon own its settings without touching the kernel.** A
/// package that draws frost defines `FrostSettings`, a slot for it, and a
/// render step that reads it:
///
/// ```dart
/// const frost = SettingsSlot<FrostSettings>(
///   'acme_frost.frost',
///   defaults: FrostSettings(),
///   toJson: FrostSettings.toJsonOf,
///   fromJson: FrostSettings.fromJsonOf,
/// );
///
/// const frostStep = RenderStep(
///   'frost',
///   switchOff: _frostOff,
///   isOn: _frostOn,
/// );
/// RenderSettings _frostOff(RenderSettings s) =>
///     s.withExtension(frost, s.extension(frost).copyWith(enabled: false));
/// bool _frostOn(RenderSettings s) => s.extension(frost).enabled;
/// ```
///
/// **Keyed by [id], not by the Dart type.** A runtime type is minified on the
/// web, and a level written on one build has to be read by another; the id
/// is a stable name, the package's and the setting's, as a plugin's id is.
/// The slot carries its own [defaults], so reading a slot nobody has written
/// needs no registry: two engines in one process share nothing through this
/// type. A renderer lists the slots its plugins brought in
/// `RendererSteps.settings`, which is what a settings screen walks and what
/// a level's `renderSettings` section is decoded against.
///
/// **The built-in settings are slots too** — [bloom], [fog] and the rest —
/// so an addon reads its family's settings through the same call a
/// third-party one does. They are still fields of [RenderSettings]: the
/// renderer's passes read those fields, and a field typed by a class defined
/// in an addon would make the kernel depend on the addon. A built-in slot
/// reads and writes its field; it has no codec, since the field is already
/// part of every [RenderSettings] an application builds in code.
final class SettingsSlot<T extends Object> {
  /// A slot called [id] whose value is [defaults] until somebody writes one.
  ///
  /// Give [toJson] and [fromJson] both, or neither: with both, the value
  /// travels in [SettingsExtensions.toJson] under [id]; without, it is kept
  /// in memory only and a document leaves it out.
  const SettingsSlot(
    this.id, {
    required this.defaults,
    Object? Function(T value)? toJson,
    T Function(Object? json)? fromJson,
  }) : // Private fields cannot be named initialising formals.
       // ignore: prefer_initializing_formals
       _toJson = toJson,
       // ignore: prefer_initializing_formals
       _fromJson = fromJson,
       _read = null,
       _write = null;

  const SettingsSlot._field(this.id, this.defaults, this._read, this._write)
    : _toJson = null,
      _fromJson = null;

  /// The stable name the value is stored and written under: the package's
  /// name, a dot and the setting's — `acme_frost.frost`. The built-in slots
  /// are named after their [RenderSettings] field.
  final String id;

  /// What [RenderSettings.extension] answers when nothing was written.
  final T defaults;

  final Object? Function(T value)? _toJson;
  final T Function(Object? json)? _fromJson;
  final T Function(RenderSettings settings)? _read;
  final RenderSettings Function(RenderSettings settings, T value)? _write;

  /// Whether this slot is one of [RenderSettings]'s own fields.
  bool get isBuiltIn => _read != null;

  /// Whether a value in this slot is written to a document.
  bool get isSerializable => _toJson != null && _fromJson != null;

  /// Whether [value] is of this slot's type.
  bool holds(Object? value) => value is T;

  /// [value] as JSON. Throws a [StateError] for a slot that is not
  /// [isSerializable], and an [ArgumentError] for a value of another type.
  Object? encode(Object value) {
    final write = _toJson;
    if (write == null) {
      throw StateError('settings slot "$id" has no JSON codec');
    }
    if (value is! T) {
      throw ArgumentError.value(value, 'value', 'is not a value of "$id"');
    }
    return write(value);
  }

  /// The value [json] describes. Throws a [StateError] for a slot that is
  /// not [isSerializable]; whatever the codec throws for a document it cannot
  /// read, it throws.
  T decode(Object? json) {
    final read = _fromJson;
    if (read == null) {
      throw StateError('settings slot "$id" has no JSON codec');
    }
    return read(json);
  }

  // Both through `this`, where `T` is the slot's own: a caller holding a
  // `SettingsSlot<Object>` reads a field typed by its `T` with a runtime
  // check that the function would fail.
  T _readFrom(RenderSettings settings) => _read!(settings);
  RenderSettings _writeInto(RenderSettings settings, Object value) =>
      _write!(settings, value as T);

  @override
  String toString() => 'SettingsSlot<$T>($id)';

  /// [RenderSettings.bloom], the light family's.
  static const SettingsSlot<BloomSettings> bloom = SettingsSlot._field(
    'bloom',
    BloomSettings(),
    _bloomOf,
    _withBloom,
  );

  /// [RenderSettings.look], the light family's grade, lens and film.
  static const SettingsSlot<LookSettings> look = SettingsSlot._field(
    'look',
    LookSettings(),
    _lookOf,
    _withLook,
  );

  /// [RenderSettings.autoExposure], the light family's meter.
  static const SettingsSlot<AutoExposureSettings> autoExposure =
      SettingsSlot._field(
        'autoExposure',
        AutoExposureSettings(),
        _autoExposureOf,
        _withAutoExposure,
      );

  /// [RenderSettings.localExposure], the light family's.
  static const SettingsSlot<LocalExposureSettings> localExposure =
      SettingsSlot._field(
        'localExposure',
        LocalExposureSettings(),
        _localExposureOf,
        _withLocalExposure,
      );

  /// [RenderSettings.ambientOcclusion], the shading family's.
  static const SettingsSlot<AmbientOcclusionSettings> ambientOcclusion =
      SettingsSlot._field(
        'ambientOcclusion',
        AmbientOcclusionSettings(),
        _ambientOcclusionOf,
        _withAmbientOcclusion,
      );

  /// [RenderSettings.contactShadows], the shading family's.
  static const SettingsSlot<ContactShadowSettings> contactShadows =
      SettingsSlot._field(
        'contactShadows',
        ContactShadowSettings(),
        _contactShadowsOf,
        _withContactShadows,
      );

  /// [RenderSettings.reflections], the reflections family's.
  static const SettingsSlot<ReflectionSettings> reflections =
      SettingsSlot._field(
        'reflections',
        ReflectionSettings(),
        _reflectionsOf,
        _withReflections,
      );

  /// [RenderSettings.planarReflections], the reflections family's.
  static const SettingsSlot<PlanarReflectionSettings> planarReflections =
      SettingsSlot._field(
        'planarReflections',
        PlanarReflectionSettings(),
        _planarReflectionsOf,
        _withPlanarReflections,
      );

  /// [RenderSettings.fog], the atmosphere family's.
  static const SettingsSlot<FogSettings> fog = SettingsSlot._field(
    'fog',
    FogSettings(),
    _fogOf,
    _withFog,
  );

  /// [RenderSettings.sky], the atmosphere family's.
  static const SettingsSlot<SkySettings> sky = SettingsSlot._field(
    'sky',
    SkySettings(),
    _skyOf,
    _withSky,
  );

  /// [RenderSettings.volumetricFog], the atmosphere family's.
  static const SettingsSlot<VolumetricFogSettings> volumetricFog =
      SettingsSlot._field(
        'volumetricFog',
        VolumetricFogSettings(),
        _volumetricFogOf,
        _withVolumetricFog,
      );

  /// [RenderSettings.lightShafts], the atmosphere family's.
  static const SettingsSlot<LightShaftSettings> lightShafts =
      SettingsSlot._field(
        'lightShafts',
        LightShaftSettings(),
        _lightShaftsOf,
        _withLightShafts,
      );

  /// [RenderSettings.depthOfField], the motion family's.
  static const SettingsSlot<DepthOfFieldSettings> depthOfField =
      SettingsSlot._field(
        'depthOfField',
        DepthOfFieldSettings(),
        _depthOfFieldOf,
        _withDepthOfField,
      );

  /// [RenderSettings.motionBlur], the motion family's.
  static const SettingsSlot<MotionBlurSettings> motionBlur =
      SettingsSlot._field(
        'motionBlur',
        MotionBlurSettings(),
        _motionBlurOf,
        _withMotionBlur,
      );

  /// [RenderSettings.antiAlias], whose temporal resolve is the motion
  /// family's.
  static const SettingsSlot<AntiAliasSettings> antiAlias = SettingsSlot._field(
    'antiAlias',
    AntiAliasSettings(),
    _antiAliasOf,
    _withAntiAlias,
  );

  /// [RenderSettings.highContrast], the style family's.
  static const SettingsSlot<HighContrastSettings> highContrast =
      SettingsSlot._field(
        'highContrast',
        HighContrastSettings(),
        _highContrastOf,
        _withHighContrast,
      );

  /// [RenderSettings.viewportShading], the style family's.
  static const SettingsSlot<ViewportShadingSettings> viewportShading =
      SettingsSlot._field(
        'viewportShading',
        ViewportShadingSettings(),
        _viewportShadingOf,
        _withViewportShading,
      );

  /// Every built-in slot, in the order the families are listed in
  /// `flutter3d_post`'s plugin marker.
  static const List<SettingsSlot<Object>> builtIn = <SettingsSlot<Object>>[
    bloom,
    look,
    autoExposure,
    localExposure,
    ambientOcclusion,
    contactShadows,
    reflections,
    planarReflections,
    fog,
    sky,
    volumetricFog,
    lightShafts,
    depthOfField,
    motionBlur,
    antiAlias,
    highContrast,
    viewportShading,
  ];
}

BloomSettings _bloomOf(RenderSettings s) => s.bloom;
RenderSettings _withBloom(RenderSettings s, BloomSettings v) =>
    s.copyWith(bloom: v);
LookSettings _lookOf(RenderSettings s) => s.look;
RenderSettings _withLook(RenderSettings s, LookSettings v) =>
    s.copyWith(look: v);
AutoExposureSettings _autoExposureOf(RenderSettings s) => s.autoExposure;
RenderSettings _withAutoExposure(RenderSettings s, AutoExposureSettings v) =>
    s.copyWith(autoExposure: v);
LocalExposureSettings _localExposureOf(RenderSettings s) => s.localExposure;
RenderSettings _withLocalExposure(RenderSettings s, LocalExposureSettings v) =>
    s.copyWith(localExposure: v);
AmbientOcclusionSettings _ambientOcclusionOf(RenderSettings s) =>
    s.ambientOcclusion;
RenderSettings _withAmbientOcclusion(
  RenderSettings s,
  AmbientOcclusionSettings v,
) => s.copyWith(ambientOcclusion: v);
ContactShadowSettings _contactShadowsOf(RenderSettings s) => s.contactShadows;
RenderSettings _withContactShadows(RenderSettings s, ContactShadowSettings v) =>
    s.copyWith(contactShadows: v);
ReflectionSettings _reflectionsOf(RenderSettings s) => s.reflections;
RenderSettings _withReflections(RenderSettings s, ReflectionSettings v) =>
    s.copyWith(reflections: v);
PlanarReflectionSettings _planarReflectionsOf(RenderSettings s) =>
    s.planarReflections;
RenderSettings _withPlanarReflections(
  RenderSettings s,
  PlanarReflectionSettings v,
) => s.copyWith(planarReflections: v);
FogSettings _fogOf(RenderSettings s) => s.fog;
RenderSettings _withFog(RenderSettings s, FogSettings v) => s.copyWith(fog: v);
SkySettings _skyOf(RenderSettings s) => s.sky;
RenderSettings _withSky(RenderSettings s, SkySettings v) => s.copyWith(sky: v);
VolumetricFogSettings _volumetricFogOf(RenderSettings s) => s.volumetricFog;
RenderSettings _withVolumetricFog(RenderSettings s, VolumetricFogSettings v) =>
    s.copyWith(volumetricFog: v);
LightShaftSettings _lightShaftsOf(RenderSettings s) => s.lightShafts;
RenderSettings _withLightShafts(RenderSettings s, LightShaftSettings v) =>
    s.copyWith(lightShafts: v);
DepthOfFieldSettings _depthOfFieldOf(RenderSettings s) => s.depthOfField;
RenderSettings _withDepthOfField(RenderSettings s, DepthOfFieldSettings v) =>
    s.copyWith(depthOfField: v);
MotionBlurSettings _motionBlurOf(RenderSettings s) => s.motionBlur;
RenderSettings _withMotionBlur(RenderSettings s, MotionBlurSettings v) =>
    s.copyWith(motionBlur: v);
AntiAliasSettings _antiAliasOf(RenderSettings s) => s.antiAlias;
RenderSettings _withAntiAlias(RenderSettings s, AntiAliasSettings v) =>
    s.copyWith(antiAlias: v);
HighContrastSettings _highContrastOf(RenderSettings s) => s.highContrast;
RenderSettings _withHighContrast(RenderSettings s, HighContrastSettings v) =>
    s.copyWith(highContrast: v);
ViewportShadingSettings _viewportShadingOf(RenderSettings s) =>
    s.viewportShading;
RenderSettings _withViewportShading(
  RenderSettings s,
  ViewportShadingSettings v,
) => s.copyWith(viewportShading: v);

/// A value written into a slot, with the slot that can encode it.
final class _Held {
  const _Held(this.slot, this.value);
  final SettingsSlot<Object> slot;
  final Object value;
}

/// The values [RenderSettings] holds in slots that are not its own fields —
/// [RenderSettings.extensions].
///
/// **Immutable, compared by value, and written by id.** [put] and [remove]
/// return a new one; two are equal when they hold the same ids with equal
/// values, a value's own `==` deciding — so a settings class of an addon's
/// that wants its edits noticed defines one. [toJson] writes each value of a
/// [SettingsSlot.isSerializable] slot under its id.
///
/// **What a document names and this build cannot read is kept, not
/// dropped.** [SettingsExtensions.fromJson] decodes the ids it is handed
/// slots for and keeps the rest as the JSON it was; [toJson] writes that
/// back unchanged, and [valueOf] decodes it the first time somebody asks
/// with the slot. A level saved by an editor without the frost addon keeps
/// its frost.
final class SettingsExtensions {
  /// None.
  const SettingsExtensions()
    : _held = const <String, _Held>{},
      _raw = const <String, Object?>{};

  const SettingsExtensions._(this._held, this._raw);

  /// Reads [json], an object of ids, decoding each id one of [slots] has.
  ///
  /// An id none of [slots] has is kept as its JSON, for [valueOf] to decode
  /// later and [toJson] to write back. An id whose slot cannot read it is
  /// kept the same way, with a sentence added to [warnings] when it is
  /// given — a document is not refused for one addon's settings.
  factory SettingsExtensions.fromJson(
    Map<String, Object?> json, {
    Iterable<SettingsSlot<Object>> slots = const <SettingsSlot<Object>>[],
    List<String>? warnings,
  }) {
    final byId = <String, SettingsSlot<Object>>{
      for (final slot in slots)
        if (slot.isSerializable) slot.id: slot,
    };
    final held = <String, _Held>{};
    final raw = <String, Object?>{};
    for (final MapEntry(:key, :value) in json.entries) {
      final slot = byId[key];
      if (slot == null) {
        raw[key] = value;
        continue;
      }
      try {
        held[key] = _Held(slot, slot.decode(value));
      } on Object catch (error) {
        warnings?.add(
          'render settings "$key" could not be read ($error); kept as '
          'written',
        );
        raw[key] = value;
      }
    }
    return SettingsExtensions._(
      Map<String, _Held>.unmodifiable(held),
      Map<String, Object?>.unmodifiable(raw),
    );
  }

  final Map<String, _Held> _held;
  final Map<String, Object?> _raw;

  /// Whether nothing is held, decoded or not.
  bool get isEmpty => _held.isEmpty && _raw.isEmpty;

  /// The ids held, decoded or still JSON.
  Set<String> get ids => <String>{..._held.keys, ..._raw.keys};

  /// The value in [slot], or null when nothing was written there.
  ///
  /// A value still held as JSON is decoded with [slot] — each call, since
  /// this is immutable; a caller reading it every frame writes it back with
  /// [put] once.
  T? valueOf<T extends Object>(SettingsSlot<T> slot) {
    final held = _held[slot.id];
    if (held != null) {
      final value = held.value;
      return value is T ? value : null;
    }
    if (!_raw.containsKey(slot.id) || !slot.isSerializable) return null;
    try {
      return slot.decode(_raw[slot.id]);
    } on Object {
      return null;
    }
  }

  /// These with [value] in [slot], replacing whatever was there.
  ///
  /// Throws an [ArgumentError] for a built-in slot: that value is a field
  /// of [RenderSettings], which [RenderSettings.withExtension] writes.
  SettingsExtensions put<T extends Object>(SettingsSlot<T> slot, T value) {
    if (slot.isBuiltIn) {
      throw ArgumentError.value(
        slot.id,
        'slot',
        'is a field of RenderSettings; write it with withExtension or '
            'copyWith',
      );
    }
    return SettingsExtensions._(
      Map<String, _Held>.unmodifiable(<String, _Held>{
        ..._held,
        slot.id: _Held(slot, value),
      }),
      Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final MapEntry(:key, :value) in _raw.entries)
          if (key != slot.id) key: value,
      }),
    );
  }

  /// These without anything under [id], decoded or not.
  SettingsExtensions remove(String id) => SettingsExtensions._(
    Map<String, _Held>.unmodifiable(<String, _Held>{
      for (final MapEntry(:key, :value) in _held.entries)
        if (key != id) key: value,
    }),
    Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final MapEntry(:key, :value) in _raw.entries)
        if (key != id) key: value,
    }),
  );

  /// Each value by its slot's id: decoded ones through their slot's codec,
  /// the rest as they were read. A value in a slot with no codec is left
  /// out — it was never meant for a document.
  Map<String, Object?> toJson() => <String, Object?>{
    for (final MapEntry(:key, :value) in _held.entries)
      if (value.slot.isSerializable) key: value.slot.encode(value.value),
    ..._raw,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SettingsExtensions) return false;
    final mine = ids;
    final theirs = other.ids;
    if (mine.length != theirs.length || !mine.containsAll(theirs)) {
      return false;
    }
    for (final id in mine) {
      if (!_sameEntry(id, other)) return false;
    }
    return true;
  }

  bool _sameEntry(String id, SettingsExtensions other) {
    final a = _held[id];
    final b = other._held[id];
    if (a != null && b != null) return a.value == b.value;
    // One side or both still JSON: compared as JSON, which is what the two
    // would be written as.
    Object? asJson(SettingsExtensions of, _Held? held) => held == null
        ? of._raw[id]
        : held.slot.isSerializable
        ? held.slot.encode(held.value)
        : held;
    return _jsonEquals(asJson(this, a), asJson(other, b));
  }

  @override
  int get hashCode => Object.hashAllUnordered(ids);

  @override
  String toString() => 'SettingsExtensions(${ids.join(', ')})';
}

bool _jsonEquals(Object? a, Object? b) => switch ((a, b)) {
  (final Map<Object?, Object?> x, final Map<Object?, Object?> y) =>
    x.length == y.length &&
        x.keys.every((k) => y.containsKey(k) && _jsonEquals(x[k], y[k])),
  (final List<Object?> x, final List<Object?> y) =>
    x.length == y.length &&
        Iterable<int>.generate(
          x.length,
        ).every((int i) => _jsonEquals(x[i], y[i])),
  _ => a == b,
};
