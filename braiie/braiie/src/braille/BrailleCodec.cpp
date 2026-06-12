#include "BrailleCodec.h"
#include <string.h>

namespace braille {

// Битмаски строятся из строки "100000" так:
//   позиция 0 (левая) -> bit 0
//   позиция 1         -> bit 1
//   ...
//   позиция 5         -> bit 5

static uint8_t parseBits(const char* s) {
    uint8_t b = 0;
    for (uint8_t i = 0; i < DOTS; ++i) {
        if (s[i] == '1') b |= (1u << i);
    }
    return b;
}

bool parseToken(const char* token, size_t len, Cell& out) {
    if (len < 8) return false;          // X + _ + 6 цифр
    if (token[1] != '_') return false;

    char prefix = token[0];
    if (prefix != 'R' && prefix != 'E' && prefix != 'r' && prefix != 'e') return false;

    // Проверяем что биты — 0/1
    for (uint8_t i = 0; i < DOTS; ++i) {
        char c = token[2 + i];
        if (c != '0' && c != '1') return false;
    }

    out.lang = (prefix == 'R' || prefix == 'r') ? 'R' : 'E';
    out.bits = parseBits(token + 2);
    return true;
}

// ---------------------------------------------------------------------------
//                       ТАБЛИЦЫ ДЕКОДИРОВАНИЯ (для отладки)
// ---------------------------------------------------------------------------
//
// Хранятся как пары {битмаска, UTF-8 строка}.
// Для повторов (например, в русском З и О имели одинаковый код — наследие старого
// проекта) берётся первое совпадение.

struct CellEntry {
    uint8_t bits;
    const char* utf8;
};

// Хелпер — превратить строку битов в uint8_t на этапе компиляции через макрос.
// Делаем "по-старинке" без constexpr-функций, чтобы быть совместимыми с любыми
// версиями GCC.
#define BITS6(a,b,c,d,e,f) \
    (uint8_t)((a)|((b)<<1)|((c)<<2)|((d)<<3)|((e)<<4)|((f)<<5))

static const CellEntry RUS_TABLE[] = {
    { BITS6(1,0,0,0,0,0), "А" },
    { BITS6(1,1,0,0,0,0), "Б" },
    { BITS6(1,0,0,0,1,0), "В" },
    { BITS6(1,1,0,0,1,0), "Г" },
    { BITS6(1,0,0,1,1,0), "Д" },
    { BITS6(1,0,0,1,0,0), "Е" },
    { BITS6(1,1,1,0,1,1), "Ё" },
    { BITS6(0,1,0,1,1,0), "Ж" },
    { BITS6(1,0,1,0,0,1), "З" },
    { BITS6(0,1,0,0,1,0), "И" },
    { BITS6(0,1,0,0,1,1), "Й" },
    { BITS6(1,0,1,0,0,0), "К" },
    { BITS6(1,1,1,0,0,0), "Л" },
    { BITS6(1,0,1,1,0,0), "М" },
    { BITS6(1,0,1,1,1,0), "Н" },
    { BITS6(1,0,1,0,1,0), "О" },
    { BITS6(1,1,1,1,0,0), "П" },
    { BITS6(1,1,1,0,1,0), "Р" },
    { BITS6(0,1,1,0,1,0), "С" },
    { BITS6(0,1,1,1,1,0), "Т" },
    { BITS6(1,0,0,0,0,1), "У" },
    { BITS6(1,1,0,1,0,0), "Ф" },
    { BITS6(1,1,0,1,1,0), "Х" },
    { BITS6(1,1,0,1,0,1), "Ц" },
    { BITS6(1,1,0,1,1,1), "Ч" },
    { BITS6(1,0,1,1,0,1), "Ш" },
    { BITS6(1,0,1,1,1,1), "Щ" },
    { BITS6(1,0,1,0,1,1), "Ъ" },
    { BITS6(0,1,1,1,0,1), "Ы" },
    { BITS6(0,1,1,1,0,0), "Ь" },
    { BITS6(0,1,1,1,1,1), "Э" },
    { BITS6(1,1,1,1,0,1), "Ю" },
    { BITS6(1,1,1,0,0,1), "Я" },
    { BITS6(1,1,1,1,1,1), " " },
};

static const CellEntry ENG_TABLE[] = {
    { BITS6(1,0,0,0,0,0), "A" },
    { BITS6(1,1,0,0,0,0), "B" },
    { BITS6(1,0,0,1,0,0), "C" },
    { BITS6(1,0,0,1,1,0), "D" },
    { BITS6(1,0,0,0,1,0), "E" },
    { BITS6(1,1,0,1,0,0), "F" },
    { BITS6(1,1,0,1,1,0), "G" },
    { BITS6(1,1,0,0,1,0), "H" },
    { BITS6(0,1,0,1,0,0), "I" },
    { BITS6(0,1,0,1,1,0), "J" },
    { BITS6(1,0,1,0,0,0), "K" },
    { BITS6(1,1,1,0,0,0), "L" },
    { BITS6(1,0,1,1,0,0), "M" },
    { BITS6(1,0,1,1,1,0), "N" },
    { BITS6(1,0,1,0,1,0), "O" },
    { BITS6(1,1,1,1,0,0), "P" },
    { BITS6(1,1,1,1,1,0), "Q" },
    { BITS6(1,1,1,0,1,0), "R" },
    { BITS6(0,1,1,1,0,0), "S" },
    { BITS6(0,1,1,1,1,0), "T" },
    { BITS6(1,0,1,0,0,1), "U" },
    { BITS6(1,1,1,0,0,1), "V" },
    { BITS6(0,1,0,1,1,1), "W" },
    { BITS6(1,0,1,1,0,1), "X" },
    { BITS6(1,0,1,1,1,1), "Y" },
    { BITS6(1,0,1,0,1,1), "Z" },
    { BITS6(1,1,1,1,1,1), " " },
};

#undef BITS6

const char* decode(const Cell& c) {
    const CellEntry* table;
    size_t n;
    if (c.lang == 'R') {
        table = RUS_TABLE;
        n     = sizeof(RUS_TABLE) / sizeof(RUS_TABLE[0]);
    } else {
        table = ENG_TABLE;
        n     = sizeof(ENG_TABLE) / sizeof(ENG_TABLE[0]);
    }
    for (size_t i = 0; i < n; ++i) {
        if (table[i].bits == c.bits) return table[i].utf8;
    }
    return "?";
}

} // namespace braille
