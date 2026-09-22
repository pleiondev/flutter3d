/// One project: its own title and description, the models inside it, and —
/// since only its owner ever reaches this page at all — the forms to rename
/// or delete it, always shown rather than gated behind an `editable` check.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../domain/model.dart';
import '../domain/project.dart';
import '../domain/user.dart';
import 'format.dart';
import 'forms.dart';
import 'layout.dart';
import 'my_models.dart';
import 'said.dart';

class ProjectPage extends StatelessComponent {
  const ProjectPage({
    required this.project,
    required this.viewer,
    required this.csrf,
    required this.models,
    this.said,
    super.key,
  });

  final ProjectRecord project;

  /// Always the project's own owner — nobody else ever reaches this page,
  /// the same "editing something not yours is 404" rule the model page
  /// already follows.
  final User viewer;

  final String csrf;
  final List<ModelRecord> models;
  final String? said;

  @override
  Component build(BuildContext context) => Page(
    title: project.title,
    signedIn: viewer,
    wide: true,
    children: [
      ?saidNotice(said),
      div([
        h1([Component.text(project.title)]),
        p([Component.text(plural(models.length, 'model'))], classes: 'by'),
      ], classes: 'model-head'),
      _DescribeForm(project: project, csrf: csrf),
      if (models.isEmpty)
        p([
          Component.text('No models here yet — move one in from its own page.'),
        ], classes: 'empty')
      else
        ul([
          for (final model in models) li([ModelCard(model: model)]),
        ], classes: 'cards'),
      _DeleteForm(project: project, csrf: csrf),
    ],
  );
}

class _DescribeForm extends StatelessComponent {
  const _DescribeForm({required this.project, required this.csrf});

  final ProjectRecord project;
  final String csrf;

  @override
  Component build(BuildContext context) => PostForm(
    action: '/p/${project.id}/describe',
    csrf: csrf,
    children: [
      Field(label: 'Title', name: 'title', value: project.title, maxLength: 80),
      div([
        label([Component.text('Description')], htmlFor: 'f-description'),
        textarea(
          [Component.text(project.description)],
          name: 'description',
          id: 'f-description',
          rows: 5,
        ),
      ], classes: 'field'),
      div([submit('Save')]),
    ],
  );
}

class _DeleteForm extends StatelessComponent {
  const _DeleteForm({required this.project, required this.csrf});

  final ProjectRecord project;
  final String csrf;

  @override
  Component build(BuildContext context) => details([
    summary([Component.text('Delete this project')]),
    PostForm(
      action: '/p/${project.id}/delete',
      csrf: csrf,
      children: [
        p([
          Component.text(
            'Its models are not deleted — they become personal, same as '
            'moving each one out by hand.',
          ),
        ]),
        div([submit('Delete project', classes: 'danger')]),
      ],
    ),
  ], classes: 'danger');
}
