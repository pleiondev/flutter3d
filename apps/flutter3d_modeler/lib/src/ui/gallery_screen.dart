/// The gallery — `gal-03`.
///
/// **A grid of what somebody can put in a scene, with the licence on the
/// card.** Not in a dialog behind a menu: choosing a prop is browsing, and
/// browsing wants the window. The insert goes through the same import path
/// a dropped file takes, so a lamp from here and a lamp from disk land the
/// same way and undo the same way.
///
/// **The licence chip is on every card, including the free ones.** A chip
/// that only appeared on the awkward items would train people not to read
/// it, and the point is that a person knows what they picked at the moment
/// they pick it rather than at export time.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart' show RecipeCategory;

import '../gallery/gallery_item.dart';
import 'theme.dart';

/// Opens the gallery and answers with whatever was chosen, or null.
Future<GalleryItem?> showGallery(
  BuildContext context, {
  required List<GallerySource> sources,
}) => Navigator.of(context).push<GalleryItem>(
  MaterialPageRoute<GalleryItem>(
    fullscreenDialog: true,
    builder: (BuildContext context) => GalleryScreen(sources: sources),
  ),
);

/// The grid.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.sources});

  final List<GallerySource> sources;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  /// Everything every source answered with.
  List<GalleryItem> _items = const <GalleryItem>[];

  /// The sources that could not answer, by name — a row that says so
  /// rather than a grid that is quietly short.
  final List<String> _unreachable = <String>[];

  bool _loading = true;
  bool _freeOnly = true;
  String _search = '';
  RecipeCategory? _category;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final found = <GalleryItem>[];
    for (final GallerySource source in widget.sources) {
      try {
        for (final GalleryItem item in await source.list()) {
          // A catalogue that offers a malformed item is a catalogue with a
          // bug, and listing it anyway would carry that bug into an
          // export. `gal-01`'s own rule, enforced where items arrive.
          if (refuseItem(item) == null) found.add(item);
        }
      } on Object {
        // One source being down leaves the others usable — the whole of
        // why `GallerySource.list` is allowed to fail at all.
        _unreachable.add(source.name);
      }
    }
    if (!mounted) return;
    setState(() {
      _items = freeFirst(found);
      _loading = false;
    });
  }

  List<GalleryItem> get _shown {
    final String want = _search.trim().toLowerCase();
    return <GalleryItem>[
      for (final GalleryItem item in _items)
        if ((!_freeOnly || item.isFree) &&
            (_category == null || item.category == _category) &&
            (want.isEmpty ||
                item.name.toLowerCase().contains(want) ||
                item.about.toLowerCase().contains(want)))
          item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<GalleryItem> shown = _shown;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 240,
                  child: TextField(
                    key: const ValueKey<String>('gallerySearch'),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search the gallery',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (String it) => setState(() => _search = it),
                  ),
                ),
                ChoiceChip(
                  label: const Text('All'),
                  selected: _category == null,
                  onSelected: (bool _) => setState(() => _category = null),
                ),
                for (final RecipeCategory category in RecipeCategory.values)
                  ChoiceChip(
                    label: Text(category.label),
                    selected: _category == category,
                    onSelected: (bool _) =>
                        setState(() => _category = category),
                  ),
                // **Named for what it does rather than for the licence.**
                // "CC0 only" asks somebody to know what CC0 is before they
                // can decide; "no credit needed" is the thing they
                // actually care about.
                FilterChip(
                  key: const ValueKey<String>('galleryFreeOnly'),
                  label: const Text('No credit needed'),
                  selected: _freeOnly,
                  onSelected: (bool to) => setState(() => _freeOnly = to),
                ),
              ],
            ),
          ),
          if (_unreachable.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.cloud_off_outlined, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_unreachable.join(', ')} could not be reached; '
                      'everything else is still here',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _freeOnly
                            ? 'Nothing here needs no credit. Turn off "No '
                                  'credit needed" to see the rest.'
                            : 'Nothing matches that.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          mainAxisExtent: 128,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: shown.length,
                    itemBuilder: (BuildContext context, int at) =>
                        _Card(item: shown[at]),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One item: what it is, what it is for, and what it costs.
class _Card extends StatelessWidget {
  const _Card({required this.item});

  final GalleryItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey<String>('gallery-${item.id}'),
        onTap: () => Navigator.of(context).pop(item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(item.name, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  item.about,
                  style: theme.textTheme.bodySmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Icon(
                    item.isFree
                        ? Icons.public_outlined
                        : Icons.copyright_outlined,
                    size: 14,
                    color: item.isFree
                        ? theme.colorScheme.primary
                        : theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.licence.name,
                      style: theme.textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (item.author case final String author)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    author,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How tall a gallery card is — kept beside the grid that draws it so the
/// two cannot disagree, the same reason `rowHeightOf` exists.
double galleryCardHeight(BuildContext context) => rowHeightOf(context) * 4;
