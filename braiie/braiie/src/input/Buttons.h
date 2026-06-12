#pragma once

#include <Arduino.h>
#include "Config.h"

/**
 * Двухкнопочный обработчик с дебаунсом и детектом long press.
 *
 * Семантика событий:
 *   - SHORT_PRESS: кнопка нажата и отпущена меньше чем за LONG_PRESS_MS.
 *     Событие генерируется при отпускании.
 *   - LONG_PRESS:  кнопка удерживается дольше LONG_PRESS_MS.
 *     Событие генерируется ОДИН РАЗ в момент пересечения порога,
 *     до отпускания. После отпускания SHORT_PRESS не генерируется.
 *
 * Все методы не блокирующие. poll() вызывать из loop().
 */
class Buttons {
public:
    enum class Event : uint8_t {
        NONE,
        FWD_SHORT,
        FWD_LONG,
        BACK_SHORT,
        BACK_LONG,
    };

    void begin() {
        pinMode(pins::BTN_FORWARD, INPUT_PULLUP);
        pinMode(pins::BTN_BACK,    INPUT_PULLUP);
        fwd_  = makeState();
        back_ = makeState();
    }

    /// Опросить кнопки. Возвращает очередное событие или NONE.
    Event poll() {
        Event e = pollOne(fwd_,  pins::BTN_FORWARD, Event::FWD_SHORT,  Event::FWD_LONG);
        if (e != Event::NONE) return e;
        return    pollOne(back_, pins::BTN_BACK,    Event::BACK_SHORT, Event::BACK_LONG);
    }

private:
    struct State {
        bool     lastRaw         = HIGH;
        bool     stable          = HIGH;     // дебаунснутое
        uint32_t lastChangeMs    = 0;
        uint32_t pressStartMs    = 0;
        bool     longFired       = false;    // событие LONG уже выдано в этом нажатии
    };

    static State makeState() { return State{}; }

    Event pollOne(State& s, uint8_t pin, Event shortEv, Event longEv) {
        const bool raw = digitalRead(pin);
        const uint32_t now = millis();

        // Дебаунс по фронту
        if (raw != s.lastRaw) {
            s.lastRaw = raw;
            s.lastChangeMs = now;
            return Event::NONE;
        }

        // Стабильное значение
        if ((now - s.lastChangeMs) < buttons::DEBOUNCE_MS) return Event::NONE;
        if (raw == s.stable) {
            // Удержание — проверим долгое нажатие
            if (s.stable == LOW && !s.longFired
                && (now - s.pressStartMs) >= buttons::LONG_PRESS_MS) {
                s.longFired = true;
                return longEv;
            }
            return Event::NONE;
        }

        // Зафиксировали смену стабильного состояния
        s.stable = raw;
        if (s.stable == LOW) {
            // Нажатие
            s.pressStartMs = now;
            s.longFired    = false;
            return Event::NONE;
        } else {
            // Отпускание. Если LONG уже отыграл — событие подавляем.
            if (s.longFired) {
                s.longFired = false;
                return Event::NONE;
            }
            return shortEv;
        }
    }

    State fwd_;
    State back_;
};
