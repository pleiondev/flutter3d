/// `mat-05`: what a texture slot shows before anything decodes a pixel.
///
/// **Reads the header, not the file's own on-device weight.** `TextureInfo`
/// from `flutter3d_model_core` already computes what a texture costs once
/// uploaded — decoded RGBA for a PNG, the same bytes as disk for a
/// block-compressed KTX2 — and that is the right number for a texture budget,
/// wrong for a slot's own "170 KB". A slot is answering "how big is the file
/// I attached", which for a PNG is a tenth of what it decodes to; this reads
/// [EncodedImage.bytes]'s own length instead of borrowing the budget's answer.
///
/// **Its own English words, not `flutter3d_model_core`'s `formatByteSize`.**
/// That one prints "КБ"/"МБ" — the level editor's own Russian panels are what
/// it was built for — and this modeller's panels are English throughout,
/// "None"/"Choose…"/"Clear" among them; borrowing it here would be the one
/// texture-slot row on an English screen reading its weight in Cyrillic.
/// [_weightText] is the same tiering and the same rounding rule, spelled in
/// this app's own words instead.
///
/// **`texCoordSet` is not read from anywhere.** `mat-05`'s acceptance is "only
/// 0" — every [TextureBinding] this reader is handed is shown at set 0
/// regardless of what it actually carries, because a selector for set 1+ is a
/// different item's scope, not this one's bug.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// A slot's own texcoord set, per `mat-05`'s acceptance: always 0, whatever a
/// binding actually names.
const int textureSlotTexCoordSet = 0;

/// What a texture slot's row needs to draw, computed once from an image's
/// encoded bytes.
final class TextureSlotDisplay {
  const TextureSlotDisplay({
    required this.name,
    required this.dimensionsText,
    required this.weightText,
    required this.formatBadge,
    required this.thumbnail,
  });

  /// What to show as the file's own name — never a path, the same rule
  /// [EncodedImage.name] itself follows.
  final String name;

  /// `"256×128"`, or null when [thumbnail]'s header could not be read —
  /// truncated bytes, or a format none of PNG/JPEG/KTX2's headers match.
  final String? dimensionsText;

  /// `"170 KB"`, from the file's own length — see the library doc comment for
  /// why this is not [TextureInfo.bytesOnDevice].
  final String weightText;

  /// The badge a slot shows beside the thumbnail — null for a plain PNG/JPEG,
  /// since "RGBA8" is every ordinary texture and a badge that always shows
  /// would say nothing. See [formatBadgeFor].
  final String? formatBadge;

  /// The encoded bytes themselves, for a thumbnail decoder to draw — 26×26,
  /// per `mat-05`'s acceptance, is the row's concern, not this class's.
  final Uint8List thumbnail;
}

/// [image]'s own slot display, reading no more than its bytes' header.
///
/// [fallbackName] is what to show when [EncodedImage.name] is null — an image
/// that arrived embedded in a glTF buffer view, say, rather than named by a
/// sibling file.
TextureSlotDisplay textureSlotDisplay(
  EncodedImage image, {
  String fallbackName = 'untitled',
}) {
  final info = textureInfo(image.bytes);
  return TextureSlotDisplay(
    name: image.name ?? fallbackName,
    dimensionsText: info == null ? null : '${info.width}×${info.height}',
    weightText: _weightText(image.bytes.length),
    formatBadge: info == null ? null : formatBadgeFor(info.format),
    thumbnail: image.bytes,
  );
}

/// [bytes] as `"170 KB"`, `"3 MB"` — see the library doc comment for why this
/// is its own small copy of `flutter3d_model_core`'s `formatByteSize` rather
/// than a call to it.
String _weightText(int bytes) {
  const int kb = 1024;
  const int mb = kb * 1024;
  const int gb = mb * 1024;
  if (bytes < kb) return '$bytes B';
  if (bytes < mb) return '${(bytes / kb).round()} KB';
  if (bytes < gb) return '${(bytes / mb).round()} MB';
  return '${(bytes / gb).round()} GB';
}

/// The badge text for [format], or null for [TextureFileFormat.rgba8] — see
/// [TextureSlotDisplay.formatBadge].
String? formatBadgeFor(TextureFileFormat format) => switch (format) {
  TextureFileFormat.rgba8 => null,
  TextureFileFormat.bc1 => 'BC1',
  TextureFileFormat.bc3 => 'BC3',
  TextureFileFormat.bc7 => 'BC7',
  TextureFileFormat.etc2Rgba8 => 'ETC2',
  TextureFileFormat.astc4x4 => 'ASTC 4×4',
  TextureFileFormat.other => 'KTX2',
};

/// The four numbers a `TextureSampling` actually varies, as the words a
/// parameter row shows rather than the booleans and enum this repository's
/// [TextureSampling] itself is stored as.
final class TextureSamplingDisplay {
  const TextureSamplingDisplay({
    required this.magFilterLabel,
    required this.minFilterLabel,
    required this.wrapSLabel,
    required this.wrapTLabel,
  });

  final String magFilterLabel;
  final String minFilterLabel;
  final String wrapSLabel;
  final String wrapTLabel;
}

/// [sampling]'s own four fields, worded for a parameter row.
///
/// [TextureSampling.useMipmaps] and [TextureSampling.mipLinear] are folded
/// into [minFilterLabel] rather than shown as a fifth field of their own —
/// `"Linear, mipmapped"` says what the minification filter actually does,
/// which a separate "uses mipmaps: yes" checkbox next to it would only repeat
/// in fewer words.
TextureSamplingDisplay textureSamplingDisplay(TextureSampling sampling) =>
    TextureSamplingDisplay(
      magFilterLabel: sampling.magLinear ? 'Linear' : 'Nearest',
      minFilterLabel: _minFilterLabel(sampling),
      wrapSLabel: _wrapLabel(sampling.wrapS),
      wrapTLabel: _wrapLabel(sampling.wrapT),
    );

String _minFilterLabel(TextureSampling sampling) {
  final base = sampling.minLinear ? 'Linear' : 'Nearest';
  if (!sampling.useMipmaps) return base;
  return '$base, ${sampling.mipLinear ? 'mipmapped' : 'mipmapped (nearest mip)'}';
}

String _wrapLabel(TextureWrap wrap) => switch (wrap) {
  TextureWrap.repeat => 'Repeat',
  TextureWrap.clampToEdge => 'Clamp to edge',
  TextureWrap.mirroredRepeat => 'Mirrored repeat',
};
