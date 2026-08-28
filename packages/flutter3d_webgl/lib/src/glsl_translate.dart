/// Turns the engine's GLSL into GLSL ES 3.00, which is what WebGL2 compiles.
///
/// The engine's shaders are written for `impellerc`: `#version 460 core`, an
/// `#include` extension impellerc resolves, and uniform blocks whose packing
/// impellerc decides. None of that reaches a browser, and none of it is where
/// the shading actually lives — the lighting model, the shadow lookup and the
/// tone mapping are ordinary GLSL that both dialects accept unchanged.
///
/// So this translates rather than duplicates. A second hand-written set of
/// shaders would be nineteen hundred lines kept in step by discipline, and the
/// first divergence would show up as one backend lighting a scene differently
/// from the other — a difference nobody would think to look for.
///
/// Pure text in, pure text out, so every rule below is testable without a
/// browser. What it cannot check is whether the result *compiles*; that is what
/// the harness is for.
library;

/// A source file the translator can read.
///
/// A map rather than the filesystem, because the translator runs both from a
/// build script and from a test, and only one of those has files.
typedef GlslSources = Map<String, String>;

/// Raised when translation cannot continue. Carries the file it happened in,
/// because an error naming only a line number is an error in nineteen hundred
/// lines of identical-looking GLSL.
final class GlslTranslateError implements Exception {
  const GlslTranslateError(this.message);

  final String message;

  @override
  String toString() => 'GlslTranslateError: $message';
}

/// Resolves `#include <path>` against [sources].
///
/// Depth-first, and a file already pulled in is skipped rather than repeated —
/// the headers include each other (`material_maps` → `surface` → `color`), so
/// without that the second inclusion redeclares every uniform and the compile
/// fails on a duplicate rather than on anything real.
///
/// A cycle is an error and not a silent stop: the include graph here is a tree
/// by design, and a cycle means somebody changed that without noticing.
String resolveIncludes(
  String source,
  GlslSources sources, {
  required String from,
  Set<String>? seen,
  List<String>? stack,
}) {
  final included = seen ?? <String>{};
  final path = stack ?? <String>[from];
  final out = StringBuffer();

  for (final line in source.split('\n')) {
    final match = _include.firstMatch(line);
    if (match == null) {
      out.writeln(line);
      continue;
    }
    final target = match.group(1)!;
    if (path.contains(target)) {
      throw GlslTranslateError(
        'include cycle: ${<String>[...path, target].join(' -> ')}',
      );
    }
    if (!included.add(target)) continue;
    final body = sources[target];
    if (body == null) {
      throw GlslTranslateError('$from includes "$target", which is not here');
    }
    // The included text is translated by the same rules, so a header's own
    // includes and its version line are handled once rather than per includer.
    out.writeln('// --- $target ---');
    out.write(
      resolveIncludes(
        body,
        sources,
        from: target,
        seen: included,
        stack: <String>[...path, target],
      ),
    );
  }
  return out.toString();
}

/// The whole translation, for one stage.
///
/// [fragment] decides two rules that differ by stage rather than by file, and
/// the caller knows which it is asking for — the manifest says so.
String translateGlsl(
  String source,
  GlslSources sources, {
  required String from,
  required bool fragment,
}) {
  var text = resolveIncludes(source, sources, from: from);

  // Every version line, including the ones that arrived inside a header. ES
  // wants exactly one and it must come first.
  text = text.replaceAll(_version, '');

  // Uniform blocks get std140 explicitly. impellerc chose a packing and told
  // the Dart side what it chose; here both ends have to agree in advance, and
  // std140 is the only layout GLSL ES 3.00 guarantees. Without this the block
  // still compiles and the members land at offsets the caller did not write to.
  text = text.replaceAllMapped(
    _uniformBlock,
    (m) => 'layout(std140) uniform ${m.group(1)}',
  );

  // The first fragment output needs a location once a second one exists. The
  // engine's surface buffer already declares location 1, so an unqualified
  // `out` beside it is a link error rather than an assumption about slot zero.
  if (fragment) {
    text = text.replaceAllMapped(
      _bareOut,
      (m) => 'layout(location = 0) out ${m.group(1)}',
    );
  }

  final header = StringBuffer('#version 300 es\n');
  if (fragment) {
    // Fragment shaders have no default precision for float in ES, and a shader
    // without one does not compile. highp because this engine renders to a
    // half-float target and mediump on a mobile GPU is ten bits of mantissa —
    // banding in every gradient, and a shadow comparison that quantises.
    header
      ..writeln('precision highp float;')
      ..writeln('precision highp int;')
      ..writeln('precision highp sampler2D;')
      // And the cube sampler, for the same reason: a sampler type with no
      // declared precision is a shader that does not compile, and the sky is
      // the first stage here to declare one.
      ..writeln('precision highp samplerCube;');
  }
  header.write(text);
  return header.toString();
}

final RegExp _include = RegExp(r'^\s*#include\s*[<"]([^>"]+)[>"]');
final RegExp _version = RegExp(r'^\s*#version[^\n]*\n', multiLine: true);
final RegExp _uniformBlock = RegExp(
  r'^uniform\s+([A-Z]\w*\s*\{)',
  multiLine: true,
);
final RegExp _bareOut = RegExp(r'^out\s+(\w+\s+\w+\s*;)', multiLine: true);
