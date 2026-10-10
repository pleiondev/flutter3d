/// MaterialX (`.mtlx`): each material's surface shader — `standard_surface`
/// or `UsdPreviewSurface` — becomes an `.fmat` when every input is a
/// constant or an image, and a `.f3dmat` program beside an `.fmat` that
/// names it when a node graph computes an input the material language can
/// say. A graph it cannot say is folded to the nearest metal-rough surface,
/// with a warning naming the node that stopped it.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';

import 'confine.dart';
import 'context.dart';
import 'materials.dart';
import 'output.dart';
import 'report.dart';
import 'surface_inputs.dart';
import 'xml.dart';

/// Converts the MaterialX document [source] into [context]'s plan.
Future<void> convertMaterialXInput(
  String source,
  ConvertContext context,
  ConvertReport report,
) async {
  final XmlElement root;
  try {
    root = parseXml(File(source).readAsStringSync());
  } on Object catch (error) {
    report.fail('could not read $source: $error');
    return;
  }
  if (root.name != 'materialx') {
    report.fail('the root element is <${root.name}>, not <materialx>');
    return;
  }
  final directory = File(source).parent.path;
  final document = _MtlxDocument(
    root,
    directory,
    report,
    bound: context.root ?? directory,
  );
  final materials = document.materials();
  if (materials.isEmpty) {
    report.warn('no surface material in the document');
  }
  for (final (name, shader) in materials) {
    final material = document.convert(name, shader);
    planMaterial(material, context.plan, owner: report.input, report: report);
    if (material.program != null) {
      // The parameters half: the images in their slots, and the program
      // named as the lighting.
      final companion = MaterialSource(
        material.id,
        material.surface,
        images: material.images,
      );
      planMaterial(
        companion,
        context.plan,
        owner: report.input,
        report: report,
      );
    }
  }
}

/// The surface shaders MaterialX documents use that map onto the engine's.
const Map<String, ShadingVocabulary> _vocabularies =
    <String, ShadingVocabulary>{
      'standard_surface': ShadingVocabulary.standardSurface,
      'UsdPreviewSurface': ShadingVocabulary.previewSurface,
    };

/// The texture slots a program may sample, in the order images take them;
/// the normal map's slot is the normal input's alone.
const List<String> _slots = <String>[
  'base_color_texture',
  'emissive_texture',
  'metallic_roughness_texture',
  'occlusion_texture',
];

final class _MtlxDocument {
  _MtlxDocument(this.root, this.directory, this.report, {required this.bound})
    : prefix = root['fileprefix'] ?? '';

  final XmlElement root;
  final String directory;
  final ConvertReport report;
  final String prefix;

  /// The directory an image the document names has to lie inside (see
  /// `confine.dart`).
  final String bound;

  /// The image file [path] names, or null, said in [report], when it is
  /// outside [bound].
  File? _image(String path) {
    final resolved = resolveInside(path, directory: directory, root: bound);
    if (resolved == null) {
      report.drop(path, outsideMessage(path, bound));
      return null;
    }
    return File(resolved);
  }

  /// Each material's name and its surface shader node.
  List<(String, XmlElement)> materials() {
    final out = <(String, XmlElement)>[];
    final used = <XmlElement>{};
    for (final material in root.all('surfacematerial')) {
      final input = material
          .all('input')
          .where((XmlElement i) => i['name'] == 'surfaceshader')
          .firstOrNull;
      final shader = input == null ? null : _node(root, input['nodename']);
      if (shader == null) {
        report.drop(
          'material "${material['name']}"',
          'it names no surface shader',
        );
        continue;
      }
      used.add(shader);
      out.add((material['name'] ?? 'material', shader));
    }
    // A document of bare shaders, with no material wrapping them.
    for (final element in root.children) {
      if (_vocabularies.containsKey(element.name) && !used.contains(element)) {
        out.add((element['name'] ?? element.name, element));
      }
    }
    for (final element in root.children) {
      if (element.name.endsWith('_surface') &&
          !_vocabularies.containsKey(element.name)) {
        report.drop(
          'shader "${element['name']}" (${element.name})',
          'only standard_surface and UsdPreviewSurface are mapped',
        );
      }
    }
    return out;
  }

