/// The tree of pages beside every page, with a search field over it.
///
/// Categories as folders, pages as rows with the version they arrived in. A
/// query replaces the folders with a flat list of what it found, best match
/// first, since somebody who typed a word wants the answer and not the shelf it
/// is on.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_showcase/src/catalog/catalog.dart';
import 'package:flutter3d_showcase/src/catalog/feature.dart';
import 'package:flutter3d_showcase/src/catalog/routes.dart';
import 'package:flutter3d_showcase/src/catalog/search.dart';

class NavTree extends StatefulWidget {
  const NavTree({super.key, required this.current, required this.onOpen});

  final ShowcaseAddress current;

  /// Asked to go to [address]; the shell decides how.
  final void Function(ShowcaseAddress address) onOpen;

  @override
  State<NavTree> createState() => _NavTreeState();
}

class _NavTreeState extends State<NavTree> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String? get _currentId => switch (widget.current) {
    PageAddress(:final id) => id,
    HomeAddress() => null,
  };

  @override
  Widget build(BuildContext context) {
    final String query = _query.text;
    return Column(
      children: <Widget>[
        ListTile(
          title: const Text('flutter3d showcase'),
          subtitle: Text('${kCatalog.length} capabilities'),
          onTap: () => widget.onOpen(const HomeAddress()),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            controller: _query,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search, or a version like 0.7',
              border: OutlineInputBorder(),
            ),
            onChanged: (String _) => setState(() {}),
          ),
        ),
        Expanded(child: query.trim().isEmpty ? _folders() : _results(query)),
      ],
    );
  }

  Widget _row(Feature feature) => ListTile(
    dense: true,
    selected: feature.id == _currentId,
    title: Text(feature.title),
    trailing: Text(feature.since, style: Theme.of(context).textTheme.bodySmall),
    onTap: () => widget.onOpen(PageAddress(feature.id)),
  );

  Widget _results(String query) {
    final List<Feature> found = searchFeatures(query, kCatalog);
    if (found.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Nothing matches.'),
      );
    }
    return ListView(children: <Widget>[for (final Feature f in found) _row(f)]);
  }

  Widget _folders() => ListView(
    children: <Widget>[
      for (final Category category in Category.values)
        if (featuresOf(category).isNotEmpty)
          ExpansionTile(
            initiallyExpanded: featuresOf(
              category,
            ).any((Feature f) => f.id == _currentId),
            title: Text(category.title),
            subtitle: Text('${featuresOf(category).length}'),
            children: <Widget>[
              for (final Feature f in featuresOf(category)) _row(f),
            ],
          ),
    ],
  );
}
