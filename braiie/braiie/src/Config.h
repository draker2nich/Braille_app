#pragma once

#include <Arduino.h>

// ============================================================================
//                              ПИНЫ ESP32-C3
// ============================================================================

namespace pins {
    // 74HC595 каскад (3 чипа = 24 выхода = 6 моторов × 4 пина DRV8833)
    constexpr uint8_t SHIFT_DATA  = 20;   // SER  / DS
    constexpr uint8_t SHIFT_CLOCK = 10;   // SRCLK
    constexpr uint8_t SHIFT_LATCH = 5;    // RCLK / STCP

    // Кнопки (активный LOW, подтяжка к +)
    constexpr uint8_t BTN_FORWARD = 4;    // следующая буква
    constexpr uint8_t BTN_BACK    = 3;    // предыдущая буква / long press = стоп

    // Buzzer (пассивный, через tone())
    constexpr uint8_t BUZZER      = 6;
}

// ============================================================================
//                          КОНСТАНТЫ ШАГОВЫХ МОТОРОВ
// ============================================================================

namespace motors {
    constexpr uint8_t  COUNT              = 6;
    constexpr uint8_t  CHIPS              = 3;     // 3× 74HC595

    // Сколько шагов от «точка опущена» до «точка поднята».
    // Подбирается экспериментально под эксцентрик.
    constexpr uint16_t STEPS_PER_DOT      = 50;

    // Запас шагов при хоуминге (на случай если эксцентрик был наверху).
    // Крутим вниз на полный диапазон + запас, чтобы гарантированно упасть в «низ».
    constexpr uint16_t HOMING_STEPS       = STEPS_PER_DOT * 2;

    // Период между шагами (мкс). Меньше — быстрее, но мотор может пропускать шаги.
    constexpr uint32_t STEP_PERIOD_US     = 2000;

    // Период хоуминга — можно медленнее, для надёжности
    constexpr uint32_t HOMING_PERIOD_US   = 2500;
}

// ============================================================================
//                                КНОПКИ
// ============================================================================

namespace buttons {
    constexpr uint32_t DEBOUNCE_MS    = 30;
    constexpr uint32_t LONG_PRESS_MS  = 1500;
}

// ============================================================================
//                                BUZZER
// ============================================================================

namespace buzzer {
    constexpr uint16_t TONE_OK        = 1500;   // подтверждение действия
    constexpr uint16_t TONE_BORDER    = 800;    // достигнут край текста
    constexpr uint16_t TONE_FINISH    = 1800;   // конец текста
    constexpr uint16_t TONE_BOOT      = 1200;   // старт устройства

    constexpr uint16_t DUR_SHORT_MS   = 80;
    constexpr uint16_t DUR_LONG_MS    = 400;
}

// ============================================================================
//                                  BLE
// ============================================================================

namespace ble {
    // Nordic UART Service (NUS) — стандартные UUID, поддерживаются всеми
    // BLE-терминалами и Flutter-пакетами (flutter_blue_plus, reactive_ble).
    constexpr const char* SERVICE_UUID  = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
    constexpr const char* RX_CHAR_UUID  = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"; // app -> device
    constexpr const char* TX_CHAR_UUID  = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"; // device -> app

    constexpr const char* DEVICE_NAME   = "BrailleReader";

    constexpr size_t MAX_TEXT_LEN       = 4096;
}
