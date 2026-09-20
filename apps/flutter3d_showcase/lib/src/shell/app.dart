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
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  ShowcaseAddress _current = const HomeAddress();

  void _open(ShowcaseAddress next) {
    _navigatorKey.currentState!.pushReplacementNamed(next.address);
  }

  @override
  Widget build(BuildContext context) {
    return DeviceScope(
      holder: _holder,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        // Keeps `_current` in step with whatever moved the route — our own
        // `_open`, the browser's back button, or the address a link was
        // opened on — without the tree needing a `BuildContext` under the
        // `Navigator` to ask it.
        navigatorObservers: <NavigatorObserver>[
          _AddressObserver((ShowcaseAddress address) {
            setState(() => _current = address);
          }),
        ],
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
        // a link to a page and a click on it go the same way. Builds only
        // the page itself — the tree lives outside the `Navigator`, in
        // `builder` below, so replacing this route never touches it.
        onGenerateRoute: (RouteSettings settings) => PageRouteBuilder<void>(
          settings: settings,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder:
              (BuildContext _, Animation<double> _, Animation<double> _) =>
                  _PageBody(
                    address: ShowcaseAddress.parse(settings.name),
                    onOpen: _open,
                  ),
        ),
        // Wraps the `Navigator` `MaterialApp` already built rather than
        // being part of any one route, which is what lets it survive a
        // `pushReplacementNamed`: the tree's own scroll position, its
        // search text and which folders are open are state a full route
        // replacement would otherwise tear down and rebuild from nothing,
        // the same way a real page navigation resets a browser's sidebar.
        //
        // Its own `Overlay`, because this now sits above the `Navigator`
        // rather than inside one of its routes — the tree's search field
        // needs one for its text selection handles, and the one `Navigator`
        // carries is no longer an ancestor of anything built here.
        builder: (BuildContext context, Widget? navigator) => Overlay(
          initialEntries: <OverlayEntry>[
            OverlayEntry(
              builder: (BuildContext context) =>
                  Shell(current: _current, onOpen: _open, body: navigator!),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reports the address of whatever route the `Navigator` settles on, so a
/// widget above it — [Shell]'s tree — can stay in step without living
/// inside the routed subtree itself.
class _AddressObserver extends NavigatorObserver {
  _AddressObserver(this._onAddress);

  final ValueChanged<ShowcaseAddress> _onAddress;

  void _report(Route<dynamic>? route) {
    if (route == null) return;
    final ShowcaseAddress address = ShowcaseAddress.parse(route.settings.name);
    // The very first route reports itself from inside the `Navigator`'s own
    // first build, while `_ShowcaseAppState` is still building too — calling
    // `setState` straight from here would be exactly the "during build" call
    // Flutter refuses. A post-frame callback runs once that build has
    // finished, which every other call to this method already runs well
    // after, so one path serves both instead of two.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onAddress(address));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _report(newRoute);
}

/// The one page the current [ShowcaseAddress] names.
class _PageBody extends StatelessWidget {
  const _PageBody({required this.address, required this.onOpen});

  final ShowcaseAddress address;
  final ValueChanged<ShowcaseAddress> onOpen;

  @override
  Widget build(BuildContext context) => switch (address) {
    HomeAddress() => HomeView(onOpen: onOpen),
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
}

/// The tree on the left and the page on the right; the tree in a drawer on a
/// narrow screen.
class Shell extends StatelessWidget {
  const Shell({
    super.key,
    required this.current,
    required this.onOpen,
    required this.body,
  });

  final ShowcaseAddress current;
  final ValueChanged<ShowcaseAddress> onOpen;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        if (box.maxWidth >= 900) {
          return Scaffold(
            body: Row(
              children: <Widget>[
                SizedBox(
                  width: 300,
                  child: NavTree(current: current, onOpen: onOpen),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('flutter3d showcase')),
          // A `Builder` so closing the drawer can find the `Scaffold` this
          // one belongs to — this widget's own `context` is above it.
          drawer: Drawer(
            child: SafeArea(
              child: Builder(
                builder: (BuildContext drawerContext) => NavTree(
                  current: current,
                  onOpen: (ShowcaseAddress next) {
                    Scaffold.of(drawerContext).closeDrawer();
                    onOpen(next);
                  },
                ),
              ),
            ),
          ),
          body: body,
        );
      },
    );
  }
}
