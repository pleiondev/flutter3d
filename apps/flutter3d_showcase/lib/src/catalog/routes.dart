/// Addresses inside the app, and what to do with them.
///
/// **A page's address is `/p/<id>?tab=steps&step=2`.** With the browser's
/// default hash strategy that is `…/showcase/#/p/<id>?tab=steps&step=2`, which
/// a static server delivers as the one `index.html` with nothing to rewrite.
/// The same strings are what `Navigator` is given on macOS, where there is no
/// address bar, so one router serves both. No Flutter import: the tests and the
/// site's generator both read addresses.
library;

/// The three tabs of a page, in the order the tab bar shows them.
enum PageTab {
  /// The running scene with its controls; the tab an address without `tab=`
  /// opens.
  demo('demo', 'Demo'),

  /// The guide, the page's Markdown with its quoted regions of source.
  steps('steps', 'Step by step'),

  /// The page's demo file, whole.
  source('source', 'Source');

  const PageTab(this.key, this.title);

  /// The value of `tab=` in an address.
  final String key;

  /// The label on the tab.
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

/// The home page, `/`, and where an address nothing matches lands.
final class HomeAddress extends ShowcaseAddress {
  /// The home page; it has nothing to carry.
  const HomeAddress();

  @override
  String get address => '/';
}

/// One page's tab, `/p/<id>?tab=steps&step=2`.
final class PageAddress extends ShowcaseAddress {
  /// The page [id] on [tab], its demo unless said; [step] is meant for
  /// [PageTab.steps] and left out of the address when null.
  const PageAddress(this.id, {this.tab = PageTab.demo, this.step});

  /// The page's `Feature.id`. Not checked here: an id the catalog does not
  /// have is the shell's to turn away.
  final String id;

  /// Which of the page's tabs is open.
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

  /// The same page on [next]; the step is dropped, since it belongs to the
  /// guide and not to whatever tab comes next.
  PageAddress onTab(PageTab next) => PageAddress(id, tab: next);
}
