#pragma once

#include <Arduino.h>
#include "Config.h"
#include "../hal/ShiftRegisterChain.h"

/**
 * Банк из 6 биполярных шаговиков, управляемых DRV8833 через каскад 74HC595.
 *
 * Раскладка пинов DRV8833 в нашем 24-битном выходе:
 *   Мотор 0: биты [0..3]  -> Q0..Q3 чипа 0
 *   Мотор 1: биты [4..7]  -> Q4..Q7 чипа 0
 *   Мотор 2: биты [8..11] -> Q0..Q3 чипа 1
 *   ...
 *
 * Внутри ниббла: bit0=AIN1, bit1=AIN2, bit2=BIN1, bit3=BIN2
 *
 * Полношаговая последовательность (две катушки одновременно — момент выше,
 * критично для маленьких моторов, ворочающих эксцентрик):
 *   phase 0: AIN1+BIN1 -> 0b0101
 *   phase 1: AIN1+BIN2 -> 0b1001
 *   phase 2: AIN2+BIN2 -> 0b1010
 *   phase 3: AIN2+BIN1 -> 0b0110
 *
 * Каждый мотор хранит:
 *   - currentSteps: текущая виртуальная позиция (0 = точка внизу)
 *   - targetSteps:  целевая позиция, к которой стремится драйвер
 *   - phase:        текущая фаза 0..3
 *
 * Метод tick() вызывается из loop() — он сам решает, прошло ли STEP_PERIOD_US
 * с прошлого шага, и делает один шаг каждому мотору, у которого current != target.
 *
 * Состояние выхода защёлкивается одним flush() — все 6 моторов обновляются
 * одновременно.
 */
class StepperBank {
public:
    void begin() {
        chain_.begin();
        for (uint8_t i = 0; i < motors::COUNT; ++i) {
            state_[i] = {};
        }
        lastStepMicros_ = micros();
        rewriteOutputs();
    }

    /// Цель = «точка поднята» (true) или «точка опущена» (false).
    void setDotTarget(uint8_t motorIdx, bool raised) {
        if (motorIdx >= motors::COUNT) return;
        state_[motorIdx].targetSteps = raised ? motors::STEPS_PER_DOT : 0;
    }

    /// Установить цели для всех 6 точек разом из паттерна (массив 6 bool).
    void setPattern(const bool dots[motors::COUNT]) {
        for (uint8_t i = 0; i < motors::COUNT; ++i) {
            state_[i].targetSteps = dots[i] ? motors::STEPS_PER_DOT : 0;
        }
    }

    /// Все точки вниз. Эквивалент пустой Брайль-ячейки.
    void releaseAll() {
        for (uint8_t i = 0; i < motors::COUNT; ++i) {
            state_[i].targetSteps = 0;
        }
    }

    /// Все моторы достигли своих целей?
    bool isIdle() const {
        for (uint8_t i = 0; i < motors::COUNT; ++i) {
            if (state_[i].currentSteps != state_[i].targetSteps) return false;
        }
        return true;
    }

    /**
     * Полностью обесточить катушки (все выходы DRV8833 = LOW).
     * Использовать когда устройство простаивает — экономит ток, не греет моторы.
     * Эксцентрик удержит точку механически (это ключевое преимущество эксцентрика).
     */
    void deenergize() {
        chain_.clear();
        chain_.flush();
        deenergized_ = true;
    }

    /// Главный тик — вызывать из loop() как можно чаще.
    void tick() {
        const uint32_t now = micros();
        const uint32_t period = homing_ ? motors::HOMING_PERIOD_US : motors::STEP_PERIOD_US;

        if ((uint32_t)(now - lastStepMicros_) < period) return;
        lastStepMicros_ = now;

        bool anyMoved = false;
        for (uint8_t i = 0; i < motors::COUNT; ++i) {
            auto& m = state_[i];
            if (m.currentSteps == m.targetSteps) continue;

            if (m.currentSteps < m.targetSteps) {
                m.phase = (m.phase + 1) & 0x3;
                m.currentSteps++;
            } else {
                m.phase = (m.phase + 3) & 0x3; // -1 mod 4
                m.currentSteps--;
            }
            anyMoved = true;
        }

        if (anyMoved) {
            rewriteOutputs();
            deenergized_ = false;
        }
    }

