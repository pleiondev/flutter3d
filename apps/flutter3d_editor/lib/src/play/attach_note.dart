/// What the attach dialog says about the page it is on.
///
/// **A published editor needs the person's permission to reach a game.** From
/// a public `https` page, Chrome holds a socket to `127.0.0.1` behind its
/// Local Network Access prompt: the socket neither opens nor fails until
/// the person allows the site to reach apps on this device. Checked from
/// `https://example.com` in Chrome 154. A desktop editor, and a page served
/// from this machine, connect at once and are told nothing.
String? attachNote(Uri page, {required bool web}) {
  if (!web || page.scheme != 'https') return null;
  const here = <String>{'localhost', '127.0.0.1', '[::1]', '::1'};
  if (here.contains(page.host)) return null;
  return 'The browser asks first: allow this site to reach apps on this '
      'device when it does, or the connection waits without an answer.';
}
