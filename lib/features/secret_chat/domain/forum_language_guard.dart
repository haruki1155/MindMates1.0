/// Early, on-device warning for common inappropriate Forum language.
///
/// This is a small subset for instant feedback only. The server's moderation
/// (functions/src/moderation) is authoritative and holds the full dictionary.
library;

const forumLanguageWarning =
    'MindMate is a safe and supportive community. Please revise your message '
    'using respectful language before publishing.';

const forumLanguageGuideline =
    'Use respectful language. Profanity, insults, slurs, sexual remarks and '
    'harassment are not published, including disguised spellings. You can '
    'always share hard feelings honestly; for urgent concerns, use MindAid or '
    'contact PACC.';

const _terms = {
  'fuck',
  'fucking',
  'fck',
  'shit',
  'bitch',
  'ashole',
  'bastard',
  'dick',
  'cunt',
  'pusy',
  'whore',
  'slut',
  'stfu',
  'wtf',
  'retard',
  'kys',
};
const _filipinoTerms = {
  'putangina',
  'tangina',
  'tngina',
  'ptngina',
  'puta',
  'gago',
  'gagu',
  'gaga',
  'bobo',
  'tanga',
  'ulol',
  'tarantado',
  'punyeta',
  'pakshet',
  'kupal',
  'pokpok',
  'leche',
};
const _prefixes = ['', 'ka', 'pinaka', 'naka', 'nakaka', 'mag', 'pag'];
const _suffixes = ['', 'mo', 'ka', 'ng', 'han', 'an', 'in', 'yan'];
const _phrases = [
  ['tang', 'ina'],
  ['putang', 'ina'],
  ['kil', 'yourself'],
  ['hayop', 'ka'],
];
const _exceptNext = {
  'leche': {'flan', 'plan'},
};

final Set<String> _index = {
  ..._terms,
  for (final stem in _filipinoTerms)
    for (final prefix in _prefixes)
      for (final suffix in _suffixes)
        if (_collapse('$prefix$stem$suffix') == '$prefix$stem$suffix' ||
            prefix.isEmpty && suffix.isEmpty)
          _collapse('$prefix$stem$suffix'),
};

const _map = {
  '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b',
  '9': 'g', '@': 'a', r'$': 's', '!': 'i', '|': 'l', '+': 't',
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'ú': 'u',
  'ù': 'u', 'ü': 'u', 'ñ': 'n',
  // Cyrillic look-alikes.
  'а': 'a', 'е': 'e', 'о': 'o', 'р': 'p', 'с': 'c', 'у': 'y', 'х': 'x',
  'і': 'i', 'ѕ': 's', 'һ': 'h',
};

final _invisible = RegExp(
  r'[\u00AD\u034F\u061C\u180E\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF]',
  unicode: true,
);

String _collapse(String token) {
  final out = StringBuffer();
  String? last;
  for (final char in token.split('')) {
    if (char != last) out.write(char);
    last = char;
  }
  return out.toString();
}

String _letters(String token) {
  final out = StringBuffer();
  for (final rune in token.runes) {
    final char = String.fromCharCode(rune);
    final mapped = _map[char] ?? char;
    final code = mapped.codeUnitAt(0);
    if (mapped.length == 1 && code >= 0x61 && code <= 0x7a) out.write(mapped);
  }
  return _collapse(out.toString());
}

bool containsInappropriateLanguage(String text) {
  final canonical = text.replaceAll(_invisible, '').toLowerCase();
  final spaced = canonical
      .split(RegExp(r'\s+'))
      .map(_letters)
      .where((token) => token.isNotEmpty)
      .toList();
  final split = canonical
      .split(RegExp(r'[^a-z0-9@$!|+áàâäéèêíìóòôöúùüñаеорсухіѕһ]+'))
      .map(_letters)
      .where((token) => token.isNotEmpty)
      .toList();

  bool hit(List<String> tokens) {
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final next = i + 1 < tokens.length ? tokens[i + 1] : '';
      if (_index.contains(token) &&
          !(_exceptNext[token]?.contains(next) ?? false)) {
        return true;
      }
      for (final phrase in _phrases) {
        if (i + phrase.length <= tokens.length &&
            [for (var j = 0; j < phrase.length; j++) tokens[i + j] == phrase[j]]
                .every((match) => match)) {
          return true;
        }
      }
    }
    return false;
  }

  if (hit(spaced) || hit(split)) return true;
  // "p u t a n g i n a" and "fu ck".
  final joined = <String>[];
  var run = StringBuffer();
  var runLength = 0;
  void flush() {
    if (runLength >= 3) joined.add(_collapse(run.toString()));
    run = StringBuffer();
    runLength = 0;
  }

  for (final token in spaced) {
    if (token.length == 1) {
      run.write(token);
      runLength++;
    } else {
      flush();
    }
  }
  flush();
  for (var i = 0; i + 1 < spaced.length; i++) {
    final a = spaced[i];
    final b = spaced[i + 1];
    if (a.length >= 2 && a.length <= 4 && b.length >= 2 && b.length <= 4) {
      joined.add(_collapse('$a$b'));
    }
  }
  return joined.any(_index.contains);
}
