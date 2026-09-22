/// The list of projects one account keeps — the same cabinet-style listing
/// `MyModelsPage` already gives its models, for the folders they sit in.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../domain/project.dart';
import '../domain/user.dart';
import 'format.dart';
import 'forms.dart';
import 'layout.dart';
import 'said.dart';

class ProjectsPage extends StatelessComponent {
  const ProjectsPage({
    required this.user,
    required this.csrf,
    required this.projects,
    this.said,
    super.key,
  });

  final User user;
  final String csrf;
  final List<ProjectRecord> projects;
  final String? said;

  @override
  Component build(BuildContext context) => Page(
    title: 'My projects',
    signedIn: user,
    wide: true,
    children: [
      ?saidNotice(said),
      div([
        h1([Component.text('My projects')]),
        span([
          Component.text(plural(projects.length, 'project')),
        ], classes: 'count'),
      ], classes: 'page-head'),
      _NewProjectForm(csrf: csrf),
      if (projects.isEmpty)
        p([
          Component.text(
            'Nothing here yet. Start a project above to group models together.',
          ),
        ], classes: 'empty')
      else
        ul([
          for (final project in projects) li([_ProjectCard(project: project)]),
        ], classes: 'cards'),
    ],
  );
}

class _NewProjectForm extends StatelessComponent {
  const _NewProjectForm({required this.csrf});

  final String csrf;

  @override
  Component build(BuildContext context) => PostForm(
    action: '/projects',
    csrf: csrf,
    children: [
      Field(label: 'Title', name: 'title', maxLength: 80),
      div([submit('New project')]),
    ],
  );
}

class _ProjectCard extends StatelessComponent {
  const _ProjectCard({required this.project});

  final ProjectRecord project;

  @override
  Component build(BuildContext context) => a(
    [
      div([Component.text('project')], classes: 'thumb'),
      div([
        h2([Component.text(project.title)]),
        p([
          Component.text(
            project.description.isNotEmpty
                ? project.description
                : 'No description.',
          ),
        ], classes: 'meta'),
      ], classes: 'body'),
    ],
    href: project.path,
    classes: 'card',
  );
}
