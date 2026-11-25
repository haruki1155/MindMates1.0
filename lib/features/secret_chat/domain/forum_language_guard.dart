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

final _invisible = RegExp(
  r'[\u00AD\u034F\u061C\u180E\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF]',
  unicode: true,
);

const _letterSwaps = {
  '0': 'o',
  '1': 'i',
  '3': 'e',
  '4': 'a',
  '5': 's',
  '7': 't',
  '8': 'b',
  '9': 'g',
  '@': 'a',
  r'$': 's',
  '!': 'i',
  '|': 'l',
  '+': 't',
};
const _lookAlikes = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'ú': 'u',
  'ù': 'u', 'ü': 'u', 'ñ': 'n', 'ø': 'o', 'ł': 'l', 'đ': 'd', 'ƒ': 'f',
  // Cyrillic look-alikes.
  'а': 'a', 'е': 'e', 'о': 'o', 'р': 'p', 'с': 'c', 'у': 'y', 'х': 'x',
  'і': 'i', 'ѕ': 's', 'һ': 'h',
};

const _terms = {
  'fuck',
  'fck',
  'fuk',
  'fvck',
  'phuck',
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
  'niger',
  'fagot',
};
const _englishSuffixes = ['', 's', 'es', 'er', 'ers', 'in', 'ing', 'ed', 'y'];
const _filipinoTerms = {
  'putangina',
  'tangina',
  'tngina',
  'ptngina',
  'puta',
  'gago',
  'gagu',
  'ulol',
  'tarantado',
  'punyeta',
  'pakshet',
  'kupal',
  'pokpok',
  'leche',
};
const _selfAllowedTerms = {'bobo', 'tanga', 'inutil'};
const _prefixes = ['', 'ka', 'pinaka', 'naka', 'nakaka', 'mag', 'pag'];
const _suffixes = ['', 'mo', 'ka', 'ng', 'han', 'an', 'in', 'yan', 'ako'];
const _phrases = [
  ['tang', 'ina'],
  ['putang', 'ina'],
  ['kil', 'yourself'],
  ['hayop', 'ka'],
  ['mamatay', 'ka'],
];
const _exceptNext = {
  'leche': {'flan', 'plan'},
};
const _selfNext = {'ko', 'ako'};
const _stopwords = {
  'as',
  'at',
  'go',
  'ok',
  'in',
  'is',
  'it',
  'me',
  'my',
  'no',
  'of',
  'on',
  'so',
  'to',
  'up',
  'the',
  'and',
  'you',
  'put',
  'ang',
  'ka',
  'ko',
  'mo',
  'na',
  'ng',
  'sa',
  'yan',
  'ako',
  'pa',
  'po',
};

/// Collapsed spelling with the prefix it was built from (for "nakaka" forms).
final Map<String, ({String prefix, bool selfAllowed})> _index = () {
  final index = <String, ({String prefix, bool selfAllowed})>{};
  void add(
    String stem,
    List<String> prefixes,
    List<String> suffixes,
    bool selfAllowed,
  ) {
    for (final prefix in prefixes) {
      for (final suffix in suffixes) {
        final variant = _collapse('$prefix$stem$suffix');
        if (variant ==
            _collapse(prefix) + _collapse(stem) + _collapse(suffix)) {
          index.putIfAbsent(
            variant,
            () => (prefix: prefix, selfAllowed: selfAllowed),
          );
        }
      }
    }
  }

  for (final term in _terms) {
    add(term, const [''], _englishSuffixes, false);
  }
  for (final term in _filipinoTerms) {
    add(term, _prefixes, _suffixes, false);
  }
  for (final term in _selfAllowedTerms) {
    add(term, _prefixes, _suffixes, true);
  }
  return index;
}();

String _collapse(String token) {
  final out = StringBuffer();
  String? last;
  for (final char in token.split('')) {
    if (char != last) out.write(char);
    last = char;
  }
  return out.toString();
}

bool _isLetter(String char) =>
    char.length == 1 &&
    char.codeUnitAt(0) >= 0x61 &&
    char.codeUnitAt(0) <= 0x7a;

String _letters(List<String> chars) {
  final out = StringBuffer();
  for (final char in chars) {
    final mapped = _letterSwaps[char] ?? char;
    if (_isLetter(mapped)) out.write(mapped);
  }
  return _collapse(out.toString());
}

List<String> _trim(List<String> chars) {
  var start = 0;
  var end = chars.length;
  while (start < end && !_isLetter(chars[start])) {
    start++;
  }
  while (end > start && !_isLetter(chars[end - 1])) {
    end--;
  }
  return chars.sublist(start, end);
}

/// Candidate spellings: edge symbols trimmed, every symbol read as a letter,
/// and an asterisk standing for a vowel.
Set<String> _forms(String raw) {
  final chars = [
    for (final rune in raw.runes)
      _lookAlikes[String.fromCharCode(rune)] ?? String.fromCharCode(rune),
  ];
  final trimmed = _trim(chars);
  final forms = <String>{_letters(trimmed), _letters(chars)};
  final star = trimmed.indexOf('*');
  if (star >= 0) {
    for (final vowel in const ['a', 'e', 'i', 'o', 'u']) {
      forms.add(_letters([...trimmed]..[star] = vowel));
    }
  }
  return forms..remove('');
}

bool containsInappropriateLanguage(String text) {
  final raw = text
      .replaceAll(_invisible, '')
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty);
  final forms = [
    for (final token in raw)
      if (_forms(token).isNotEmpty) _forms(token),
  ];
  final spaced = [for (final set in forms) set.first];

  for (var i = 0; i < forms.length; i++) {
    final next = i + 1 < spaced.length ? spaced[i + 1] : '';
    for (final form in forms[i]) {
      final match = _index[form];
      if (match == null) continue;
      if (_exceptNext[form]?.contains(next) ?? false) continue;
      if (match.selfAllowed &&
          (_selfNext.contains(next) || match.prefix == 'nakaka')) {
        continue;
      }
      return true;
    }
  }
  for (var i = 0; i < spaced.length; i++) {
    for (final phrase in _phrases) {
      if (i + phrase.length > spaced.length) continue;
      var same = true;
      for (var j = 0; j < phrase.length && same; j++) {
        same = spaced[i + j] == phrase[j];
      }
      if (same) return true;
    }
  }
  // "p u t a n g i n a", "fu ck", "f uc k".
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
  for (var i = 0; i < spaced.length; i++) {
    var glued = '';
    for (var size = 1; size <= 4 && i + size <= spaced.length; size++) {
      final part = spaced[i + size - 1];
      if (part.length > 5 || (part.length > 1 && _stopwords.contains(part))) {
        break;
      }
      glued += part;
      if (size >= 2 && glued.length <= 12) joined.add(_collapse(glued));
    }
  }
  return joined.any(_index.containsKey);
}
