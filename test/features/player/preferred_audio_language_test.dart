import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/features/settings/presentation/player_settings_provider.dart';

import 'fake_vlc_engine.dart';
import 'vlc_screen_harness.dart';

void main() {
  late FakeVlcEngine engine;

  setUp(() {
    engine = FakeVlcEngine();
    installEngineMocks(engine: engine);
  });
  tearDown(removeEngineMocks);

  List<Object?> selectedAudio() => engine
      .callsTo('setAudioTrack')
      .map((call) => (call.arguments as Map<Object?, Object?>)['id'])
      .toList();

  testWidgets('first open picks the preferred language, not VLC default', (
    tester,
  ) async {
    engine.audio = const <Map<String, Object?>>[
      {'id': 1, 'name': 'English', 'language': 'eng'},
      {'id': 7, 'name': 'Turkish', 'language': 'tur'},
    ];
    engine.activeAudioId = 1;

    await pumpPlayer(
      tester,
      settings: const PlayerSettings(preferredAudioLanguage: 'tr'),
    );
    await sendEvent(tester, engine.event());
    await settle(tester);

    expect(selectedAudio(), contains(7));
    await tester.pumpWidget(const SizedBox());
  }, variant: texturePlatform);

  testWidgets('late audio tracks still receive the preference', (
    tester,
  ) async {
    engine.audio = const <Map<String, Object?>>[
      {'id': 1, 'name': 'English', 'language': 'eng'},
    ];
    engine.activeAudioId = 1;

    await pumpPlayer(
      tester,
      settings: const PlayerSettings(preferredAudioLanguage: 'tr'),
    );
    await sendEvent(tester, engine.event());
    await settle(tester);
    expect(selectedAudio(), isNot(contains(7)));

    engine.audio = const <Map<String, Object?>>[
      {'id': 1, 'name': 'English', 'language': 'eng'},
      {'id': 7, 'name': 'Turkish', 'language': 'tur'},
    ];
    await engine.bumpTracks();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    expect(selectedAudio(), contains(7));
    await tester.pumpWidget(const SizedBox());
  }, variant: texturePlatform);

  testWidgets('without a preference never changes the engine-selected audio', (
    tester,
  ) async {
    engine.audio = const <Map<String, Object?>>[
      {'id': 1, 'name': 'English', 'language': 'eng'},
      {'id': 7, 'name': 'Turkish', 'language': 'tur'},
    ];
    engine.activeAudioId = 1;
    await pumpPlayer(tester);
    await sendEvent(tester, engine.event());
    await settle(tester);
    expect(selectedAudio(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  }, variant: texturePlatform);

  testWidgets('absent preferred language preserves VLC default', (tester) async {
    engine.audio = const <Map<String, Object?>>[
      {'id': 1, 'name': 'English', 'language': 'eng'},
    ];
    engine.activeAudioId = 1;
    await pumpPlayer(
      tester,
      settings: const PlayerSettings(preferredAudioLanguage: 'tr'),
    );
    await sendEvent(tester, engine.event());
    await settle(tester);

    expect(selectedAudio(), isEmpty);
    expect(engine.activeAudioId, 1);
    await tester.pumpWidget(const SizedBox());
  }, variant: texturePlatform);
}
