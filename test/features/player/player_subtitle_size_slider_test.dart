import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/features/player/presentation/vlc/panel/player_subtitle_size_slider.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

void main() {
  Future<void> pumpSize(
    WidgetTester tester, {
    required double value,
    required ValueChanged<double> onChangeEnd,
  }) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PlayerSubtitleSizeSlider(
          value: value,
          onChangeEnd: onChangeEnd,
        ),
      ),
    ),
  );

  testWidgets('shows the saved size and uses the settings range', (
    tester,
  ) async {
    await pumpSize(tester, value: 22, onChangeEnd: (_) {});

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 22);
    expect(slider.min, 10);
    expect(slider.max, 80);
    expect(slider.divisions, 70);
    expect(find.text('Text size'), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
  });

  testWidgets('previews every drag but commits only when released', (
    tester,
  ) async {
    final saved = <double>[];
    await pumpSize(tester, value: 22, onChangeEnd: saved.add);

    tester.widget<Slider>(find.byType(Slider)).onChanged!(30);
    await tester.pump();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(44);
    await tester.pump();

    expect(tester.widget<Slider>(find.byType(Slider)).value, 44);
    expect(find.text('44'), findsOneWidget);
    expect(saved, isEmpty);

    tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(44);
    expect(saved, <double>[44]);

    await pumpSize(tester, value: 44, onChangeEnd: saved.add);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 44);
  });

  testWidgets('follows an external settings update while idle', (
    tester,
  ) async {
    await pumpSize(tester, value: 22, onChangeEnd: (_) {});
    await pumpSize(tester, value: 36, onChangeEnd: (_) {});

    expect(tester.widget<Slider>(find.byType(Slider)).value, 36);
    expect(find.text('36'), findsOneWidget);
  });
}
