/// Addresses inside the app, and what to do with them.
///
/// **A page's address is `/p/<id>?tab=steps&step=2`.** With the browser's
/// default hash strategy that is `…/showcase/#/p/<id>?tab=steps&step=2`, which
/// a static server delivers as the one `index.html` with nothing to rewrite.
/// The same strings are what `Navigator` is given on macOS, where there is no
/// address bar, so one router serves both. No Flutter import: the tests and the
/// site's generator both read addresses.
library;

enum PageTab {
  demo('demo', 'Demo'),
  steps('steps', 'Step by step'),
  source('source', 'Source');

  const PageTab(this.key, this.title);

  final String key;
  final String title;
}

/// Where the app is: the home page, or a page's tab.
sealed class ShowcaseAddress {
  const ShowcaseAddress();

  /// [name] as `Navigator` hands it over, or the home route for anything that
  /// is not a page address. A wrong address gets the home page, not a blank
  /// screen: somebody followed a link that has since moved.
  factory ShowcaseAddress.parse(String? name) {
    final Uri uri = Uri.parse(name ?? '/');
    final List<String> parts = uri.pathSegments;
    if (parts.length == 2 && parts.first == 'p' && parts.last.isNotEmpty) {
      return PageAddress(
        parts.last,
        tab: PageTab.values.firstWhere(
          (PageTab tab) => tab.key == uri.queryParameters['tab'],
          orElse: () => PageTab.demo,
        ),
        step: int.tryParse(uri.queryParameters['step'] ?? ''),
      );
    }
    return const HomeAddress();
  }

  /// The address, as [ShowcaseAddress.parse] reads it.
  String get address;
}

final class HomeAddress extends ShowcaseAddress {
  const HomeAddress();

  @override
  String get address => '/';
}

final class PageAddress extends ShowcaseAddress {
  const PageAddress(this.id, {this.tab = PageTab.demo, this.step});

  final String id;
  final PageTab tab;

  /// The step of the guide to scroll to, from 1.
  final int? step;

  @override
  String get address {
    final Map<String, String> query = <String, String>{
      if (tab != PageTab.demo) 'tab': tab.key,
      if (step != null) 'step': '$step',
    };
    return Uri(
      path: '/p/$id',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  PageAddress onTab(PageTab next) => PageAddress(id, tab: next);
}
