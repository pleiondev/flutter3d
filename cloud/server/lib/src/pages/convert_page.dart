/// `/convert`: a source file in, the engine's formats out, and the
/// converter's own account of what it carried over and what it left behind.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../convert/conversion_store.dart';
import '../convert/converter.dart';
import '../convert/exporter.dart';
import '../domain/access.dart';
import '../domain/model.dart' show formatBytes;
import '../domain/user.dart';
import 'download_as.dart';
import 'forms.dart';
import 'layout.dart';

/// What the file picker suggests. Not a rule: the server reads what the
/// bytes are, and a `.zip` of a folder is the usual way in for a scene.
const _accepted =
    '.zip,.gltf,.glb,.obj,.stl,.ply,.usda,.usd,.usdz,.mtlx,.prefab,'
    '.unity,.mat,.tscn,.tres';

/// The form: one file or a `.zip` of a folder, and what to get out of it.
class ConvertPage extends StatelessComponent {
  const ConvertPage({
    required this.signedIn,
    required this.csrf,
    required this.uploadLimitBytes,
    this.error,
    super.key,
  });

  final User? signedIn;
  final String csrf;
  final int uploadLimitBytes;

  /// Shown above the form when a result asked for has gone.
  final String? error;

  @override
  Component build(BuildContext context) {
    final user = signedIn;
    final allowed = canUpload(user);
    return Page(
      title: 'Convert',
      description:
          'Convert glTF, OBJ, STL, PLY, USD, MaterialX, Unity and Godot '
          'files into flutter3d models, materials and levels.',
      signedIn: user,
      scripts: [if (allowed) 'convert.js'],
      children: [
        h1([Component.text('Convert a model, a material or a scene')]),
        p([
          Component.text(
            'Send one file, or a .zip of the folder a scene lives in, and get '
            'back what the engine loads. A model is one .f3d per file you '
            'sent, with its materials, its .f3dmat programs and a scene\'s '
            'prefabs inside it. Ask for a material or a level instead and '
            'they come as files of their own: .fmat and .f3dmat materials, '
            'their textures, and level documents with their prefabs. The '
            'converter says what it carried over, what it approximated and '
            'what it had to leave behind.',
          ),
        ], classes: 'lead'),
        if (error case final message?) Notice(message, kind: 'error'),
        if (user == null)
          Notice(
            'Converting needs an account with a confirmed address. ',
            children: [
              a([Component.text('Sign in')], href: '/login?next=/convert'),
              Component.text(' or '),
              a([Component.text('create one')], href: '/register'),
              Component.text('.'),
            ],
          )
        else if (!allowed)
          const Notice(
            'Confirm your address to start converting — the confirmation '
            'letter has a link in it. My models can send it again.',
          )
        else
          _ConvertForm(csrf: csrf, limit: uploadLimitBytes),
        const _WhatGoesIn(),
      ],
    );
  }
}

class _ConvertForm extends StatelessComponent {
  const _ConvertForm({required this.csrf, required this.limit});

  final String csrf;
  final int limit;

  @override
  Component build(BuildContext context) => form(
    [
      div([
        label([Component.text('File')], htmlFor: 'convert-file'),
        input(
          type: InputType.file,
          id: 'convert-file',
          name: 'file',
          attributes: const {'accept': _accepted, 'required': ''},
        ),
        p([
          Component.text(
            'One file, or a .zip of a Unity, Godot or USD folder with the '
            'files it refers to. Up to ${formatBytes(limit)}.',
          ),
        ], classes: 'hint'),
      ], classes: 'field'),
      div([
        label([Component.text('Convert to')], htmlFor: 'convert-target'),
        select(
          [
            for (final target in ConversionTarget.values)
              option(
                [Component.text(target.label)],
                value: target.column,
                selected: target == ConversionTarget.model,
              ),
          ],
          id: 'convert-target',
          name: 'target',
        ),
      ], classes: 'field'),
      div([submit('Convert')]),
      p(
        const [],
        attributes: const {'data-convert-status': '', 'aria-live': 'polite'},
      ),
    ],
    classes: 'stack convert',
    attributes: {'data-convert': '', 'data-limit': '$limit', 'data-csrf': csrf},
  );
}

class _WhatGoesIn extends StatelessComponent {
  const _WhatGoesIn();