  XmlElement? _node(XmlElement scope, String? name) => name == null
      ? null
      : scope.children.where((XmlElement e) => e['name'] == name).firstOrNull;

  MaterialSource convert(String name, XmlElement shader) {
    final id = safeFileName(name);
    final vocabulary = _vocabularies[shader.name];
    if (vocabulary == null) {
      report.drop('material "$name"', '${shader.name} is not mapped');
      return MaterialSource(id, SurfaceMaterial(name: id));
    }
    final inputs = <String, InputValue>{};
    final graphs = <String, _Expr>{};
    for (final input in shader.all('input')) {
      final inputName = input['name'];
      if (inputName == null) continue;
      final expr = _inputExpr(input, root);
      final folded = _fold(expr);
      inputs[inputName] = folded;
      graphs[inputName] = expr;
    }
    if (!inputs.values.any((InputValue v) => v is GraphInput)) {
      return surfaceFromInputs(id, inputs, vocabulary, report);
    }
    final program = _program(id, inputs, graphs, vocabulary);
    // With a program, the parameters are only its companion's: what they
    // fold away the program computes, so their notes would mislead.
    final surface = surfaceFromInputs(
      id,
      inputs,
      vocabulary,
      program == null ? report : ConvertReport(report.input, report.format),
    );
    if (program == null) return surface;
    report.map('material "$name": node graph -> material language program');
    return MaterialSource(
      id,
      _withLighting(surface.surface, id, program.$2, surface.images),
      images: <MaterialImage>[
        ...surface.images,
        for (final image in program.$2)
          if (!surface.images.any((MaterialImage i) => i.name == image.name))
            image,
      ],
      program: program.$1,
    );
  }

  /// [surface] naming the program [id] as its lighting, with each image the
  /// program samples bound in the slot it samples it from.
  SurfaceMaterial _withLighting(
    SurfaceMaterial surface,
    String id,
    List<MaterialImage> slotted,
    List<MaterialImage> existing,
  ) {
    final all = <MaterialImage>[
      ...existing,
      for (final image in slotted)
        if (!existing.any((MaterialImage i) => i.name == image.name)) image,
    ];
    TextureBinding? bindFor(int slot) {
      if (slot >= slotted.length) return null;
      final at = all.indexWhere(
        (MaterialImage i) => i.name == slotted[slot].name,
      );
      return at < 0 ? null : TextureBinding(imageIndex: at);
    }

    final name = _programName(id);
    return SurfaceMaterial(
      name: id,
      baseColor: LinearColor.fromSrgb(1.0, 1.0, 1.0, surface.baseColor.a),
      metallic: surface.metallic,
      roughness: surface.roughness,
      baseColorTexture: bindFor(0),
      emissiveTexture: bindFor(1),
      metallicRoughnessTexture: bindFor(2),
      occlusionTexture: bindFor(3),
      normalTexture: surface.normalTexture,
      alphaMode: surface.alphaMode,
      alphaCutoff: surface.alphaCutoff,
      lightingModel: LightingModel(name, name),
    );
  }

  /// An input as an expression tree.
  _Expr _inputExpr(XmlElement input, XmlElement scope) {
    final type = input['type'] ?? 'float';
    if (input['value'] case final String value) {
      if (type == 'filename') return _Expr.file(_file(value, scope));
      return _Expr.constant(_numbers(value), type);
    }
    if (input['nodegraph'] case final String graphName) {
      final graph = _node(root, graphName);
      if (graph == null) {
        return _Expr.unsupported('a missing nodegraph "$graphName"');
      }
      final outputName = input['output'];
      final output = graph
          .all('output')
          .where(
            (XmlElement o) => outputName == null || o['name'] == outputName,
          )
          .firstOrNull;
      if (output == null) return _Expr.unsupported('a missing output');
      return _outputExpr(output, graph);
    }
    if (input['nodename'] case final String nodeName) {
      final node = _node(scope, nodeName);
      if (node == null) return _Expr.unsupported('a missing node "$nodeName"');
      return _nodeExpr(node, scope, input['output']);
    }
    if (input['interfacename'] != null) {
      return _Expr.unsupported('an interface input');
    }
    return _Expr.constant(const <double>[], type);
  }

