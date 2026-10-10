import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// An event a run-time plugin published: a name its document declared and
/// the integers it handed over.
///
/// **One class for every event a module or a script publishes**, because
/// neither can define a Dart type. The name is what tells two apart — it is
/// `<plugin id>.<event>`, declared on the bus when the plugin is installed —
/// and [values] are what the publisher passed: two Q16.16 numbers from a Wasm
/// module, whatever a script chose. Subscribe to `PluginDataEvent` and match
/// on [name].
final class PluginDataEvent extends BusEvent {
  const PluginDataEvent(this.name, this.values);

  @override
  final String name;

  /// What the publisher passed, in order.
  final List<int> values;

  /// How an event named [name] is written: its values, in order. One codec
  /// per declared name, since the name is not in the encoding.
  static EventCodec<PluginDataEvent> codecFor(String name) =>
      EventCodec<PluginDataEvent>.of(
        encode: (event) => List<int>.of(event.values),
        decode: (data, _) => data is List && data.every((v) => v is int)
            ? PluginDataEvent(name, List<int>.unmodifiable(data.cast<int>()))
            : null,
      );

  @override
  void digestInto(EventDigestSink sink) {
    for (final value in values) {
      sink.add(value);
    }
  }

  @override
  String toString() => '$name(${values.join(', ')})';
}
