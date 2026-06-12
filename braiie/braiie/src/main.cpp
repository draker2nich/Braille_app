// ============================================================================
//                  BrailleReader — главный файл
// ----------------------------------------------------------------------------
// ESP32-C3 + 3x 74HC595 + 6x DRV8833 + 6 шаговиков + 2 кнопки + buzzer + BLE.
//
// Поток работы:
//   1. BOOT:    инициализация, стартовая мелодия.
//   2. HOMING:  крутим все моторы вниз ("soft homing" эксцентриков).
//   3. IDLE:    ждём подключения по BLE и приёма текста.
//   4. PLAYING: показываем текущую букву, ждём нажатий кнопок.
//      - FWD short  -> следующая буква
//      - BACK short -> предыдущая буква
//      - BACK long  -> остановить, обесточить, вернуться в IDLE
//      - конец текста -> длинный писк, ждать ещё нажатия (вернётся в IDLE по BACK long).
// ============================================================================

#include <Arduino.h>
#include "Config.h"

#include "hal/Buzzer.h"
#include "motors/StepperBank.h"
#include "input/Buttons.h"
#include "braille/BrailleCodec.h"
#include "braille/TextPlayer.h"
#include "ble/BleService.h"

// ---------------------------------------------------------------------------
//                            ГЛОБАЛЬНЫЕ КОМПОНЕНТЫ
// ---------------------------------------------------------------------------
// Делаются глобальными сознательно: их по одному в системе, время жизни =
// время жизни устройства, передача указателей в Arduino-стиле через колбэки
// проще именно так. RAII здесь не нужен.

static StepperBank g_motors;
static Buttons     g_buttons;
static Buzzer      g_buzzer;
static TextPlayer  g_player;
static BleService  g_ble;

enum class State : uint8_t { BOOT, HOMING, IDLE, PLAYING };
static State g_state = State::BOOT;

// Флаг "моторы достигли цели и обесточены" в состоянии PLAYING.
// Сбрасывается при каждом перелистывании.
static bool g_settled = false;

// ---------------------------------------------------------------------------
//                                  HELPERS
// ---------------------------------------------------------------------------

static void applyCurrentCellToMotors() {
    bool dots[braille::DOTS];
    braille::cellToDots(g_player.currentCell(), dots);
    g_motors.setPattern(dots);
}

/// Сообщить приложению текущее состояние (если оно подключено).
static void notifyClient(const char* fmt, ...) {
    if (!g_ble.isConnected()) return;
    char buf[96];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    g_ble.notify(buf);
}

// ---------------------------------------------------------------------------
//                       КОЛБЭК: BLE принял сообщение
// ---------------------------------------------------------------------------

static void onBleMessage(const char* data, size_t len) {
    // Команды управления
    if (len >= 4 && strncmp(data, "STOP", 4) == 0) {
        g_player.clear();
        g_motors.releaseAll();
        g_state = State::IDLE;
        notifyClient("STOPPED");
        return;
    }

    // Иначе — это поток токенов брайля
    const size_t parsed = g_player.load(data, len);
    if (parsed == 0) {
        notifyClient("ERR: no tokens");
        return;
    }

    applyCurrentCellToMotors();
    g_settled = false;
    g_state = State::PLAYING;

    notifyClient("LOADED %u POS 1", (unsigned)parsed);
    g_buzzer.beep(buzzer::TONE_OK);
}

// ---------------------------------------------------------------------------
//                                  SETUP
// ---------------------------------------------------------------------------

void setup() {
    Serial.begin(115200);
    delay(100);
    log_i("BrailleReader booting...");

    g_buzzer.begin();
    g_motors.begin();
    g_buttons.begin();
    g_ble.begin(onBleMessage);

    g_buzzer.boot();

    g_motors.startHoming();
    g_state = State::HOMING;

    log_i("Setup done, homing started");
}

// ---------------------------------------------------------------------------
//                                   LOOP
// ---------------------------------------------------------------------------

static void handleButtonsPlaying(Buttons::Event ev) {
    switch (ev) {
        case Buttons::Event::FWD_SHORT: {
            auto r = g_player.next();
            if (r == TextPlayer::StepResult::MOVED) {
                applyCurrentCellToMotors();
                notifyClient("POS %u/%u %s",
                             (unsigned)(g_player.cursor() + 1),
                             (unsigned)g_player.size(),
                             braille::decode(g_player.currentCell()));
            } else if (r == TextPlayer::StepResult::FINISHED) {
                g_buzzer.finish();
                notifyClient("FINISHED");
                // Оставляем последнюю букву на моторах; ждём BACK_LONG для выхода.
            }
            break;
        }
        case Buttons::Event::BACK_SHORT: {
            auto r = g_player.prev();
            if (r == TextPlayer::StepResult::MOVED) {
                applyCurrentCellToMotors();
                notifyClient("POS %u/%u %s",
                             (unsigned)(g_player.cursor() + 1),
                             (unsigned)g_player.size(),
                             braille::decode(g_player.currentCell()));
            } else {
                g_buzzer.border();
            }
            break;
        }
        case Buttons::Event::BACK_LONG: {
            g_player.clear();
            g_motors.releaseAll();
            g_buzzer.doubleBeep(buzzer::TONE_OK);
            notifyClient("STOPPED");
            g_state = State::IDLE;
            break;
        }
        case Buttons::Event::FWD_LONG:
            // Не задействовано, оставим на будущее (например, "повторить с начала").
            break;
        case Buttons::Event::NONE:
            break;
    }
}

void loop() {
    g_ble.tick();

    switch (g_state) {
        case State::BOOT:
            // Перетекает в HOMING из setup(), сюда не попадаем.
            break;

        case State::HOMING:
            if (g_motors.tickHoming()) {
                g_state = State::IDLE;
                g_buzzer.beep(buzzer::TONE_OK);
                log_i("Homing complete");
            }
            break;

        case State::IDLE:
            // Моторы стоят, ждём BLE. Можно слегка отдохнуть.
            g_motors.tick(); // на всякий случай (если кто-то задал targets)
            break;

        case State::PLAYING:
            g_motors.tick();
            // Кнопки обрабатываем только когда моторы достигли цели —
            // иначе пользователь будет давить вперёд раньше, чем точка поднялась.
            if (g_motors.isIdle()) {
                // Точки на месте — обесточим катушки (эксцентрик удержит позицию,
                // моторы не греются, ток ~0). Делаем это ОДИН раз при переходе
                // в idle, чтобы не дёргать SPI каждый цикл.
                if (!g_settled) {
                    g_motors.deenergize();
                    g_settled = true;
                }
                Buttons::Event ev = g_buttons.poll();
                if (ev != Buttons::Event::NONE) {
                    g_settled = false;   // следующая буква снова заведёт моторы
                    handleButtonsPlaying(ev);
                }
            }
            break;
    }
}
