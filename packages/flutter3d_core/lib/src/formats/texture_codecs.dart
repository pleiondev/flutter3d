/// Image formats a plugin reads, beside the model decoders (D22b).
library;

import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        NameTakenException,
        PluginException,
        PluginRegistry,
        PluginScope,
        Registration;

import 'ktx2/encode/rgba8_image.dart';

/// What a [TextureCodec] is handed for one encoded image: one object that
/// can gain members, rather than a list of parameters that grows.
final class TextureDecodeContext {
  const TextureDecodeContext({
    required this.bytes,
    this.maxDimension,
    this.report,
  });

  /// The encoded image, whole.
  final Uint8List bytes;

  /// The longest side the result may have, in pixels, or null for no cap:
  /// a codec that can decode at a smaller size does, and one that cannot is
  /// scaled down afterwards.
  final int? maxDimension;

  /// Where a codec says why it left an image out, in a sentence naming the
  /// format; null loses the sentence.
  final void Function(String message)? report;
}

/// An image format of a plugin's own — DDS, TGA, a game's packed format —
/// read into RGBA8 pixels the engine uploads like a PNG's (D22b).
///
/// **Beside the engine's own decoders, and asked before them.** A texture
/// the engine loads (`uploadEncodedImage`) is offered first to every codec
/// registered with [TextureCodecs], in order, then to the engine's KTX2 and
/// Basis transcoders, the browser's decoder and the image decoder the
/// application gave. The first codec whose [sniff] claims the bytes decodes
/// them. Extendable outside this package, and stays so through 1.x.
abstract base class TextureCodec {
  const TextureCodec();

  /// The codec's name, in its plugin's namespace: `acme_dds.dds`.
  String get name;

  /// Whether [head] — the first bytes of a file, at least sixteen where the
  /// file has them — is in this codec's format.
  bool sniff(Uint8List head);

  /// The image [context] holds, as RGBA8 pixels, or null for one this codec
  /// claimed and cannot read (said through [TextureDecodeContext.report]).
  Future<Rgba8Image?> decode(TextureDecodeContext context);

  @override
  String toString() => 'TextureCodec($name)';
}

/// The image formats plugins brought, asked in the order they were
/// registered — the application's first, then each plugin's.
///
/// Reached by a plugin as `host.registry<TextureCodecs>()`, a companion of
/// the `ModelDecoders` the engine hands its plugin host
/// (`ModelDecoders.textureCodecs`).
final class TextureCodecs extends PluginRegistry {
  /// An empty registry.
  TextureCodecs() : _codecs = <TextureCodec>[], _scope = null;

  TextureCodecs._scoped(this._codecs, this._scope);

  final List<TextureCodec> _codecs;
  final PluginScope? _scope;

  /// Every codec, in the order they are asked.
  List<TextureCodec> get codecs => List<TextureCodec>.unmodifiable(_codecs);

  /// The first codec that claims [bytes], or null.
  TextureCodec? codecFor(Uint8List bytes) {
    for (final codec in _codecs) {
      if (codec.sniff(bytes)) return codec;
    }
    return null;
  }

  /// Adds [codec] until the result is cancelled. Through a plugin's view, a
  /// [PluginException] for a codec named outside the plugin's namespace;
  /// a [NameTakenException] for a name another codec has.
  Registration add(TextureCodec codec) {
    final problem = _scope?.manifest.nameProblem(
      codec.name,
      what: 'the texture codec',
    );
    if (problem != null) throw PluginException(problem);
    if (_codecs.any((other) => other.name == codec.name)) {
      throw NameTakenException(codec.name, what: 'the texture codec');
    }
    _codecs.add(codec);
    final registration = Registration(() => _codecs.remove(codec));
    _scope?.track(registration);
    return registration;
  }

  @override
  TextureCodecs forPlugin(PluginScope scope) =>
      TextureCodecs._scoped(_codecs, scope);
}