  _Expr _outputExpr(XmlElement output, XmlElement graph) {
    final nodeName = output['nodename'];
    final node = nodeName == null ? null : _node(graph, nodeName);
    if (node == null) return _Expr.unsupported('an output with no node');
    return _nodeExpr(node, graph, output['output']);
  }

  _Expr _nodeExpr(XmlElement node, XmlElement scope, String? output) {
    final type = node['type'] ?? 'float';
    final args = <String, _Expr>{
      for (final input in node.all('input'))
        if (input['name'] case final String n) n: _inputExpr(input, scope),
    };
    final kind = node.name;
    if (kind == 'image' || kind == 'tiledimage' || kind == 'gltf_image') {
      final file = args['file'];
      if (file == null || file.kind != 'file') {
        return _Expr.unsupported('an image node with no file');
      }
      return _Expr.image(file.file!, type, args['uvtiling']);
    }
    return _Expr.node(kind, type, args, node['name'] ?? kind);
  }

  String _file(String value, XmlElement scope) {
    final graphPrefix = scope == root ? '' : (scope['fileprefix'] ?? '');
    return '$prefix$graphPrefix$value';
  }

  static List<double> _numbers(String text) => <double>[
    for (final part in text.split(RegExp(r'[,\s]+')))
      if (double.tryParse(part) case final double d) d,
  ];

  /// [expr] as a constant or an image when it is one — an image multiplied
  /// by a constant folds into the factor — and a [GraphInput] otherwise.
  InputValue _fold(_Expr expr) {
    switch (expr.kind) {
      case 'constant':
        return ConstantInput(expr.values);
      case 'image':
        return _texture(expr, null);
      case 'node' when expr.op == 'multiply':
        final a = expr.args['in1'], b = expr.args['in2'];
        if (a != null && b != null) {
          if (a.kind == 'image' && b.kind == 'constant') {
            return _texture(a, b.values);
          }
          if (b.kind == 'image' && a.kind == 'constant') {
            return _texture(b, a.values);
          }
        }
      case 'node' when expr.op == 'extract':
        final source = expr.args['in'];
        final index = expr.args['index']?.values.firstOrNull?.toInt() ?? 0;
        if (source != null && source.kind == 'image') {
          return _texture(source, null, channel: 'rgba'[index.clamp(0, 3)]);
        }
      case 'node' when expr.op == 'dot' || expr.op == 'convert':
        final source = expr.args['in'];
        if (source != null) {
          final inner = _fold(source);
          if (inner is! GraphInput) return inner;
        }
    }
    return GraphInput(
      'a ${expr.describe()} node',
      fallback: _firstImage(expr) == null
          ? null
          : _texture(_firstImage(expr)!, null),
    );
  }

  _Expr? _firstImage(_Expr expr) {
    if (expr.kind == 'image') return expr;
    for (final arg in expr.args.values) {
      final found = _firstImage(arg);
      if (found != null) return found;
    }
    return null;
  }

  TextureInput _texture(_Expr image, List<double>? scale, {String? channel}) {
    final path = image.file!;
    final file = _image(path);
    return TextureInput(
      path.substring(path.lastIndexOf('/') + 1),
      file != null && file.existsSync() ? file.readAsBytesSync() : null,
      channel: channel ?? (image.type == 'float' ? 'r' : 'rgb'),
      scale: scale,
    );
  }

