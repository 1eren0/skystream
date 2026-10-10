import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;

import '../../../core/domain/entity/multimedia_item.dart';
import 'search_result_filter.dart';

/// Maximum number of outstanding plugin searches. This limits peak socket,
/// cancellation-token and JS callback pressure, *not* total results.
///
/// Android/iOS retain the existing 4..8 budget. Desktop formerly started 32
/// providers at once regardless of the machine's CPU count. Scale with cores
/// there, but never exceed 16; provider order and cancellation are unchanged.
int searchConcurrencyLimit({
  required int logicalProcessors,
  required bool desktop,
  required int providerCount,
}) {
  if (providerCount <= 0) {
    return 0;
  }
  final processors = math.max(1, logicalProcessors);
  final slots = desktop
      ? (processors * 2).clamp(4, 16)
      : processors.clamp(4, 8);
  return math.min(providerCount, slots);
}

/// Filtering a tiny provider list takes much less than the CPU and transfer
/// overhead of spawning a one-off isolate. Large provider lists still leave
/// the UI isolate to avoid frames dropped during title normalization.
///
/// The threshold is intentionally independent of hardware core count: the
/// direct-vs-compute CI benchmark records representative list sizes. Run
/// profile-mode on-device benchmarks before tuning for a particular TV/phone.
const int kSearchFilterIsolateMinItems = 512;

typedef SearchBackgroundFilter = Future<List<MultimediaItem>> Function(
  List<MultimediaItem> items,
  String query,
);

class _FilterRequest {
  final List<MultimediaItem> items;
  final String query;

  const _FilterRequest(this.items, this.query);
}

List<MultimediaItem> _filterOnWorker(_FilterRequest request) =>
    filterProviderSearchResults(request.items, request.query);

/// Same multilingual filter and result order regardless of execution path.
/// The optional runner lets regression tests verify the scheduling decision.
Future<List<MultimediaItem>> filterSearchItems(
  List<MultimediaItem> items,
  String query, {
  SearchBackgroundFilter? runInBackground,
}) {
  if (items.length < kSearchFilterIsolateMinItems) {
    return Future.value(filterProviderSearchResults(items, query));
  }
  if (runInBackground != null) {
    return runInBackground(items, query);
  }
  return compute(_filterOnWorker, _FilterRequest(items, query));
}
