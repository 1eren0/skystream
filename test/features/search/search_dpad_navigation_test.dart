import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';
import 'package:skystream/core/extensions/base_provider.dart';
import 'package:skystream/core/extensions/extension_manager.dart';
import 'package:skystream/core/network/clearance/clearance.dart';
import 'package:skystream/core/network/clearance/clearance_solver.dart';
import 'package:skystream/core/network/clearance/clearance_store.dart';
import 'package:skystream/core/network/clearance/site_checks.dart';
import 'package:skystream/core/network/clearance/site_keys.dart';
import 'package:skystream/features/explore/presentation/delegates/explore_search_delegate.dart';
import 'package:skystream/features/home/presentation/delegates/home_search_delegate.dart';
import 'package:skystream/features/search/data/search_history_store.dart';
import 'package:skystream/features/search/presentation/search_provider.dart';
import 'package:skystream/features/search/presentation/search_screen.dart';
import 'package:skystream/features/search/presentation/widgets/search_suggestion_row.dart';
import 'package:skystream/features/settings/presentation/general_settings_provider.dart';
import 'package:skystream/shared/widgets/cards_wrapper.dart';
import 'package:skystream/shared/widgets/multimedia_card.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

class _FakeStore implements SearchHistoryStore {
  List<String> queries;

  _FakeStore(this.queries);

  @override
  List<String> read() => queries;

  @override
  Future<void> write(List<String> next) async {
    queries = List<String>.from(next);
  }
}

/// A plugin whose requests are tagged `js:a` when they meet a bot check.
class _Plugin extends SkyStreamProvider {
  @override
  String get name => 'A';
  @override
  String get packageName => 'p.a';
  @override
  String? get checkSource => 'js:a';
  @override
  String get mainUrl => '';
  @override
  String get version => '1';
  @override
  List<String> get languages => const ['en'];
  @override
  Set<ProviderType> get supportedTypes => const {ProviderType.movie};
  @override
  Future<List<MultimediaItem>> search(String q, {CancelToken? cancelToken}) =>
      throw UnimplementedError();
  @override
  Future<Map<String, List<MultimediaItem>>> getHome() =>
      throw UnimplementedError();
  @override
  Future<MultimediaItem> getDetails(String url) => throw UnimplementedError();
  @override
  Future<List<StreamResult>> loadStreams(String url) =>
      throw UnimplementedError();
}

class _Manager extends ExtensionManager {
  _Manager(this.plugins);

  final List<SkyStreamProvider> plugins;

  @override
  List<SkyStreamProvider> build() => plugins;
}

