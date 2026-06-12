/// Преобразование человеческого текста в токены формата `R_111000 E_100100 ...`,
/// которые понимает прошивка BrailleReader.
///
/// Логика:
///   1. Авто-определение языка по наличию кириллических символов.
///   2. Цифры разворачиваются в слова ("123" -> "ОДИН ДВА ТРИ").
///   3. Текст приводится к верхнему регистру.
///   4. Каждая буква маппится в 6-битный паттерн с префиксом языка.
///   5. Неизвестные символы заменяются пробелом (`_111111`).
library;

/// Языки, поддерживаемые устройством.
enum BrailleLang { russian, english }

class BrailleCodec {
  /// Стандартная таблица русского шрифта Брайля (по ГОСТ Р 51645-2000).
  ///
  /// ВАЖНО: тут исправлен баг старого приложения, где З и О имели одинаковый
  /// код `101010`. Правильный код для З — `101001`. С этим же кодом теперь
  /// работает прошивка.
  static const Map<String, String> _russian = {
    'А': '100000', 'Б': '110000', 'В': '100010', 'Г': '110010', 'Д': '100110',
    'Е': '100100', 'Ё': '111011', 'Ж': '010110', 'З': '101001', 'И': '010010',
    'Й': '010011', 'К': '101000', 'Л': '111000', 'М': '101100', 'Н': '101110',
    'О': '101010', 'П': '111100', 'Р': '111010', 'С': '011010', 'Т': '011110',
    'У': '100001', 'Ф': '110100', 'Х': '110110', 'Ц': '110101', 'Ч': '110111',
    'Ш': '101101', 'Щ': '101111', 'Ъ': '101011', 'Ы': '011101', 'Ь': '011100',
    'Э': '011111', 'Ю': '111101', 'Я': '111001', ' ': '111111',
  };

  static const Map<String, String> _english = {
    'A': '100000', 'B': '110000', 'C': '100100', 'D': '100110', 'E': '100010',
    'F': '110100', 'G': '110110', 'H': '110010', 'I': '010100', 'J': '010110',
    'K': '101000', 'L': '111000', 'M': '101100', 'N': '101110', 'O': '101010',
    'P': '111100', 'Q': '111110', 'R': '111010', 'S': '011100', 'T': '011110',
    'U': '101001', 'V': '111001', 'W': '010111', 'X': '101101', 'Y': '101111',
    'Z': '101011', ' ': '111111',
  };

  static const Map<String, String> _digitsRu = {
    '0': 'НОЛЬ',  '1': 'ОДИН',   '2': 'ДВА',    '3': 'ТРИ',    '4': 'ЧЕТЫРЕ',
    '5': 'ПЯТЬ',  '6': 'ШЕСТЬ',  '7': 'СЕМЬ',   '8': 'ВОСЕМЬ', '9': 'ДЕВЯТЬ',
  };

  static const Map<String, String> _digitsEn = {
    '0': 'ZERO',  '1': 'ONE',    '2': 'TWO',    '3': 'THREE',  '4': 'FOUR',
    '5': 'FIVE',  '6': 'SIX',    '7': 'SEVEN',  '8': 'EIGHT',  '9': 'NINE',
  };

  static final RegExp _cyrillic = RegExp(r'[\u0400-\u04FF]');

  /// Определить язык по содержимому. Если есть хоть один кириллический
  /// символ — русский, иначе английский.
  static BrailleLang detectLanguage(String text) {
    return _cyrillic.hasMatch(text) ? BrailleLang.russian : BrailleLang.english;
  }

  /// Преобразовать текст в строку токенов для отправки в устройство.
  ///
  /// Возвращает строку вида "R_111000 R_100010 ..." с пробелами между токенами.
  static String encode(String text) {
    if (text.trim().isEmpty) return '';

    final lang = detectLanguage(text);
    final isRu = lang == BrailleLang.russian;
    final digits = isRu ? _digitsRu : _digitsEn;
    final letters = isRu ? _russian : _english;
    final prefix = isRu ? 'R' : 'E';
    final spaceCode = letters[' ']!;

    // Шаг 1: цифры -> слова.
    final expanded = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      final word = digits[ch];
      if (word != null) {
        // Цифру окружаем пробелами, чтобы «5лет» не превратилось в «ПЯТЬЛЕТ».
        if (i > 0 && expanded.isNotEmpty &&
            expanded.toString().codeUnitAt(expanded.length - 1) != 32) {
          expanded.write(' ');
        }
        expanded.write(word);
        if (i < text.length - 1) expanded.write(' ');
      } else {
        expanded.write(ch);
      }
    }

    // Шаг 2: верхний регистр + маппинг в токены.
    final upper = expanded.toString().toUpperCase();
    final tokens = <String>[];
    for (var i = 0; i < upper.length; i++) {
      final ch = upper[i];
      final code = letters[ch] ?? spaceCode;
      tokens.add('${prefix}_$code');
    }
    return tokens.join(' ');
  }
}
