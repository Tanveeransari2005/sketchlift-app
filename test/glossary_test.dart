import 'package:flutter_test/flutter_test.dart';
import 'package:sketchlift/services/glossary.dart';

void main() {
  group('Glossary.fix', () {
    test('fixes common student misspellings', () {
      expect(Glossary.fix('mitocondria'), 'Mitochondria');
      expect(Glossary.fix('chloroplst'), 'Chloroplast');
      expect(Glossary.fix('nuclues'), 'Nucleus');
      expect(Glossary.fix('vacoule'), 'Vacuole');
      expect(Glossary.fix('cell wal'), 'Cell wall');
      expect(Glossary.fix('zylem', subject: 'Biology'), 'Xylem');
      expect(Glossary.fix('Phloem'), 'Phloem');
      expect(Glossary.fix('cytoplasm'), 'Cytoplasm');
      expect(Glossary.fix('stomta'), 'Stomata');
    });

    test('is case- and punctuation-insensitive', () {
      expect(Glossary.fix('  MITOCHONDRIA. '), 'Mitochondria');
      expect(Glossary.fix('golgi-apparatus'), 'Golgi apparatus');
    });

    test('does not force unrelated or short words', () {
      expect(Glossary.bestMatch('ear'), 'Ear');
      expect(Glossary.bestMatch('eat'), isNull); // 3 letters: exact only
      expect(Glossary.fix('my custom label'), 'My custom label');
      expect(Glossary.bestMatch(''), isNull);
    });

    test('subject terms are preferred', () {
      expect(Glossary.fix('concave lens', subject: 'Physics'), 'Concave lens');
      expect(Glossary.fix('troposfere', subject: 'Geography'), 'Troposphere');
    });
  });

  test('Damerau-Levenshtein distance', () {
    expect(Glossary.damerauLevenshtein('abc', 'abc'), 0);
    expect(Glossary.damerauLevenshtein('abc', 'acb'), 1); // swap
    expect(Glossary.damerauLevenshtein('kitten', 'sitting'), 3);
    expect(Glossary.damerauLevenshtein('', 'abc'), 3);
  });

  test('allowed distance grows with word length', () {
    expect(Glossary.maxDistanceFor(3), 0);
    expect(Glossary.maxDistanceFor(5), 1);
    expect(Glossary.maxDistanceFor(8), 2);
    expect(Glossary.maxDistanceFor(20), 3);
  });
}
