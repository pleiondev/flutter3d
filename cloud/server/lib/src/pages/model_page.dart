/// One model: a still frame that turns into the renderer, its facts, and what
/// its owner can change.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../db/models_repository.dart';
import '../domain/access.dart';
import '../domain/model.dart';
import '../domain/project.dart';
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
    this.ownerProjects = const [],
    this.sourceSha = '',
    this.said,
    this.publishProblems = const {},
    this.publishLicence,
    this.publishCategory,
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

  /// The owner's own projects, for the move form's own select — only ever
  /// non-empty when the caller already checked `canEdit`, the same as
  /// [revisions]: nobody else's page needs to know what projects the owner
  /// keeps.
  final List<ProjectRecord> ownerProjects;

  /// The current source file's own `blobSha256` — `tut-19`'s own
  /// `data-source-sha`. Empty when the model somehow has no source file,
  /// which `viewer.js` never reaches: it only opens the viewer when a person
  /// presses "Open in 3D", and that button only draws once a source exists.
  final String sourceSha;

  final String? said;

  /// Set only when `/m/<id>/publish` refused the form just submitted — the
  /// same `RegisterInvalid` shape `RegisterPage` already re-shows its own
  /// errors with. Keyed `licence`/`category`.
  final Map<String, String> publishProblems;

  /// The licence and category the refused form was submitted with, so the
  /// choice a person just made is still selected when the page comes back
  /// rather than silently reset to the first option.
  final String? publishLicence;
  final String? publishCategory;

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
            if (model.category case final category?)
              span([Component.text(category.label)], classes: 'badge'),
            if (model.licence case final licence? when model.isPublic)
              span([Component.text(licence.spdx)], classes: 'badge'),
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
            // `tut-19`'s own preview capture: whether *this viewer* may edit
            // the model, so the build inside only ever attempts a capture
            // upload where the server's own `canEdit` could possibly accept
            // it — never from a public visitor's browser, who could only
            // ever get a 404 back. UX-only, the same as `CabinetLink`'s own
            // doc comment already says about `id`/`mode`: the server checks
            // `canEdit` again itself, independently, on the actual POST.
            'data-editable': '$editable',
            // The source file's own hash, so a captured picture can be
            // tagged with the exact file it was rendered from — the preview
            // endpoint's own staleness check compares this against what the
            // model's current source is by the time the picture arrives.
            'data-source-sha': sourceSha,
            // The CSRF token this same request already carries for every
            // other form on this page — nothing new is minted, and nothing
            // more sensitive is exposed than what `_DescribeForm`'s own
            // hidden field already would be for the owner. `viewer.js`
            // passes it on the same way as `id`/`editable`, since the
            // upload the capture makes is itself a same-origin POST that
            // needs it, exactly as `scriptIsOurs` already asks of
            // `/api/v1/models/<id>/source`.
            'data-csrf': csrf,
          },
        ),
        div([
          div([
            if (editable) ...[
              _DescribeForm(model: model, csrf: csrf),
              _MoveForm(model: model, csrf: csrf, projects: ownerProjects),
            ] else if (model.description.isNotEmpty)
              p([Component.text(model.description)], classes: 'description')
            else
              p([Component.text('No description.')], classes: 'muted'),
            if (editable)
              model.isPublic
                  ? _UnpublishForm(model: model, csrf: csrf)
                  : _PublishForm(
                      model: model,
                      csrf: csrf,
                      problems: publishProblems,
                      licence: publishLicence,
                      category: publishCategory,
                    ),
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
              if (model.category case final category?) ...[
                dt([Component.text('Category')]),
                dd([Component.text(category.label)]),
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

/// Where the model sits — one of the owner's own projects, or personal.
/// Reads back as a plain 404 on the server side when the choice does not
/// hold up, the same as every other ownership refusal on this page — this
/// select only ever offers projects the owner actually has.
class _MoveForm extends StatelessComponent {
  const _MoveForm({
    required this.model,
    required this.csrf,
    required this.projects,
  });

  final ModelRecord model;
  final String csrf;
  final List<ProjectRecord> projects;

  @override
  Component build(BuildContext context) => PostForm(
    action: '/m/${model.id}/move',
    csrf: csrf,
    children: [
      div([
        label([Component.text('Project')], htmlFor: 'f-project'),
        select(
          [
            option(
              [Component.text('Personal — no project')],
              value: '',
              selected: model.projectId == null,
            ),
            for (final project in projects)
              option(
                [Component.text(project.title)],
                value: '${project.id}',
                selected: project.id == model.projectId,
              ),
          ],
          name: 'project',
          id: 'f-project',
        ),
      ], classes: 'field'),
      div([submit('Move')]),
    ],
  );
}

/// Offered to the owner while the model is private: every [Licence] as a
/// radio button, every [Category] in a select — the same shape
/// `/register`'s own `RegisterInvalid` branch re-shows a rejected form with,
/// not trusting that a value posted back matches either enum.
class _PublishForm extends StatelessComponent {
  const _PublishForm({
    required this.model,
    required this.csrf,
    this.problems = const {},
    this.licence,
    this.category,
  });

  final ModelRecord model;
  final String csrf;
  final Map<String, String> problems;
  final String? licence;
  final String? category;

  @override
  Component build(BuildContext context) => details([
    summary([Component.text('Publish this model')]),
    PostForm(
      action: '/m/${model.id}/publish',
      csrf: csrf,
      children: [
        p([
          Component.text(
            'A published model is public: anybody can find it in the '
            'showcase, see its page and download the file.',
          ),
        ]),
        fieldset([
          legend([Component.text('Licence')]),
          for (final choice in Licence.values)
            label([
              input(
                type: InputType.radio,
                name: 'licence',
                value: choice.spdx,
                checked: (licence ?? Licence.cc0.spdx) == choice.spdx,
                attributes: const {'required': ''},
              ),
              Component.text(' ${choice.label}'),
            ], classes: 'radio-option'),
          if (problems['licence'] case final error?)
            p([Component.text(error)], classes: 'error'),
        ], classes: 'field'),
        div([
          label([Component.text('Category')], htmlFor: 'f-publish-category'),
          select(
            [
              for (final choice in Category.values)
                option(
                  [Component.text(choice.label)],
                  value: choice.column,
                  selected: category == choice.column,
                ),
            ],
            name: 'category',
            id: 'f-publish-category',
            attributes: {
              if (problems['category'] != null) 'aria-invalid': 'true',
            },
          ),
          if (problems['category'] case final error?)
            p([Component.text(error)], classes: 'error'),
        ], classes: 'field'),
        div([submit('Publish')]),
      ],
    ),
  ], classes: 'publish');
}

/// Offered to the owner while the model is public — takes it back to
/// private. The repository's own `unpublish` keeps the licence, the
/// category and `published_at` exactly as they were, so putting a model
/// back up later does not move it to the top of the catalogue or ask the
/// owner to choose a licence again.
class _UnpublishForm extends StatelessComponent {
  const _UnpublishForm({required this.model, required this.csrf});

  final ModelRecord model;
  final String csrf;

  @override
  Component build(BuildContext context) => PostForm(
    action: '/m/${model.id}/unpublish',
    csrf: csrf,
    children: [
      p([
        Component.text(
          'This model is public. Anybody can find it in the showcase.',
        ),
      ]),
      div([submit('Unpublish')]),
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
