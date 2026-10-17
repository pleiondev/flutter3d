import 'dart:convert';

import 'level_format_exception.dart';

/// The render settings a level asks for, by settings slot id, and nothing it
/// does not ask for.
///
/// **Data, read before any renderer.** A level is read by a server with no
/// renderer and by a tool with no device, so this holds each slot's JSON —
/// what `SettingsExtensions.toJson` writes — and the renderer decodes it
/// against the slots its plugins added (`SettingsExtensions.fromJson(
/// patch.toJson(), slots: renderer.renderSteps.settings)`). An id no
/// installed plugin knows is kept and written back as it was read.
///
/// A patch, not whole settings: what it leaves out is the game's own.
final class RenderSettingsPatch {
  /// A patch asking for [bySlot]: each slot's settings, as their JSON.
  factory RenderSettingsPatch(Map<String, Object?> bySlot) =>
      RenderSettingsPatch.fromJson(bySlot);

  const RenderSettingsPatch._(this._json);

  /// The patch [json] writes: an object of settings by slot id. Throws a
  /// [LevelFormatException] for a value JSON cannot carry.
  factory RenderSettingsPatch.fromJson(Map<String, Object?> json) {
    if (json.isEmpty) return empty;
    final copy = Map<String, Object?>.unmodifiable(<String, Object?>{...json});
    try {
      jsonEncode(copy);
    } on JsonUnsupportedObjectError catch (error, stackTrace) {
      Error.throwWithStackTrace(
        LevelFormatException(
          'render settings are JSON: ${error.unsupportedObject} is not',
        ),
        stackTrace,
      );
    }
    return RenderSettingsPatch._(copy);
  }

  /// The patch that asks for nothing.
  static const RenderSettingsPatch empty = RenderSettingsPatch._(
    <String, Object?>{},
  );

  final Map<String, Object?> _json;

  /// Whether this patch asks for nothing.
  bool get isEmpty => _json.isEmpty;

  /// The slot ids it names, in the order they were written.
  Iterable<String> get ids => _json.keys;

  /// The settings it asks of the slot [id], as JSON; null when it names
  /// none (absent).
  Object? operator [](String id) => _json[id];

  /// The document: settings by slot id, as they were written.
  Map<String, Object?> toJson() => <String, Object?>{..._json};

  @override
  bool operator ==(Object other) =>
      other is RenderSettingsPatch &&
      jsonEncode(other._json) == jsonEncode(_json);

  @override
  int get hashCode => jsonEncode(_json).hashCode;

  @override
  String toString() => 'RenderSettingsPatch(${jsonEncode(_json)})';
}
