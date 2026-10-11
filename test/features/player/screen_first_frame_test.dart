import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';
import 'package:skystream/features/player/presentation/vlc/vlc_player_controls.dart';

import 'vlc_screen_harness.dart';

/// The bars come up over a video's first frame, as Android's own player does,
/// and hide by themselves a few seconds into playback. A screen reader user
/// depends on it: with the bars down the player has no controls to find.
void main() {
  setUp(installEngineMocks);
  tearDown(removeEngineMocks);

  final film = MultimediaItem(
    title: 'The Matrix',
    url: 'https://example.com/matrix',
    posterUrl: '',
    provider: 'Remote',
  );

  bool chromeUp(WidgetTester tester) => tester
      .widget<VlcPlayerControls>(find.byType(VlcPlayerControls))
      .chrome!
      .value;

  testWidgets(
    'the controls come up over the first frame',
    variant: texturePlatform,
    (tester) async {
      await pumpPlayer(tester, item: film, videoUrl: film.url);
      await sendFirstFrame(tester);

      expect(chromeUp(tester), isTrue);
    },
  );

  testWidgets(
    "the controls come back over a new attempt's first frame, with the remote "
    'on play/pause',
    variant: texturePlatform,
    (tester) async {
      await pumpPlayer(
        tester,
        // Bare paths, so the resolver's health probe answers without a socket.
        preloadedStreams: const [
          StreamResult(
            url: '/sources/alpha.mkv',
            source: '1080p',
            providerName: 'Alpha',
          ),
          StreamResult(
            url: '/sources/beta.mkv',
            source: '720p',
            providerName: 'Beta',
          ),
        ],
      );
      await sendFirstFrame(tester);
      await sendEvent(tester, snapshot(position: 6000));
      await tester.pump(const Duration(seconds: 4));
      expect(chromeUp(tester), isFalse, reason: 'gone a few seconds in');

      // The source dies; the next attempt's first picture is a new picture.
      await sendEvent(tester, snapshot(state: 'error', position: 6000));
      await settle(tester);
      await sendEvent(tester, snapshot(position: 9000));
      await sendEvent(tester, snapshot(position: 9500));

      expect(chromeUp(tester), isTrue);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'player-play-pause',
      );

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a screen reader finds the controls on the first frame',
    variant: texturePlatform,
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final semantics = tester.ensureSemantics();

      await pumpPlayer(tester, item: film, videoUrl: film.url);
      await sendFirstFrame(tester);
      await tester.pump(const Duration(milliseconds: 400));

      for (final label in <String>['Back', 'Pause', 'Options']) {
        expect(find.semantics.byLabel(label), findsOne, reason: label);
      }
      semantics.dispose();
    },
  );
}
