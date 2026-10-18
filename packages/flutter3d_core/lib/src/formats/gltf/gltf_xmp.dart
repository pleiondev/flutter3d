/// The document's `KHR_xmp_json_ld` packet: who made a model and on what
/// terms, read for `DocumentAsset` and written back with the rest of the
/// packet untouched.
///
/// **Only the document's packet.** The extension lets any object point at
/// a packet; the root `asset` pointing at one is the model's own metadata,
/// and it is the one this package reads. Its JSON-LD is carried whole, so a
/// key nothing here reads (`xmp:CreatorTool`, `dc:title`, a vendor's own)
/// survives a write; [authorOf] and [licenseOf] are the two it reads.
library;

/// The extension's name, as `extensionsUsed` lists it.
const String xmpExtension = 'KHR_xmp_json_ld';

/// Dublin Core's namespace, which `dc:creator` and `dc:rights` are in.
const String _dublinCore = 'http://purl.org/dc/elements/1.1/';

/// The packet the root `asset` of [json] points at, or null when it points
/// at none or at one the file does not have.
Map<String, Object?>? documentXmpPacket(Map<String, Object?> json) {
  final asset = json['asset'];
  final assetExtensions = asset is Map ? asset['extensions'] : null;
  final pointer = assetExtensions is Map ? assetExtensions[xmpExtension] : null;
  final index = pointer is Map ? pointer['packet'] : null;
  final rootExtensions = json['extensions'];
  final block = rootExtensions is Map ? rootExtensions[xmpExtension] : null;
  final packets = block is Map ? block['packets'] : null;
  if (index is! int || packets is! List) return null;
  if (index < 0 || index >= packets.length) return null;
  final packet = packets[index];
  return packet is Map ? packet.cast<String, Object?>() : null;
}

/// The author [packet] names: its `dc:creator`, several joined with `, `.
String? authorOf(Map<String, Object?>? packet) => _text(packet?['dc:creator']);

/// The licence [packet] states: its `dc:rights`.
String? licenseOf(Map<String, Object?>? packet) => _text(packet?['dc:rights']);

/// The packet to write for a document whose packet was [packet] (null for
/// none) and whose author and licence are now [author] and [license]; null
/// when there is nothing to write.
///
/// A value that still reads as what the packet says is left in the
/// packet's own shape (an `@list`, a language map); a changed one is
/// written as plain text, and `dc` is added to the context when the packet
/// did not declare it.
Map<String, Object?>? packetToWrite(
  Map<String, Object?>? packet, {
  required String? author,
  required String? license,
}) {
  if (packet == null && author == null && license == null) return null;
  final out = <String, Object?>{...?packet};
  var touched = false;
  if (author != null && authorOf(packet) != author) {
    out['dc:creator'] = <String, Object?>{
      '@list': <Object?>[author],
    };
    touched = true;
  }
  if (license != null && licenseOf(packet) != license) {
    out['dc:rights'] = license;
    touched = true;
  }
  if (touched) {
    final context = out['@context'];
    if (context == null) {
      out['@context'] = <String, Object?>{'dc': _dublinCore};
    } else if (context is Map && !context.containsKey('dc')) {
      out['@context'] = <String, Object?>{
        ...context.cast<String, Object?>(),
        'dc': _dublinCore,
      };
    }
  }
  return out;
}

/// The text a JSON-LD value holds: a string, a value object's `@value`, or
/// the texts of an `@list`, an `@set` or a plain list joined with `, `.
String? _text(Object? value) {
  switch (value) {
    case final String text:
      return text;
    case {'@value': final String text}:
      return text;
    case {'@list': final List<Object?> items} ||
        {'@set': final List<Object?> items}:
      return _joined(items);
    case final List<Object?> items:
      return _joined(items);
    default:
      return null;
  }
}

String? _joined(List<Object?> items) {
  final texts = <String>[for (final item in items) ?_text(item)];
  return texts.isEmpty ? null : texts.join(', ');
}