  /// The program for [graphs] — the inputs that are node graphs — with the
  /// images it samples in slot order, or null with the reason reported.
  (String, List<MaterialImage>)? _program(
    String id,
    Map<String, InputValue> inputs,
    Map<String, _Expr> graphs,
    ShadingVocabulary vocabulary,
  ) {
    final images = <String>[];
    final writer = _GlslWriter(images);
    String term(String? name, String fallback, String glslType) {
      if (name == null) return fallback;
      final expr = graphs[name];
      if (expr == null) return fallback;
      if (expr.kind == 'constant') {
        return expr.values.isEmpty
            ? fallback
            : _GlslWriter.literal(expr.values, glslType);
      }
      return writer.write(expr, glslType);
    }

    final String base, emission, opacity, rough, metal;
    try {
      final weight = term(vocabulary.baseWeight, '1.0', 'float');
      base =
          '(${term(vocabulary.baseColor, 'vec3(0.8, 0.8, 0.8)', 'vec3')}) * ($weight)';
      final emissionWeight = term(vocabulary.emissiveWeight, '1.0', 'float');
      emission =
          '(${term(vocabulary.emissive, 'vec3(0.0, 0.0, 0.0)', 'vec3')}) * ($emissionWeight)';
      // standard_surface's opacity is a colour; the engine's is one number,
      // the mean of the three.
      final colourOpacity = vocabulary == ShadingVocabulary.standardSurface;
      final opacityTerm = term(
        vocabulary.opacity,
        colourOpacity ? 'vec3(1.0, 1.0, 1.0)' : '1.0',
        colourOpacity ? 'vec3' : 'float',
      );
      opacity = colourOpacity
          ? 'dot($opacityTerm, vec3(0.3333, 0.3333, 0.3334))'
          : opacityTerm;
      rough = term(vocabulary.roughness, '0.5', 'float');
      metal = term(vocabulary.metallic, '0.0', 'float');
    } on _Unsupported catch (error) {
      report.warn(
        'material "$id": ${error.what} has no counterpart in the material '
        'language, so the material is the nearest metal-rough surface',
      );
      return null;
    }
    if (images.length > _slots.length) {
      report.warn(
        'material "$id" samples ${images.length} images and a program may '
        'sample ${_slots.length}; the nearest metal-rough surface is written',
      );
      return null;
    }
    final name = _programName(id);
    final source = StringBuffer()
      ..writeln('f3dmat 1')
      ..writeln('// Written by flutter3d convert from a MaterialX node graph.')
      ..writeln('// The diffuse and the highlight are computed here from the')
      ..writeln('// graph; the highlight is a normalised Blinn-Phong lobe, an')
      ..writeln("// approximation of the engine's own metal-rough response.")
      ..writeln('material $name {');
    for (var i = 0; i < images.length; i++) {
      source.writeln('  texture tex$i = ${_slots[i]};');
    }
    source
      ..writeln('  light {')
      ..writeln('    let baseColor = $base;')
      ..writeln('    let metal = clamp($metal, 0.0, 1.0);')
      ..writeln('    let rough = clamp($rough, 0.04, 1.0);')
      ..writeln(
        '    let shininess = 2.0 / max(rough * rough * rough * rough, 0.0001) - 2.0;',
      )
      ..writeln(
        '    let lobe = pow(max(nDotH, 0.0), shininess) * (shininess + 8.0) / 25.1327;',
      )
      ..writeln('    let f0 = mix(vec3(0.04, 0.04, 0.04), baseColor, metal);')
      ..writeln('    return baseColor * (1.0 - metal) / 3.14159 + f0 * lobe;')
      ..writeln('  }')
      ..writeln('  fragment {')
      ..writeln('    return vec4(lit + $emission, clamp($opacity, 0.0, 1.0));')
      ..writeln('  }')
      ..writeln('}');
    final text = source.toString();
    try {
      parseMaterial(text);
    } on MaterialSyntaxException catch (error) {
      report.warn(
        'material "$id": the program written for its graph does not read '
        'back ($error), so the nearest metal-rough surface is written',
      );
      return null;
    }
    return (
      text,
      <MaterialImage>[
        for (final path in images)
          () {
            final file = _image(path);
            return MaterialImage(
              path.substring(path.lastIndexOf('/') + 1),
              file != null && file.existsSync()
                  ? file.readAsBytesSync()
                  : Uint8List(0),
            );
          }(),
      ],
    );
  }
}

/// The material language name for [id]: a capitalised identifier.
String _programName(String id) {
  final parts = id
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((String p) => p.isNotEmpty);
  final joined = parts
      .map((String p) => '${p[0].toUpperCase()}${p.substring(1)}')
      .join();
  if (joined.isEmpty) return 'Converted';
  return RegExp(r'^[0-9]').hasMatch(joined) ? 'M$joined' : joined;
}

