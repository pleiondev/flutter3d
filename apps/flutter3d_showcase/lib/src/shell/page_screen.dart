/// One capability: its header, and the demo, the guide and the source.
///
/// **One capability to a page, always.** The header says what it is and when it
/// arrived, and the three tabs are the three ways to meet it: run it, follow
/// the steps that build it, read the file that runs.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_showcase/src/catalog/feature.dart';
import 'package:flutter3d_showcase/src/catalog/routes.dart';
import 'package:flutter3d_showcase/src/demo/capability_report.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/demo_stage.dart';
import 'package:flutter3d_showcase/src/demo/device_holder.dart';
import 'package:flutter3d_showcase/src/docs/guide_loader.dart';
import 'package:flutter3d_showcase/src/docs/source_view.dart';
import 'package:flutter3d_showcase/src/docs/tutorial_view.dart';
import 'package:flutter3d_showcase/src/registry/registry.dart';
import 'package:flutter3d_showcase/src/shell/chips.dart';
import 'package:url_launcher/url_launcher.dart';

class PageScreen extends StatefulWidget {
  const PageScreen({super.key, required this.feature, required this.route});

  final Feature feature;
  final PageAddress route;

  @override
  State<PageScreen> createState() => _PageScreenState();
}

class _PageScreenState extends State<PageScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: PageTab.values.length,
    vsync: this,
    initialIndex: widget.route.tab.index,
  )..addListener(_onTab);

  final ValueNotifier<List<String>> _declined = ValueNotifier<List<String>>(
    const <String>[],
  );
  Future<Guide>? _guide;
  String? _deviceNotice;

  @override
  void initState() {
    super.initState();
    _findDeviceNotice(DeviceScope.of(context));
  }

  Future<void> _findDeviceNotice(DeviceHolder holder) async {
    final device = await holder.device;
    final String? sentence = CapabilityReport.of(
      device,
    ).sentenceFor(widget.feature.needs);
    if (mounted && sentence != null) setState(() => _deviceNotice = sentence);
  }

  /// Puts the tab in the address without building the page again, so the demo
  /// keeps running and a link to the tab you are on can be copied.
  void _onTab() {
    if (_tabs.indexIsChanging) return;
    final PageAddress route = PageAddress(
      widget.feature.id,
      tab: PageTab.values[_tabs.index],
    );
    SystemNavigator.routeInformationUpdated(
      uri: Uri.parse(route.address),
      replace: true,
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    _declined.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Feature feature = widget.feature;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(feature.title, style: text.headlineSmall),
              VersionChip(feature),
              TextButton.icon(
                icon: const Icon(Icons.menu_book, size: 16),
                label: const Text('Guide on the docs site'),
                onPressed: () => launchUrl(guideOf(feature)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(feature.summary, style: text.bodyMedium),
        ),
        ValueListenableBuilder<List<String>>(
          valueListenable: _declined,
          builder: (BuildContext context, List<String> declined, Widget? _) =>
              BackendNotice(
                lines: <String>[
                  ?_deviceNotice,
                  if (declined.isNotEmpty)
                    'This backend declined: ${declined.join(', ')}.',
                ],
              ),
        ),
        TabBar(
          controller: _tabs,
          tabs: <Widget>[
            for (final PageTab tab in PageTab.values) Tab(text: tab.title),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              _demo(feature),
              _steps(feature),
              _source(feature),
            ],
          ),
        ),
      ],
    );
  }

  Widget _demo(Feature feature) {
    final DemoBuilder? build = kDemos[feature.id];
    if (build == null) {
      return Center(child: Text('${feature.title} has no demo yet.'));
    }
    return DemoStage(build: build, declined: _declined);
  }

  Future<Guide> _load() =>
      _guide ??= loadGuide(DefaultAssetBundle.of(context), widget.feature);

  Widget _steps(Feature feature) => FutureBuilder<Guide>(
    future: _load(),
    builder: (BuildContext context, AsyncSnapshot<Guide> snapshot) {
      final Guide? guide = snapshot.data;
      if (snapshot.hasError) {
        return Center(child: Text('The guide did not load: ${snapshot.error}'));
      }
      if (guide == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return TutorialView(
        markdown: guide.markdown,
        pageSource: guide.pageSource,
        sourceOf: guide.sourceOf,
      );
    },
  );

  Widget _source(Feature feature) => FutureBuilder<Guide>(
    future: _load(),
    builder: (BuildContext context, AsyncSnapshot<Guide> snapshot) {
      final Guide? guide = snapshot.data;
      if (snapshot.hasError) {
        return Center(
          child: Text('The source did not load: ${snapshot.error}'),
        );
      }
      if (guide == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return SourceView(feature: feature, source: guide.pageSource);
    },
  );
}
