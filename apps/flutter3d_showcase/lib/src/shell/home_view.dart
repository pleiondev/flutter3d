/// The first page: what this is, and every capability by category.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_showcase/src/catalog/catalog.dart';
import 'package:flutter3d_showcase/src/catalog/feature.dart';
import 'package:flutter3d_showcase/src/catalog/routes.dart';

/// The home page: what the showcase is, and each category's pages as buttons.
class HomeView extends StatelessWidget {
  /// A home view that hands the page a button opens to [onOpen].
  const HomeView({super.key, required this.onOpen});

  /// Called with the address of the page a button opens.
  final void Function(ShowcaseAddress address) onOpen;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Text(
          'The engine, one capability at a time',
          style: text.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Every page is one thing the engine does. It runs live, on this '
          'device, and says which version of the engine it appeared in. The '
          'Step by step tab builds it from nothing and the Source tab is the '
          'file that is running.',
          style: text.bodyLarge,
        ),
        const SizedBox(height: 24),
        for (final Category category in Category.values)
          if (featuresOf(category).isNotEmpty) ...<Widget>[
            Text(category.title, style: text.titleLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final Feature feature in featuresOf(category))
                  ActionChip(
                    label: Text('${feature.title}  ·  ${feature.since}'),
                    onPressed: () => onOpen(PageAddress(feature.id)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
      ],
    );
  }
}
