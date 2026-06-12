#pragma once

#include <Arduino.h>
#include "Config.h"

/**
 * Каскад из N 74HC595 (LSB первого чипа = бит 0, MSB последнего чипа = старший бит).
 *
 * Внутри хранит «теневое» состояние всех выходов. Менять биты через set()/clear(),
 * физическая запись происходит при flush().
 *
 * Не блокирующий по природе — flush() стоит ~150 мкс для 3 чипов на bit-bang
 * на 80 МГц C3, что приемлемо для нашего шагового цикла (2 мс между шагами).
 */
template <uint8_t NUM_CHIPS>
class ShiftRegisterChain {
public:
    static constexpr uint8_t NUM_BITS = NUM_CHIPS * 8;

    void begin() {
        pinMode(pins::SHIFT_DATA,  OUTPUT);
        pinMode(pins::SHIFT_CLOCK, OUTPUT);
        pinMode(pins::SHIFT_LATCH, OUTPUT);
        digitalWrite(pins::SHIFT_DATA,  LOW);
        digitalWrite(pins::SHIFT_CLOCK, LOW);
        digitalWrite(pins::SHIFT_LATCH, LOW);

        for (auto& b : buffer_) b = 0;
        flush();
    }

    /// Установить бит (0..NUM_BITS-1).
    inline void setBit(uint8_t bit, bool value) {
        const uint8_t byte = bit / 8;
        const uint8_t mask = 1u << (bit % 8);
        if (value) buffer_[byte] |=  mask;
        else       buffer_[byte] &= ~mask;
    }

    /// Записать целый байт в конкретный чип.
    inline void setByte(uint8_t chipIdx, uint8_t value) {
        if (chipIdx < NUM_CHIPS) buffer_[chipIdx] = value;
    }

    /// Сбросить всё в 0 (моторы остановлены).
    void clear() {
        for (auto& b : buffer_) b = 0;
    }

    /// Физически вытолкнуть теневой буфер в регистры и защёлкнуть.
    void flush() {
        // Сдвигаем начиная с последнего чипа (он "продавливается" дальше всех),
        // внутри каждого байта — MSB first.
        for (int8_t chip = NUM_CHIPS - 1; chip >= 0; --chip) {
            const uint8_t b = buffer_[chip];
            for (int8_t bit = 7; bit >= 0; --bit) {
                digitalWrite(pins::SHIFT_CLOCK, LOW);
                digitalWrite(pins::SHIFT_DATA,  (b >> bit) & 1);
                digitalWrite(pins::SHIFT_CLOCK, HIGH);
            }
        }
        // Защёлка
        digitalWrite(pins::SHIFT_LATCH, LOW);
        digitalWrite(pins::SHIFT_LATCH, HIGH);
        digitalWrite(pins::SHIFT_LATCH, LOW);
    }

private:
    uint8_t buffer_[NUM_CHIPS] = {};
};
