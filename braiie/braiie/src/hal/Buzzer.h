#pragma once

#include <Arduino.h>
#include "Config.h"

/**
 * Простой неблокирующий buzzer. tone() на ESP32 сам по себе асинхронный
 * (использует LEDC), поэтому ничего хитрого здесь не нужно.
 *
 * Метод beep() запускает сигнал и сразу возвращает управление.
 */
class Buzzer {
public:
    void begin() {
        pinMode(pins::BUZZER, OUTPUT);
        digitalWrite(pins::BUZZER, LOW);
    }

    /// Короткий писк (неблокирующий).
    void beep(uint16_t freq = buzzer::TONE_OK, uint16_t durationMs = buzzer::DUR_SHORT_MS) {
        tone(pins::BUZZER, freq, durationMs);
    }

    /// Двойной писк — для смены направления.
    void doubleBeep(uint16_t freq = buzzer::TONE_OK) {
        beep(freq, buzzer::DUR_SHORT_MS);
        // Здесь короткая блокировка нужна — чтобы tone() успел отыграть и сбросить.
        // 80 мс на старте чтения буквы — незаметно.
        delay(buzzer::DUR_SHORT_MS + 30);
        beep(freq, buzzer::DUR_SHORT_MS);
    }

    /// Длинный сигнал — конец текста.
    void finish() {
        beep(buzzer::TONE_FINISH, buzzer::DUR_LONG_MS);
    }

    /// Сигнал границы (попытка листать дальше начала/конца).
    void border() {
        beep(buzzer::TONE_BORDER, buzzer::DUR_SHORT_MS);
    }

    /// Стартовая мелодия.
    void boot() {
        for (uint8_t i = 0; i < 3; ++i) {
            tone(pins::BUZZER, buzzer::TONE_BOOT, 60);
            delay(90);
        }
    }
};