  @override
  Component build(BuildContext context) => section([
    h2([Component.text('What it reads')]),
    ul([
      li([
        Component.text('glTF and GLB, OBJ with its MTL, STL, PLY → a model'),
      ]),
      li([
        Component.text(
          'USDA and USDZ → a model, its materials and a level with prefabs',
        ),
      ]),
      li([Component.text('MaterialX .mtlx → a material, or a material graph')]),
      li([
        Component.text(
          'Unity .prefab and .unity → a level with prefabs, its models and '
          'materials; a Unity .mat → a material',
        ),
      ]),
      li([
        Component.text(
          'Godot .tscn → a level with prefabs; a Godot .tres material → a '
          'material',
        ),
      ]),
    ]),
    h2([Component.text('What it does not')]),
    p([
      Component.text(
        'FBX, .blend and binary USD (.usdc) are read by outside programs on '
        'a desktop — FBX2glTF, Blender, usdcat — and this server runs none, '
        'so it says so and converts the rest. Export glTF or USDA, or run '
        'flutter3d convert on your own machine.',
      ),
    ]),
    h2([Component.text('What happens to the file')]),
    p([
      Component.text(
        'The upload is converted and dropped — unless it is a .glb, .gltf '
        'or .obj model, which waits beside the result so that keeping the '
        'model keeps your file rather than the .f3d. The result is kept for '
        'an hour, for you alone, so you can download it or keep a model in '
        'My models; then it is deleted. Nobody else can see either. A '
        'conversion that runs past two minutes is stopped, and a .zip that '
        'unpacks to more than 512 MB is not unpacked.',
      ),
    ], classes: 'muted'),
  ], classes: 'prose');
}

/// A finished conversion: what came out, and the converter's report.
class ConversionResultPage extends StatelessComponent {
  const ConversionResultPage({
    required this.user,
    required this.csrf,
    required this.held,
    required this.uploadLimitBytes,
    super.key,
  });

  final User user;
  final String csrf;
  final HeldConversion held;
  final int uploadLimitBytes;

  @override
  Component build(BuildContext context) {
    final failed = held.reports.where((r) => !r.converted).length;
    return Page(
      title: 'Converted ${held.sourceName}',
      signedIn: user,
      wide: true,
      children: [
        div([
          h1([Component.text(held.sourceName)]),
          p([
            Component.text(
              '${held.target.label} · kept until '
              '${_clockTime(held.expiresAt)} UTC, visible only to you',
            ),
          ], classes: 'muted'),
        ], classes: 'model-head'),
        if (held.files.isEmpty)
          Notice(
            held.notOffered.isEmpty
                ? 'Nothing came out of this conversion. The report below says '
                      'why.'
                : 'Nothing of the kind asked for came out, but the conversion '
                      'did write ${_kinds(held.notOffered)}. Convert again and '
                      'choose that.',
            kind: 'error',
          )
        else
          section([
            h2([Component.text('Files')]),
            ul([
              for (final file in held.files)
                li([
                  _FileRow(
                    held: held,
                    file: file,
                    csrf: csrf,
                    uploadLimitBytes: uploadLimitBytes,
                  ),
                ]),
            ], classes: 'convert-files'),
            if (held.hasArchive)
              div([
                a(
                  [Component.text('Download all as .zip')],
                  href: '${held.path}/all.zip',
                  classes: 'button quiet',
                ),
              ], classes: 'row'),
            if (held.notOffered.isNotEmpty)
              p([
                Component.text(
                  'The conversion also wrote ${_kinds(held.notOffered)}, '
                  'which are not part of a ${held.target.column} result.',
                ),
              ], classes: 'muted'),
            if (held.target.bundles && held.files.any((f) => f.isModel))
              p([
                Component.text(
                  'Each .f3d carries its materials, programs and prefabs '
                  'inside it, so it is the whole of what that file became.',
                ),
              ], classes: 'muted'),
            if (held.files.any((f) => f.isModel))
              p([
                Component.text(
                  'Only models can go into My models. Materials and levels '
                  'are downloads.',
                ),
              ], classes: 'muted'),
          ], classes: 'convert-result'),
        section([
          h2([
            Component.text(
              failed == 0
                  ? 'Report'
                  : 'Report — ${failed == 1 ? 'one input' : '$failed inputs'} '
                        'did not convert',
            ),
          ]),
          for (final report in held.reports) _ReportBlock(report: report),
        ], classes: 'convert-report'),
        div([
          a(
            [Component.text('Convert another file')],
            href: '/convert',
            classes: 'button',
          ),
        ], classes: 'row'),
      ],
    );
  }
}

class _FileRow extends StatelessComponent {
  const _FileRow({
    required this.held,
    required this.file,
    required this.csrf,
    required this.uploadLimitBytes,
  });

  final HeldConversion held;
  final HeldFile file;
  final String csrf;
  final int uploadLimitBytes;