void main() {
  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  /// The text of the row that currently holds focus, or null.
  String? focusedRowText(WidgetTester tester) {
    final focused = tester
        .widgetList<SearchSuggestionRow>(find.byType(SearchSuggestionRow))
        .where((row) => row.focusNode?.hasFocus ?? false);
    return focused.isEmpty ? null : focused.first.text;
  }

  bool fieldHasFocus(WidgetTester tester) {
    return tester
        .widgetList<EditableText>(find.byType(EditableText))
        .any((field) => field.focusNode.hasFocus);
  }

  group('search tab', () {
    /// The bot checks the app has met, which the screen's check section reads.
    SiteChecks useChecks({DateTime Function()? clock}) {
      final keys = SiteKeys.parse(
        File('assets/clearance/public_suffix_list.dat').readAsStringSync(),
      );
      final checks = SiteChecks(clock: clock);
      final store = ClearanceStore();
      Clearance.instance.debugUse(
        store: store,
        siteKeys: keys,
        checks: checks,
        solver: ClearanceSolver(store: store, siteKeys: keys, checks: checks),
      );
      return checks;
    }

    Future<void> pumpSearch(
      WidgetTester tester, {
      required List<String> history,
      required Size size,
      Stream<SearchAggregateState>? results,
      List<SkyStreamProvider>? plugins,
      bool settle = true,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchHistoryStoreProvider.overrideWithValue(
              _FakeStore(List<String>.from(history)),
            ),
            searchResultsProvider.overrideWith(
              (ref) => results ?? Stream.value(const SearchAggregateState()),
            ),
            if (plugins != null)
              extensionManagerProvider.overrideWith(() => _Manager(plugins)),
            generalSettingsProvider.overrideWithValue(const GeneralSettings()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData.dark(),
            home: const SearchScreen(),
          ),
        ),
      );
      // Result cards show a looping placeholder while their posters load,
      // so a screen with results never settles.
      Future<void> pump() => settle
          ? tester.pumpAndSettle()
          : tester.pump(const Duration(seconds: 1));
      await pump();
      await tester.tap(find.byType(TextField));
      await pump();
    }

    // The bar used to be a column, so down from the field meant "into the
    // scope pill". The pill stands beside the field now and the panel is what
    // is underneath, so down has to reach the list.
    for (final (name, size) in [
      ('desktop', const Size(1440, 900)),
      ('phone', const Size(400, 800)),
    ]) {
      testWidgets('$name: down from the field enters the list', (tester) async {
        await pumpSearch(tester, history: ['Dune', 'Arrival'], size: size);

        await press(tester, LogicalKeyboardKey.arrowDown);

        expect(focusedRowText(tester), 'Dune');
      });

      testWidgets('$name: up from the first row returns to the field', (
        tester,
      ) async {
        await pumpSearch(tester, history: ['Dune'], size: size);

        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focusedRowText(tester), 'Dune');

        await press(tester, LogicalKeyboardKey.arrowUp);

        expect(fieldHasFocus(tester), isTrue);
      });

      testWidgets('$name: right off a row reaches its remove button', (
        tester,
      ) async {
        await pumpSearch(tester, history: ['Dune'], size: size);

        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.arrowRight);

        // The body node gave the button its focus, so neither the row body
        // nor the field holds it now.
        expect(focusedRowText(tester), isNull);
        expect(fieldHasFocus(tester), isFalse);

        // And select on it drops the recent.
        await press(tester, LogicalKeyboardKey.enter);
        expect(find.text('Dune'), findsNothing);
      });

      // On a television the checks the search met sit between the field and
      // the results, so the D-pad has to stop there on its way down.
      testWidgets('$name: down from the field reaches the checks', (
        tester,
      ) async {
        final checks = useChecks();
        final began = checks.now;
        // A site that needs the person: nothing spins, so the screen settles.
        checks
          ..met('a.com', source: 'js:a')
          ..update('a.com', CheckState.needsYou);
        await pumpSearch(
          tester,
          history: const [],
          size: size,
          results: Stream.value(SearchAggregateState(startedAt: began)),
          plugins: [_Plugin()],
        );

        await press(tester, LogicalKeyboardKey.arrowDown);

        final showSites = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Show the sites'),
            matching: find.byType(IconButton),
          ),
        );
        expect(showSites.focusNode?.hasFocus, isTrue);
      });

      // A focus node keeps its last context after it leaves the tree. A
      // section that has gone mustn't catch Down: the press would be lost,
      // and the section's button would take the focus when it came back.
      testWidgets('$name: checks that have gone do not catch down', (
        tester,
      ) async {
        var time = DateTime(2026, 10, 3, 12);
        final checks = useChecks(clock: () => time);
        final searches = StreamController<SearchAggregateState>();
        addTearDown(searches.close);
        checks
          ..met('a.com', source: 'js:a')
          ..update('a.com', CheckState.needsYou);
        searches.add(SearchAggregateState(startedAt: time));
        await pumpSearch(
          tester,
          history: const [],
          size: size,
          results: searches.stream,
          plugins: [_Plugin()],
        );
        expect(find.byTooltip('Show the sites'), findsOneWidget);

        // A new search, which has met no check.
        time = time.add(const Duration(minutes: 1));
        searches.add(SearchAggregateState(startedAt: time));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Show the sites'), findsNothing);
        await press(tester, LogicalKeyboardKey.arrowDown);

        // Then it meets one.
        time = time.add(const Duration(seconds: 1));
        checks
          ..met('b.com', source: 'js:a')
          ..update('b.com', CheckState.needsYou);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Show the sites'), findsOneWidget);
        expect(fieldHasFocus(tester), isTrue);
      });

      // A result card and the scope pill hand their nodes to a CardsWrapper,
      // whose own key handler replaced the screen's on those nodes: on a
      // television, down from the pill and up from the first result went
      // past the checks.
      for (final (from, key) in [
        // A phone's bar has no labelled pill to stand on.
        if (name == 'desktop') ('the scope pill', LogicalKeyboardKey.arrowDown),
        ('the first result', LogicalKeyboardKey.arrowUp),
      ]) {
        testWidgets('$name: $from reaches the checks', (tester) async {
          final checks = useChecks();
          final began = checks.now;
          checks
            ..met('a.com', source: 'js:a')
            ..update('a.com', CheckState.needsYou);
          await pumpSearch(
            tester,
            history: const [],
            size: size,
            settle: false,
            results: Stream.value(
              SearchAggregateState(
                startedAt: began,
                results: [
                  ProviderSearchResult(
                    providerId: 'p.a',
                    providerName: 'A',
                    results: [
                      for (var i = 0; i < 12; i++)
                        MultimediaItem(
                          title: 'Film $i',
                          url: 'u/$i',
                          posterUrl: '',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            plugins: [_Plugin()],
          );
          final node = from == 'the scope pill'
              ? tester
                    .widget<CardsWrapper>(
                      find.ancestor(
                        of: find.text('Movies & Shows'),
                        matching: find.byType(CardsWrapper),
                      ),
                    )
                    .focusNode!
              : tester
                    .widget<MultimediaCard>(find.byType(MultimediaCard).first)
                    .focusNode!;
          node.requestFocus();
          await tester.pump();
          expect(node.hasPrimaryFocus, isTrue);

          await tester.sendKeyEvent(key);
          await tester.pump();

          final showSites = tester.widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Show the sites'),
              matching: find.byType(IconButton),
            ),
          );
          expect(showSites.focusNode?.hasFocus, isTrue);
          await tester.pumpWidget(const SizedBox());
        });
      }

      testWidgets('$name: select on a row runs that search', (tester) async {
        await pumpSearch(tester, history: ['Dune'], size: size);

        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.enter);

        // The panel is down and the query is committed to the field. It used
        // to reopen a frame later: tearing down the focused row bounced focus
        // back to the field, which the screen reads as "show the panel".
        expect(find.byType(SearchSuggestionRow), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Dune',
        );
      });
    }
  });

  group('delegates', () {
    Future<void> openSearch(
      WidgetTester tester,
      SearchDelegate<void> Function() delegate, {
      required List<String> history,
    }) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchHistoryStoreProvider.overrideWithValue(
              _FakeStore(List<String>.from(history)),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showSearch<void>(
                      context: context,
                      delegate: delegate(),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    // An EditableText swallows arrow keys for its own caret, so without the
    // global handler a remote could never leave the search field.
    testWidgets('home: down from the field enters the list', (tester) async {
      await openSearch(
        tester,
        HomeSearchDelegate.new,
        history: ['Dune', 'Arrival'],
      );
      expect(fieldHasFocus(tester), isTrue);

      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(focusedRowText(tester), 'Dune');
    });

    testWidgets('home: right off a row reaches its remove button', (
      tester,
    ) async {
      await openSearch(tester, HomeSearchDelegate.new, history: ['Dune']);

      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.enter);

      expect(find.text('Dune'), findsNothing);
    });

    testWidgets('explore: down from the field enters the list', (tester) async {
      await openSearch(
        tester,
        ExploreSearchDelegate.new,
        history: ['Dune', 'Arrival'],
      );
      expect(fieldHasFocus(tester), isTrue);

      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(focusedRowText(tester), 'Dune');
    });

    testWidgets('explore: select on a row runs that search', (tester) async {
      await openSearch(tester, ExploreSearchDelegate.new, history: ['Dune']);

      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.enter);

      // showResults swapped the suggestions out for the results grid.
      expect(find.byType(SearchSuggestionRow), findsNothing);
    });
  });
}