    // ----- ХОУМИНГ ---------------------------------------------------------
    //
    // Так как нет концевиков, делаем "soft homing": крутим все моторы в
    // отрицательную сторону на HOMING_STEPS шагов, эксцентрик встаёт в "низ".
    // Если эксцентрик уже был внизу — мотор просто провернёт его лишний раз
    // (эксцентрик это допускает, у него нет жёсткого упора).
    // По окончании сбрасываем виртуальную позицию в 0.

    void startHoming() {
        homing_ = true;
        homingStepsLeft_ = motors::HOMING_STEPS;
        lastStepMicros_ = micros();
    }

    /// Если идёт хоуминг — продвинуть его. Возвращает true когда завершено.
    bool tickHoming() {
        if (!homing_) return true;

        const uint32_t now = micros();
        if ((uint32_t)(now - lastStepMicros_) < motors::HOMING_PERIOD_US) return false;
        lastStepMicros_ = now;

        if (homingStepsLeft_ == 0) {
            // Закончили — обнуляем виртуальные координаты
            for (uint8_t i = 0; i < motors::COUNT; ++i) {
                state_[i].currentSteps = 0;
                state_[i].targetSteps  = 0;
            }
            homing_ = false;
            deenergize();
            return true;
        }

        // Шаг в "минус" для всех моторов
        for (uint8_t i = 0; i < motors::COUNT; ++i) {
            state_[i].phase = (state_[i].phase + 3) & 0x3;
        }
        rewriteOutputs();
        homingStepsLeft_--;
        return false;
    }

    bool isHoming() const { return homing_; }

private:
    // Полношаговая таблица. Индекс = фаза 0..3. Значение = ниббл, биты AIN1|AIN2|BIN1|BIN2.
    //
    // ВАЖНО: если при тестировании мотор гудит/дрожит, но не вращается, либо
    // вращается рывками — скорее всего перепутаны провода катушек. Поменять
    // местами катушку A или B (физически), либо в таблице поменять биты 0<->1
    // (катушка A) или биты 2<->3 (катушка B).
    static constexpr uint8_t STEP_TABLE[4] = {
        0b0101, // AIN1=1, BIN1=1   (A+, B+)
        0b1001, // AIN2=1, BIN1=1   (A-, B+)
        0b1010, // AIN2=1, BIN2=1   (A-, B-)
        0b0110, // AIN1=1, BIN2=1   (A+, B-)
    };

    struct MotorState {
        uint16_t currentSteps = 0;
        uint16_t targetSteps  = 0;
        uint8_t  phase        = 0;
    };

    /// Собрать байты из текущих фаз и протолкнуть в регистры.
    void rewriteOutputs() {
        for (uint8_t chip = 0; chip < motors::CHIPS; ++chip) {
            const uint8_t motorLo = chip * 2;
            const uint8_t motorHi = motorLo + 1;
            const uint8_t lo = STEP_TABLE[state_[motorLo].phase];
            const uint8_t hi = STEP_TABLE[state_[motorHi].phase];
            chain_.setByte(chip, lo | (hi << 4));
        }
        chain_.flush();
    }

    ShiftRegisterChain<motors::CHIPS> chain_;
    MotorState state_[motors::COUNT];

    uint32_t lastStepMicros_ = 0;
    bool     homing_ = false;
    bool     deenergized_ = false;
    uint16_t homingStepsLeft_ = 0;
};

// Определение constexpr-массива (для C++14/17 совместимости)
constexpr uint8_t StepperBank::STEP_TABLE[4];