  @override
  Component build(BuildContext context) {
    final original = held.savesOriginalFor(file) ? held.original : null;
    final keptSize = original?.sizeBytes ?? file.sizeBytes;
    final path = Uri.encodeQueryComponent(file.path);
    return div([
      a([Component.text(file.path)], href: '${held.path}/file?path=$path'),
      span([Component.text(formatBytes(file.sizeBytes))], classes: 'muted'),
      if (file.isModel)
        if (keptSize <= uploadLimitBytes)
          PostForm(
            action: '${held.path}/save',
            csrf: csrf,
            classes: 'inline',
            children: [
              input(type: InputType.hidden, name: 'file', value: file.path),
              submit('Save to my models', classes: 'quiet'),
            ],
          )
        else
          span([
            Component.text(
              'larger than ${formatBytes(uploadLimitBytes)}, so download only',
            ),
          ], classes: 'muted'),
      if (file.isModel)
        p([Component.text(_whatIsSaved(file, original))], classes: 'hint'),
      if (file.isModel)
        DownloadAsMenu(
          formats: [
            for (final format in ExportFormat.values)
              if (format != ExportFormat.original) format,
          ],
          hrefOf: (format) => '${held.path}/as/${format.column}?path=$path',
        ),
    ], classes: 'convert-file');
  }
}

/// The line under a model's "Save to my models": which file the button
/// keeps.
String _whatIsSaved(HeldFile file, HeldOriginal? original) =>
    switch (original) {
      null => 'Save to my models keeps ${file.fileName}, the converted model.',
      HeldOriginal(:final fileName, asUploaded: true) =>
        'Save to my models keeps your $fileName as you sent it, not the '
            '.f3d, so nothing the .f3d leaves out is lost. The .f3d stays a '
            'download.',
      HeldOriginal(:final fileName, :final writtenFrom?) =>
        'Save to my models keeps $fileName, a glTF binary written from '
            '$writtenFrom and the files beside it in the .zip: a file that '
            'refers to other files cannot be kept as one file. The .f3d stays '
            'a download.',
      HeldOriginal() => 'Save to my models keeps ${file.fileName}.',
    };

class _ReportBlock extends StatelessComponent {
  const _ReportBlock({required this.report});

  final InputReport report;

  @override
  Component build(BuildContext context) => article([
    h3([
      Component.text(report.input),
      Component.text(' '),
      span([Component.text(report.format)], classes: 'badge'),
      Component.text(' '),
      span([
        Component.text(
          report.neededExternalTool ? 'not available online' : report.outcome,
        ),
      ], classes: report.converted ? 'badge public' : 'badge'),
    ]),
    if (report.error case final error?)
      p([Component.text(error)], classes: 'error'),
    if (report.dropped.isNotEmpty) ...[
      p([Component.text('Left behind')], classes: 'report-head'),
      ul([
        for (final line in report.dropped) li([Component.text(line)]),
      ]),
    ],
    if (report.warnings.isNotEmpty) ...[
      p([Component.text('Approximated')], classes: 'report-head'),
      ul([
        for (final line in report.warnings) li([Component.text(line)]),
      ]),
    ],
    if (report.mapped.isNotEmpty)
      details([
        summary([
          Component.text(
            'Carried over (${report.mapped.length} '
            '${report.mapped.length == 1 ? 'line' : 'lines'})',
          ),
        ]),
        ul([
          for (final line in report.mapped) li([Component.text(line)]),
        ]),
      ]),
  ], classes: 'input-report');
}

/// `14:05`, in UTC.
String _clockTime(DateTime moment) {
  final utc = moment.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(utc.hour)}:${two(utc.minute)}';
}

/// "a level and 3 materials" — what [paths] are, counted by kind.
String _kinds(List<String> paths) {
  int count(bool Function(String) test) =>
      paths.map((name) => name.toLowerCase()).where(test).length;
  final levels = count((name) => name.endsWith('.level.json'));
  final models = count(
    (name) => name.endsWith('.f3d') || name.endsWith('.f3dsplat'),
  );
  final materials = count(
    (name) => name.endsWith('.fmat') || name.endsWith('.f3dmat'),
  );
  final other = paths.length - levels - models - materials;
  String some(int n, String one) => n == 1
      ? 'one $one'
      : '$n ${one == 'other file' ? 'other files' : '${one}s'}';
  final parts = <String>[
    if (levels > 0) some(levels, 'level'),
    if (models > 0) some(models, 'model'),
    if (materials > 0) some(materials, 'material'),
    if (other > 0) some(other, 'other file'),
  ];
  return switch (parts) {
    [] => 'nothing',
    [final only] => only,
    _ => '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}',
  };
}