/// A node, constant or image of a MaterialX graph.
final class _Expr {
  _Expr.constant(this.values, this.type)
    : kind = 'constant',
      op = '',
      args = const <String, _Expr>{},
      file = null,
      label = '';

  _Expr.file(String this.file)
    : kind = 'file',
      type = 'filename',
      op = '',
      values = const <double>[],
      args = const <String, _Expr>{},
      label = '';

  _Expr.image(String this.file, this.type, _Expr? tiling)
    : kind = 'image',
      op = '',
      values = const <double>[],
      args = <String, _Expr>{'uvtiling': ?tiling},
      label = '';

  _Expr.node(this.op, this.type, this.args, this.label)
    : kind = 'node',
      values = const <double>[],
      file = null;

  _Expr.unsupported(this.label)
    : kind = 'unsupported',
      type = 'float',
      op = '',
      values = const <double>[],
      args = const <String, _Expr>{},
      file = null;

  final String kind;
  final String type;
  final String op;
  final List<double> values;
  final Map<String, _Expr> args;
  final String? file;
  final String label;

  String describe() => kind == 'node' ? '$op ("$label")' : label;
}

final class _Unsupported implements Exception {
  const _Unsupported(this.what);

  final String what;
}

/// Writes a graph as a material language expression.
final class _GlslWriter {
  _GlslWriter(this.images);

  /// The image files sampled so far, in slot order.
  final List<String> images;

  static String glslTypeOf(String mtlxType) => switch (mtlxType) {
    'float' || 'integer' || 'boolean' => 'float',
    'vector2' => 'vec2',
    'color3' || 'vector3' => 'vec3',
    'color4' || 'vector4' => 'vec4',
    _ => 'float',
  };

  static String _f(double v) {
    final text = v.toString();
    return text.contains('.') || text.contains('e') ? text : '$text.0';
  }

  /// [values] as a literal of [glslType].
  static String literal(List<double> values, String glslType) {
    final n = switch (glslType) {
      'vec2' => 2,
      'vec3' => 3,
      'vec4' => 4,
      _ => 1,
    };
    final v = <double>[
      for (var i = 0; i < n; i++)
        i < values.length ? values[i] : (values.isEmpty ? 0.0 : values.last),
    ];
    return n == 1 ? _f(v[0]) : '$glslType(${v.map(_f).join(', ')})';
  }

  /// [expr] as an expression of [glslType], converting at the end.
  String write(_Expr expr, String glslType) =>
      _convert(_write(expr), glslTypeOf(expr.type), glslType);

  static String _convert(String text, String from, String to) {
    if (from == to) return text;
    if (from == 'float') {
      return '$to($text, ${List.filled(int.parse(to.substring(3)) - 1, text).join(', ')})';
    }
    if (to == 'float') return '($text).x';
    if (from == 'vec4' && to == 'vec3') return '($text).xyz';
    if (from == 'vec3' && to == 'vec4') return 'vec4($text, 1.0)';
    if (from == 'vec2' && to == 'vec3') return 'vec3($text, 0.0)';
    if (from == 'vec3' && to == 'vec2') return '($text).xy';
    throw _Unsupported('a $from where a $to is wanted');
  }

  String _write(_Expr expr) {
    final type = glslTypeOf(expr.type);
    switch (expr.kind) {
      case 'constant':
        return literal(expr.values, type);
      case 'image':
        final path = expr.file!;
        var slot = images.indexOf(path);
        if (slot < 0) {
          images.add(path);
          slot = images.length - 1;
        }
        final tiling = expr.args['uvtiling'];
        final uv = tiling == null
            ? 'uv'
            : '(uv * ${literal(tiling.values, 'vec2')})';
        final sample = 'sample(tex$slot, $uv)';
        return switch (type) {
          'float' => '$sample.x',
          'vec2' => '$sample.xy',
          'vec3' => '$sample.xyz',
          _ => sample,
        };
      case 'node':
        return _node(expr, type);
      default:
        throw _Unsupported(expr.describe());
    }
  }

