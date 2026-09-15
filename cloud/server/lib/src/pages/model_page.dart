/// One model: a still frame that turns into the renderer, its facts, and what
/// its owner can change.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../db/models_repository.dart';
import '../domain/access.dart';
import '../domain/model.dart';
import '../domain/user.dart';
import '../storage/inspect.dart';
import 'format.dart';
import 'forms.dart';
import 'layout.dart';
import 'said.dart';

class ModelPage extends StatelessComponent {
  const ModelPage({
    required this.model,
    required this.viewer,
    required this.csrf,
    required this.viewerAvailable,
    this.revisions = const [],
    this.said,
    super.key,
  });

  final ModelRecord model;
  final User? viewer;
  final String csrf;

  /// Whether the web build of the renderer is deployed. Without it the button
  /// would open a frame with a 404 in it.
  final bool viewerAvailable;

  /// Past saves of the source file, newest first — only ever non-empty when
  /// the caller already checked `canEdit`, since nobody else's page fetches
  /// them.
  final List<RevisionRecord> revisions;

  final String? said;

  @override
  Component build(BuildContext context) {
    final editable = canEdit(model, viewer);
    final suffix = SourceFormat.of(model.sourceFormat)?.suffix ?? '';

    return Page(
      title: model.title,
      description: model.isPublic
          ? (model.description.isNotEmpty
                ? model.description
                : '${model.title}, a 3D model by ${model.ownerName}.')
          : null,
      signedIn: viewer,
      wide: true,
      scripts: const ['viewer.js'],
      children: [
        ?saidNotice(said),
        div([
          h1([Component.text(model.title)]),
          p([
            if (model.isPublic)
              Component.text('by ${model.ownerName}')
            else ...[
              span([Component.text('private')], classes: 'badge'),
              Component.text(' only you can see this model'),
            ],
          ], classes: 'by'),
        ], classes: 'model-head'),
        div(
          [
            if (model.hasPreview)
              img(
                src: '/files/${model.id}/preview',
                alt: '',
                classes: 'preview-image',
              ),
            div([
              if (viewerAvailable)
                button([Component.text('Open in 3D')], type: ButtonType.button)
              else
                p([
                  Component.text('The 3D view is not deployed on this server.'),
                ]),
              p([
                Component.text(
                  'Loads the flutter3d renderer: WebGPU where the browser '
                  'has it, WebGL2 where it does not.',
                ),
              ]),
            ], classes: model.hasPreview ? 'poster has-preview' : 'poster'),
          ],
          classes: 'viewer',
          attributes: {
            'data-viewer': '',
            'data-src': '/files/${model.id}/source?inline',
            'data-name': '${model.slug}$suffix',
            // `tut-19`/`tut-20`'s own cabinet id: `viewer.js` reads this the
            // same way it already reads `data-src`/`data-name`, and passes
            // it on as the iframe's own `id=` so the build inside knows
            // which cabinet entry, if any, a later "Save to cabinet" would
            // write back to.
            'data-id': '${model.id}',
          },
        ),
        div([
          div([
            if (editable)
              _DescribeForm(model: model, csrf: csrf)
            else if (model.description.isNotEmpty)
              p([Component.text(model.description)], classes: 'description')
            else
              p([Component.text('No description.')], classes: 'muted'),
            if (editable) _DeleteForm(model: model, csrf: csrf),
          ]),
          aside([
            dl([
              dt([Component.text('Format')]),
              dd([Component.text(model.sourceFormat)]),
              dt([Component.text('Triangles')]),
              dd([Component.text(groupDigits(model.triangleCount))]),
              dt([Component.text('Size')]),
              dd([Component.text(formatBytes(model.sizeBytes))]),
              dt([Component.text('Uploaded')]),
              dd([Component.text(isoDate(model.createdAt))]),
              if (model.licence case final licence?) ...[
                dt([Component.text('Licence')]),
                dd([
                  a([Component.text(licence.spdx)], href: licence.url),
                ]),
              ],
            ], classes: 'facts'),
            a(
              [Component.text('Download')],
              href: '/files/${model.id}/source',
              classes: 'button quiet',
            ),
          ]),
        ], classes: 'model-grid'),
        if (editable) _RevisionsSection(model: model, revisions: revisions),
      ],
    );
  }
}

class _RevisionsSection extends StatelessComponent {
  const _RevisionsSection({required this.model, required this.revisions});

  final ModelRecord model;
  final List<RevisionRecord> revisions;

  @override
  Component build(BuildContext context) => section([
    h2([Component.text('Revisions')]),
    if (revisions.isEmpty)
      p([
        Component.text(
          'No past saves yet — saving an edit here keeps the file it '
          'replaces as a revision.',
        ),
      ], classes: 'muted')
    else
      ul([
        for (var i = 0; i < revisions.length; i++)
          li([
            _RevisionRow(
              modelId: model.id,
              revision: revisions[i],
              current: i == 0,
            ),
          ]),
      ], classes: 'revisions-list'),
  ], classes: 'revisions');
}

class _RevisionRow extends StatelessComponent {
  const _RevisionRow({
    required this.modelId,
    required this.revision,
    required this.current,
  });

  final int modelId;
  final RevisionRecord revision;
  final bool current;

  @override
  Component build(BuildContext context) => a([
    span([
      Component.text(isoDate(revision.createdAt)),
      if (current) span([Component.text('current')], classes: 'badge public'),
    ], classes: 'when'),
    span([Component.text(formatBytes(revision.bytes))], classes: 'bytes'),
  ], href: '/files/$modelId/revisions/${revision.id}');
}

class _DescribeForm extends StatelessComponent {
  const _DescribeForm({required this.model, required this.csrf});

  final ModelRecord model;
  final String csrf;

  @override
  Component build(BuildContext context) => PostForm(
    action: '/m/${model.id}/describe',
    csrf: csrf,
    children: [
      Field(label: 'Title', name: 'title', value: model.title, maxLength: 80),
      div([
        label([Component.text('Description')], htmlFor: 'f-description'),
        textarea(
          [Component.text(model.description)],
          name: 'description',
          id: 'f-description',
          rows: 5,
        ),
        p([
          Component.text(
            'What it is, how it was made, anything somebody opening it '
            'would want to know.',
          ),
        ], classes: 'hint'),
      ], classes: 'field'),
      div([submit('Save')]),
    ],
  );
}

class _DeleteForm extends StatelessComponent {
  const _DeleteForm({required this.model, required this.csrf});

  final ModelRecord model;
  final String csrf;

  @override
  Component build(BuildContext context) => details([
    summary([Component.text('Delete this model')]),
    PostForm(
      action: '/m/${model.id}/delete',
      csrf: csrf,
      children: [
        p([
          Component.text(
            'The file is removed at once, and this address stops working.',
          ),
        ]),
        div([submit('Delete model', classes: 'danger')]),
      ],
    ),
  ], classes: 'danger');
}
