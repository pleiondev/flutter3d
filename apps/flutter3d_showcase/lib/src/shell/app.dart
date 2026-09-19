/// The application: a theme, an address book and the device every page shares.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_showcase/src/catalog/catalog.dart';
import 'package:flutter3d_showcase/src/catalog/feature.dart';
import 'package:flutter3d_showcase/src/catalog/routes.dart';
import 'package:flutter3d_showcase/src/demo/device_holder.dart';
import 'package:flutter3d_showcase/src/shell/home_view.dart';
import 'package:flutter3d_showcase/src/shell/nav_tree.dart';
import 'package:flutter3d_showcase/src/shell/page_screen.dart';

class ShowcaseApp extends StatefulWidget {
  /// [holder] is for a test that brings a device of its own.
  const ShowcaseApp({super.key, this.holder});

  final DeviceHolder? holder;

  @override
  State<ShowcaseApp> createState() => _ShowcaseAppState();
}

class _ShowcaseAppState extends State<ShowcaseApp> {
  late final DeviceHolder _holder = widget.holder ?? DeviceHolder();

  @override
  Widget build(BuildContext context) {
    return DeviceScope(
      holder: _holder,
      child: MaterialApp(
        title: 'flutter3d showcase',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD9542B)),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFD9542B),
            brightness: Brightness.dark,
          ),
        ),
        // The address the browser was opened on arrives here as a name, so
        // a link to a page and a click on it go the same way.
        onGenerateRoute: (RouteSettings settings) => PageRouteBuilder<void>(
          settings: settings,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder:
              (BuildContext _, Animation<double> _, Animation<double> _) =>
                  Shell(address: ShowcaseAddress.parse(settings.name)),
        ),
      ),
    );
  }
}

/// The tree on the left and the page on the right; the tree in a drawer on a
/// narrow screen.
class Shell extends StatelessWidget {
  const Shell({super.key, required this.address});

  final ShowcaseAddress address;

  void _open(BuildContext context, ShowcaseAddress next) {
    Navigator.of(context).pushReplacementNamed(next.address);
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (address) {
      HomeAddress() => HomeView(
        onOpen: (ShowcaseAddress a) => _open(context, a),
      ),
      final PageAddress page => switch (featureNamed(page.id)) {
        final Feature feature => PageScreen(
          // A new key per page so that going from one page to the next
          // starts a new demo instead of reusing the last one's state.
          key: ValueKey<String>(feature.id),
          feature: feature,
          route: page,
        ),
        null => Center(child: Text('There is no page called "${page.id}".')),
      },
    };
    final Widget tree = NavTree(
      current: address,
      onOpen: (ShowcaseAddress a) => _open(context, a),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        if (box.maxWidth >= 900) {
          return Scaffold(
            body: Row(
              children: <Widget>[
                SizedBox(width: 300, child: tree),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('flutter3d showcase')),
          drawer: Drawer(child: SafeArea(child: tree)),
          body: body,
        );
      },
    );
  }
}