  String _arg(_Expr expr, String name, String type, {String? fallback}) {
    final arg = expr.args[name];
    if (arg == null) {
      if (fallback != null) return fallback;
      throw _Unsupported('${expr.describe()} without "$name"');
    }
    return _convert(_write(arg), glslTypeOf(arg.type), type);
  }

  /// The type an argument is read at: the node's own, except a scalar
  /// operand, which GLSL broadcasts.
  String _operandType(_Expr expr, String name, String type) {
    final arg = expr.args[name];
    if (arg != null && glslTypeOf(arg.type) == 'float') return 'float';
    return type;
  }

  /// One component of a vector, read at the vector's own type.
  String _extract(_Expr expr) {
    final source = expr.args['in'];
    if (source == null) throw _Unsupported('${expr.describe()} without "in"');
    final sourceType = glslTypeOf(source.type);
    final text = _write(source);
    if (sourceType == 'float') return text;
    final width = int.parse(sourceType.substring(3));
    final index = (expr.args['index']?.values.firstOrNull ?? 0).toInt();
    return '($text).${'xyzw'[index.clamp(0, width - 1)]}';
  }

  String _node(_Expr expr, String type) {
    String a(String name, {String? fallback, String? as}) => _arg(
      expr,
      name,
      as ?? _operandType(expr, name, type),
      fallback: fallback,
    );
    final zero = literal(const <double>[0.0], type);
    final one = literal(const <double>[1.0], type);
    return switch (expr.op) {
      'constant' => a('value'),
      'dot' => a('in'),
      'convert' => _arg(expr, 'in', type),
      'add' => '(${a('in1', fallback: zero)} + ${a('in2', fallback: zero)})',
      'subtract' =>
        '(${a('in1', fallback: zero)} - ${a('in2', fallback: zero)})',
      'multiply' => '(${a('in1', fallback: one)} * ${a('in2', fallback: one)})',
      'divide' => '(${a('in1', fallback: one)} / ${a('in2', fallback: one)})',
      'mix' =>
        'mix(${a('bg', as: type, fallback: zero)}, ${a('fg', as: type, fallback: zero)}, ${a('mix', fallback: '0.5')})',
      'clamp' =>
        'clamp(${a('in', as: type)}, ${a('low', fallback: '0.0')}, ${a('high', fallback: '1.0')})',
      'power' =>
        'pow(${a('in1', as: type)}, ${a('in2', as: type, fallback: one)})',
      'max' => 'max(${a('in1', as: type)}, ${a('in2', fallback: zero)})',
      'min' => 'min(${a('in1', as: type)}, ${a('in2', fallback: one)})',
      'absval' => 'abs(${a('in', as: type)})',
      'floor' => 'floor(${a('in', as: type)})',
      'sin' => 'sin(${a('in', as: type)})',
      'cos' => 'cos(${a('in', as: type)})',
      'sqrt' => 'sqrt(${a('in', as: type)})',
      'smoothstep' =>
        'smoothstep(${a('low', fallback: '0.0')}, ${a('high', fallback: '1.0')}, ${a('in', as: type)})',
      'invert' => '(${a('amount', fallback: one)} - ${a('in', as: type)})',
      'normalize' => 'normalize(${a('in', as: type)})',
      'dotproduct' =>
        'dot(${_arg(expr, 'in1', 'vec3')}, ${_arg(expr, 'in2', 'vec3')})',
      'texcoord' => _convert('uv', 'vec2', type),
      'position' => _convert('world', 'vec3', type),
      'normal' => _convert('normal', 'vec3', type),
      'combine2' =>
        'vec2(${_arg(expr, 'in1', 'float')}, ${_arg(expr, 'in2', 'float')})',
      'combine3' =>
        'vec3(${_arg(expr, 'in1', 'float')}, ${_arg(expr, 'in2', 'float')}, ${_arg(expr, 'in3', 'float')})',
      'extract' => _extract(expr),
      _ => throw _Unsupported(expr.describe()),
    };
  }
}
