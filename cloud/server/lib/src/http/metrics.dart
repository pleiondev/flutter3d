/// The `/metrics` response, in the text format Prometheus scrapes.
///
/// **A gauge, not a counter.** Every number here can go down — an account can
/// be deleted, a model with it — so none of them carries the `_total` suffix
/// Prometheus reserves for a count that only ever grows. A dashboard asking
/// "how many accounts have ever registered" needs `increase()` over a counter
/// this service does not keep; what it keeps is "how many exist right now",
/// which is what an operator watching disk space actually wants.
library;

import '../db/metrics_repository.dart';

/// One line of help text, one of type, one of the value — the smallest a
/// scrape target can be and still self-describe, which is what lets Grafana's
/// metrics browser list these without a human writing down what they mean.
String renderPrometheusMetrics(MetricsSnapshot snapshot) {
  final lines = <String>[
    for (final metric in _metricsOf(snapshot)) ...[
      '# HELP ${metric.name} ${metric.help}',
      '# TYPE ${metric.name} gauge',
      '${metric.name} ${metric.value}',
    ],
  ];
  // A trailing newline: the exposition format requires it, and curl piped
  // into a file without one leaves the next line's prompt glued to the
  // number.
  return '${lines.join('\n')}\n';
}

class _Metric {
  const _Metric(this.name, this.help, this.value);

  final String name;
  final String help;
  final int value;
}

List<_Metric> _metricsOf(MetricsSnapshot snapshot) => [
  _Metric(
    'flutter3d_models_registered_users',
    'Accounts that exist right now, verified or not.',
    snapshot.registeredUsers,
  ),
  _Metric(
    'flutter3d_models_verified_users',
    'Accounts with a confirmed email address.',
    snapshot.verifiedUsers,
  ),
  _Metric(
    'flutter3d_models_uploaded_models',
    'Models on the service right now, across every account.',
    snapshot.models,
  ),
  _Metric(
    'flutter3d_models_storage_bytes',
    'Bytes held by uploaded files, deduplicated by content hash — what is '
        'actually on disk, not the sum of every upload.',
    snapshot.storageBytes,
  ),
];
