/// A guide, drawn.
///
/// **From the same file the site is built from.** The guide's Markdown is read
/// through `expandDirectives`, which fills in the code from the page, and then
/// through `parseTutorial`; this widget only turns the blocks into widgets.
/// It draws the subset `lintTutorial` allows and nothing else, which is why it
/// can be small.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter3d_showcase/src/docs/code_text.dart';
import 'package:flutter3d_showcase/src/docs/regions.dart';
import 'package:flutter3d_showcase/src/docs/tutorial.dart';
import 'package:url_launcher/url_launcher.dart';

class TutorialView extends StatelessWidget {
  const TutorialView({
    super.key,
    required this.markdown,
    required this.pageSource,
    this.sourceOf,
  });

  /// The guide as written, with its `{{code …}}` lines still in it.
  final String markdown;

  /// The source of the page the guide belongs to.
  final String pageSource;

  /// The source of another page by id, for `{{code other-id#region}}`.
  final String Function(String id)? sourceOf;

  @override
  Widget build(BuildContext context) {
    final List<Block> blocks = parseTutorial(
      expandDirectives(markdown, own: pageSource, sourceOf: sourceOf),
    );
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          for (final Block block in blocks) _block(context, block),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, Block block) {
    final TextTheme text = Theme.of(context).textTheme;
    return switch (block) {
      Heading(:final level, :final text) => Padding(
        padding: EdgeInsets.only(top: level == 1 ? 0 : 20, bottom: 8),
        child: Text(
          text,
          style: switch (level) {
            1 => Theme.of(context).textTheme.headlineSmall,
            2 => Theme.of(context).textTheme.titleLarge,
            _ => Theme.of(context).textTheme.titleMedium,
          },
        ),
      ),
      Paragraph(:final inlines) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _Inlines(inlines, style: text.bodyLarge),
      ),
      ListBlock(:final ordered, :final items) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 26,
                      child: Text(ordered ? '${i + 1}.' : '•'),
                    ),
                    Expanded(child: _Inlines(items[i], style: text.bodyLarge)),
                  ],
                ),
              ),
          ],
        ),
      ),
      CodeBlock(:final code) => _CodeBox(code),
      Callout(:final kind, :final inlines) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: _Inlines(<Inline>[
          Bold('${kind[0].toUpperCase()}${kind.substring(1)}. '),
          ...inlines,
        ], style: text.bodyMedium),
      ),
      // What these two become depends on where the guide is shown: on the site
      // a link to the live page and a picture; here the page is already open.
      DirectiveBlock() => const SizedBox.shrink(),
    };
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text.rich(
          highlightedSpan(
            code,
            codeStyle(context),
            Theme.of(context).brightness,
          ),
        ),
      ),
    );
  }
}

/// A paragraph's runs, with links that open. Stateful only to own and dispose
/// the tap recognizers a link needs.
class _Inlines extends StatefulWidget {
  const _Inlines(this.inlines, {this.style});

  final List<Inline> inlines;
  final TextStyle? style;

  @override
  State<_Inlines> createState() => _InlinesState();
}

class _InlinesState extends State<_Inlines> {
  final List<TapGestureRecognizer> _taps = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final TapGestureRecognizer tap in _taps) {
      tap.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final TapGestureRecognizer tap in _taps) {
      tap.dispose();
    }
    _taps.clear();
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        style: widget.style,
        children: <InlineSpan>[
          for (final Inline run in widget.inlines)
            switch (run) {
              Plain() => TextSpan(text: run.text),
              Bold() => TextSpan(
                text: run.text,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Italic() => TextSpan(
                text: run.text,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
              CodeSpan() => TextSpan(
                text: run.text,
                style: codeStyle(context).copyWith(
                  fontSize: 13,
                  backgroundColor: colors.surfaceContainerHighest,
                ),
              ),
              Link(:final url) => TextSpan(
                text: run.text,
                style: TextStyle(
                  color: colors.primary,
                  decoration: TextDecoration.underline,
                ),
                recognizer:
                    (TapGestureRecognizer()
                        ..onTap = () => launchUrl(Uri.parse(url)))
                      .._remember(_taps),
              ),
            },
        ],
      ),
    );
  }
}

extension on TapGestureRecognizer {
  /// Adds this to [owner] so the widget that made it can dispose it.
  void _remember(List<TapGestureRecognizer> owner) => owner.add(this);
}
