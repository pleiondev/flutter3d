/// The cabinet: what somebody keeps here, and the place to add more.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../domain/access.dart';
import '../domain/model.dart';
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
    required this.uploadLimitBytes,
    this.said,
    super.key,
  });

  final User user;
  final String csrf;
  final List<ModelRecord> models;
  final int uploadLimitBytes;
  final String? said;

  @override
  Component build(BuildContext context) {
    final uploads = canUpload(user);
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
        if (models.isEmpty)
          p([
            Component.text(
              uploads
                  ? 'Nothing here yet. Drop a model above to keep it.'
                  : 'Nothing here yet.',
            ),
          ], classes: 'empty')
        else
          ul([
            for (final model in models) li([_Card(model: model)]),
          ], classes: 'cards'),
      ],
    );
  }
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

class _Card extends StatelessComponent {
  const _Card({required this.model});

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
      ], classes: 'body'),
    ],
    href: model.path,
    classes: 'card',
  );
}
