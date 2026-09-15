/// The cabinet: what somebody keeps here, and the place to add more.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../domain/access.dart';
import '../domain/model.dart';
import '../domain/project.dart';
import '../domain/user.dart';
import 'format.dart';
import 'forms.dart';
import 'layout.dart';
import 'said.dart';

class MyModelsPage extends StatelessComponent {
  const MyModelsPage({
    required this.user,
    required this.csrf,
    required this.models,
    required this.projects,
    required this.uploadLimitBytes,
    this.said,
    super.key,
  });

  final User user;
  final String csrf;
  final List<ModelRecord> models;

  /// The owner's own projects, most recently changed first — [ofOwner]'s own
  /// order, fetched once alongside [models] and grouped against it in
  /// [build] below rather than with a second query per project.
  final List<ProjectRecord> projects;

  final int uploadLimitBytes;
  final String? said;

  @override
  Component build(BuildContext context) {
    final uploads = canUpload(user);
    final personal = [
      for (final model in models)
        if (model.projectId == null) model,
    ];
    final byProject = <int, List<ModelRecord>>{};
    for (final model in models) {
      if (model.projectId case final projectId?) {
        (byProject[projectId] ??= []).add(model);
      }
    }
    return Page(
      title: 'My models',
      signedIn: user,
      wide: true,
      scripts: [if (uploads) 'upload.js'],
      children: [
        ?saidNotice(said),
        if (!user.emailVerified)
          Notice(
            'Confirm your address to start uploading — the letter went to ${user.email}. ',
            children: [
              PostForm(
                action: '/verify/resend',
                csrf: csrf,
                classes: '',
                children: [submit('Send it again', classes: 'link')],
              ),
            ],
          ),
        div([
          h1([Component.text('My models')]),
          span([
            Component.text(plural(models.length, 'model')),
          ], classes: 'count'),
        ], classes: 'page-head'),
        if (uploads) _UploadZone(csrf: csrf, limit: uploadLimitBytes),
        if (models.isEmpty && projects.isEmpty)
          p([
            Component.text(
              uploads
                  ? 'Nothing here yet. Drop a model above to keep it.'
                  : 'Nothing here yet.',
            ),
          ], classes: 'empty')
        else ...[
          _OwnerSection(
            title: 'Personal',
            models: personal,
            emptyText: 'No personal models yet.',
          ),
          for (final project in projects)
            _OwnerSection(
              title: project.title,
              href: project.path,
              models: byProject[project.id] ?? const [],
              emptyText: 'No models here yet.',
            ),
        ],
      ],
    );
  }
}

/// One group of models on the cabinet — "Personal", or one of the owner's
/// projects. [MyModelsPage] groups its flat [ModelsRepository.ofOwner] list
/// into these in Dart, rather than asking the database once per project.
class _OwnerSection extends StatelessComponent {
  const _OwnerSection({
    required this.title,
    required this.models,
    required this.emptyText,
    this.href,
  });

  final String title;

  /// Where the section title links — a project's own page. Null for
  /// "Personal", which has no page of its own to link to.
  final String? href;

  final List<ModelRecord> models;
  final String emptyText;

  @override
  Component build(BuildContext context) => section([
    h2([
      if (href case final target?)
        a([Component.text(title)], href: target)
      else
        Component.text(title),
    ]),
    if (models.isEmpty)
      p([Component.text(emptyText)], classes: 'muted')
    else
      ul([
        for (final model in models) li([ModelCard(model: model)]),
      ], classes: 'cards'),
  ], classes: 'owner-section');
}

class _UploadZone extends StatelessComponent {
  const _UploadZone({required this.csrf, required this.limit});

  final String csrf;
  final int limit;

  @override
  Component build(BuildContext context) => div(
    [
      p([Component.text('Drop a model here, or')]),
      label(
        [Component.text('Choose a file')],
        htmlFor: 'upload-file',
        classes: 'button',
      ),
      input(
        type: InputType.file,
        id: 'upload-file',
        attributes: const {'accept': '.glb,.gltf,.obj,.f3d,.f3dproj'},
      ),
      p([
        Component.text(
          'glTF — a .glb, or a .gltf with its buffers embedded — OBJ, '
          '.f3d and flutter3d projects, up to ${formatBytes(limit)}. Every file '
          'is read before it is kept, and stays private.',
        ),
      ], classes: 'formats'),
      p(
        const [],
        attributes: const {'data-upload-status': '', 'aria-live': 'polite'},
      ),
    ],
    classes: 'upload',
    attributes: {'data-upload': '', 'data-limit': '$limit', 'data-csrf': csrf},
  );
}

/// A model as a card in a grid of them — what a cabinet's own list shows,
/// and what a project's own page shows for the models inside it, so the two
/// places a model turns up as a thumbnail never drift apart.
class ModelCard extends StatelessComponent {
  const ModelCard({required this.model, super.key});

  final ModelRecord model;

  @override
  Component build(BuildContext context) => a(
    [
      div([
        if (model.hasPreview)
          img(src: '/files/${model.id}/preview', alt: '')
        else
          Component.text(model.sourceFormat),
      ], classes: 'thumb'),
      div([
        h2([Component.text(model.title)]),
        p([
          Component.text(
            '${plural(model.triangleCount, 'triangle')} · ${formatBytes(model.sizeBytes)} ',
          ),
          span([
            Component.text(model.isPublic ? 'public' : 'private'),
          ], classes: model.isPublic ? 'badge public' : 'badge'),
        ], classes: 'meta'),
        if (model.category != null || (model.isPublic && model.licence != null))
          div([
            if (model.category case final category?)
              span([Component.text(category.label)], classes: 'badge'),
            if (model.licence case final licence? when model.isPublic)
              span([Component.text(licence.spdx)], classes: 'badge'),
          ], classes: 'badges'),
      ], classes: 'body'),
    ],
    href: model.path,
    classes: 'card',
  );
}
