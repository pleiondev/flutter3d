/// The sandbox question, answered where there is no sandbox to ask about.
///
/// A browser's storage rules are a different subject with different words —
/// origins, quotas and a picker that hands over bytes — and answering the
/// macOS question here with a plausible-looking table would put a number in a
/// document that means nothing. So it says what it is instead.
library;

import 'sandbox_probe_io.dart' show ProbeLine;

export 'sandbox_probe_io.dart' show ProbeLine, describeProbe;

Future<List<ProbeLine>> probeSandbox() async => <ProbeLine>[
  (
    what: 'the macOS sandbox',
    worked: false,
    said: 'not a question a browser has; see p0-08 for the web half',
  ),
];
