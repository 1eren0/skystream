import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/features/search/presentation/search_provider.dart';

/// Search keeps a result only when every word of the query begins a word of
/// its title. Words are split at punctuation as well as spaces: a title's
/// year in brackets, or a hyphenated name, is still made of words.
void main() {
  test('a year in brackets is a word', () {
    expect(searchWords('His Girl Friday (1940)'), [
      'his',
      'girl',
      'friday',
      '1940',
    ]);
    expect(
      titleMatches(
        'His Girl Friday (1940)',
        searchWords('his girl friday 1940'),
      ),
      isTrue,
    );
  });

  test('hyphens, colons and apostrophes split words', () {
    expect(searchWords("Spider-Man: Don't Look Back"), [
      'spider',
      'man',
      'don',
      't',
      'look',
      'back',
    ]);
    expect(
      titleMatches('Spider-Man: No Way Home', searchWords('spider man')),
      isTrue,
    );
    expect(
      titleMatches('Spider-Man: No Way Home', searchWords('spider-man')),
      isTrue,
    );
  });

  test('words still have to begin a title word, in any order', () {
    expect(
      titleMatches('Night of the Living Dead', searchWords('dead night')),
      isTrue,
    );
    expect(
      titleMatches('Night of the Living Dead', searchWords('ight')),
      isFalse,
    );
    expect(
      titleMatches('Night of the Living Dead', searchWords('night zombie')),
      isFalse,
    );
  });

  test('letters and digits of any script stay words', () {
    expect(searchWords('Shingeki no Kyojin (進撃の巨人)'), [
      'shingeki',
      'no',
      'kyojin',
      '進撃の巨人',
    ]);
    expect(searchWords('Pokémon 2000'), ['pokémon', '2000']);
    expect(
      titleMatches('Pokémon: The Movie 2000', searchWords('pokémon 2000')),
      isTrue,
    );
  });

  test('a query of only punctuation has no words', () {
    expect(searchWords(' --- '), isEmpty);
  });
}
