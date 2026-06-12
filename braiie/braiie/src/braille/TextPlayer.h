#pragma once

#include <Arduino.h>
#include "BrailleCodec.h"
#include "../Config.h"

/**
 * Хранит распарсенный текст как массив Брайль-ячеек и положение курсора.
 *
 * Не управляет моторами напрямую — main.cpp вытаскивает текущую ячейку
 * через currentCell() и отдаёт её StepperBank.
 *
 * Память: статический буфер на MAX_CELLS ячеек. 4 КБ текста на BLE-приёме
 * = максимум 4096/8 ≈ 512 токенов = 512 ячеек × 2 байта = 1 КБ. Влезает с запасом.
 */
class TextPlayer {
public:
    static constexpr size_t MAX_CELLS = 768;

    /// Загрузить новый текст. data — строка токенов через пробел/перевод строки.
    /// Возвращает количество распарсенных ячеек.
    size_t load(const char* data, size_t len) {
        count_  = 0;
        cursor_ = 0;
        finished_ = false;

        size_t i = 0;
        while (i < len && count_ < MAX_CELLS) {
            // Пропускаем разделители
            while (i < len && (data[i] == ' ' || data[i] == '\n' || data[i] == '\r' || data[i] == '\t')) {
                ++i;
            }
            if (i >= len) break;

            // Находим конец токена
            size_t start = i;
            while (i < len && data[i] != ' ' && data[i] != '\n'
                          && data[i] != '\r' && data[i] != '\t') {
                ++i;
            }

            braille::Cell c;
            if (braille::parseToken(data + start, i - start, c)) {
                cells_[count_++] = c;
            }
            // Некорректные токены молча игнорируются
        }
        return count_;
    }

    void clear() {
        count_ = 0;
        cursor_ = 0;
        finished_ = false;
    }

    bool isEmpty() const { return count_ == 0; }
    size_t size() const { return count_; }
    size_t cursor() const { return cursor_; }
    bool isFinished() const { return finished_; }

    /// Текущая ячейка под курсором. Безопасно вызывать когда !isEmpty().
    const braille::Cell& currentCell() const { return cells_[cursor_]; }

    /// Результат попытки сдвинуть курсор.
    enum class StepResult : uint8_t {
        MOVED,          // курсор успешно сдвинулся
        BORDER_START,   // попытка уйти за начало
        FINISHED,       // дошли до конца текста
    };

    StepResult next() {
        if (count_ == 0) return StepResult::BORDER_START;
        if (cursor_ + 1 < count_) {
            ++cursor_;
            return StepResult::MOVED;
        }
        finished_ = true;
        return StepResult::FINISHED;
    }

    StepResult prev() {
        if (count_ == 0) return StepResult::BORDER_START;
        if (cursor_ == 0) return StepResult::BORDER_START;
        --cursor_;
        finished_ = false;
        return StepResult::MOVED;
    }

private:
    braille::Cell cells_[MAX_CELLS];
    size_t count_   = 0;
    size_t cursor_  = 0;
    bool   finished_ = false;
};
