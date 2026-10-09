import '../../../core/domain/entity/multimedia_item.dart';

/// Removes differences that commonly hide otherwise valid multilingual
/// title matches. This is deliberately lightweight, not transliteration:
/// a provider may return a translated title in a different script entirely.
String _normalizeSearchText(String text) => text
    .replaceAll('İ', 'i')
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640\u0307]'), '')
    .replaceAll(RegExp(r'[آأإٱ]'), 'ا')
    .replaceAll(RegExp(r'[-_./:(),!?،؛—–]'), ' ');

/// Filters the results returned by an extension, without discarding a
/// provider's entire response when its display titles use another language.
///
/// The extension has already performed the requested search. Title matches
/// can remove unrelated entries, but zero literal matches cannot prove the
/// provider's results are irrelevant: aliases and translated titles are common.
/// In that case, trust the provider and keep its original order.
List<MultimediaItem> filterProviderSearchResults(
  List<MultimediaItem> items,
  String query,
) {
  if (items.isEmpty) return items;

  final normalizedQuery = _normalizeSearchText(query).trim();
  if (normalizedQuery.isEmpty) return <MultimediaItem>[];

  final terms = normalizedQuery.split(RegExp(r'\s+'));
  final matching = items.where((item) {
    final title = _normalizeSearchText(item.title);
    return terms.every(title.contains);
  }).toList();

  return matching.isEmpty ? items : matching;
}
