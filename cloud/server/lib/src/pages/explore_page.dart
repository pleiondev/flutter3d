/// The showcase: every published model, searchable and filterable by
/// category — the one catalogue page nobody needs an account to open.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../domain/model.dart';
import '../domain/user.dart';
import 'format.dart';
import 'forms.dart';
import 'layout.dart';

class ExplorePage extends StatelessComponent {
  const ExplorePage({
    required this.models,
    this.signedIn,
    this.query,
    this.category,
    this.hasMore = false,
    super.key,
  });

  final List<ModelRecord> models;
  final User? signedIn;

  /// The search box's current text — null when the visitor has not searched,
  /// never the empty string, so a blank search box and "no query at all"
  /// read the same way to [_emptyMessage] and to the hidden field the
  /// category links carry along.
  final String? query;

  /// The category narrowed to, or null for "All".
  final Category? category;

  /// Whether [models] came back at the full page size — the same signal
  /// [ModelsRepository.published] leaves it to the caller to notice, since it
  /// never fetches one extra row just to answer this.
  final bool hasMore;

  @override
  Component build(BuildContext context) => Page(
    title: 'Explore',
    description:
        'Published 3D models — searchable by name, browsable by category.',
    signedIn: signedIn,
    wide: true,
    children: [
      div([
        h1([Component.text('Explore')]),
        span([
          Component.text(plural(models.length, 'model')),
        ], classes: 'count'),
      ], classes: 'page-head'),
      _SearchForm(query: query, category: category),
      _CategoryFilter(query: query, category: category),
      if (models.isEmpty)
        p([Component.text(_emptyMessage(query, category))], classes: 'empty')
      else ...[
        ul([
          for (final model in models) li([_ShowcaseCard(model: model)]),
        ], classes: 'cards'),
        if (hasMore && models.last.publishedAt != null)
          div([
            a(
              [Component.text('More')],
              href: _exploreUrl(
                query: query,
                category: category,
                before: models.last.publishedAt,
              ),
              classes: 'button quiet',
            ),
          ], classes: 'row'),
      ],
    ],
  );
}

String _emptyMessage(String? query, Category? category) {
  final hasQuery = query != null && query.isNotEmpty;
  return switch ((hasQuery, category)) {
    (true, final category?) =>
      'No published models match "$query" in ${category.label}.',
    (true, null) => 'No published models match "$query".',
    (false, final category?) => 'No published models in ${category.label} yet.',
    (false, null) => 'Nothing has been published yet.',
  };
}

/// The path back to `/explore` with [query], [category] and a pagination
/// [before] cursor carried along — every link and form on this page builds
/// its target through this, so none of them can drop a filter the visitor
/// already chose.
String _exploreUrl({String? query, Category? category, DateTime? before}) {
  final params = {
    if (query != null && query.isNotEmpty) 'q': query,
    if (category != null) 'category': category.column,
    if (before != null) 'before': before.toIso8601String(),
  };
  return params.isEmpty
      ? '/explore'
      : '/explore?${Uri(queryParameters: params).query}';
}

/// The search box — a GET form, since a search is a read: bookmarkable and
/// shareable, and a reload never resubmits anything.
class _SearchForm extends StatelessComponent {
  const _SearchForm({this.query, this.category});

  final String? query;
  final Category? category;

  @override
  Component build(BuildContext context) => form(
    [
      label(
        [Component.text('Search')],
        htmlFor: 'explore-q',
        classes: 'sr-only',
      ),
      input(
        type: InputType.search,
        name: 'q',
        value: query,
        id: 'explore-q',
        attributes: const {'placeholder': 'Search published models'},
      ),
      // The category the visitor already chose travels with a new search,
      // the same way [_CategoryFilter]'s own links carry [query] along —
      // changing one filter never silently drops the other.
      if (category != null)
        input(
          type: InputType.hidden,
          name: 'category',
          value: category!.column,
        ),
      submit('Search'),
    ],
    action: '/explore',
    method: FormMethod.get,
    classes: 'search-bar',
  );
}

/// One link per [Category], plus "All" — the same "links, not a select that
/// needs a script to submit itself" shape the task asked for.
class _CategoryFilter extends StatelessComponent {
  const _CategoryFilter({this.query, this.category});

  final String? query;
  final Category? category;

  @override
  Component build(BuildContext context) => nav(
    [
      a(
        [Component.text('All')],
        href: _exploreUrl(query: query),
        classes: category == null ? 'chip active' : 'chip',
      ),
      for (final choice in Category.values)
        a(
          [Component.text(choice.label)],
          href: _exploreUrl(query: query, category: choice),
          classes: category == choice ? 'chip active' : 'chip',
        ),
    ],
    classes: 'category-filter',
    attributes: const {'aria-label': 'Filter by category'},
  );
}

/// A published model as a card in the showcase's own grid — [ModelCard]'s
/// cousin in `my_models.dart`, but showing who made it and what it goes out
/// under rather than a visibility badge only its owner would care about.
class _ShowcaseCard extends StatelessComponent {
  const _ShowcaseCard({required this.model});

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
          Component.text('by ${model.ownerName ?? 'someone'}'),
        ], classes: 'meta'),
        div([
          if (model.licence case final licence?)
            span([Component.text(licence.spdx)], classes: 'badge'),
          if (model.category case final category?)
            span([Component.text(category.label)], classes: 'badge'),
        ], classes: 'badges'),
      ], classes: 'body'),
    ],
    href: model.path,
    classes: 'card',
  );
}
