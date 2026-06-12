#pragma once

#include <Arduino.h>
#include "../Config.h"

/**
 * Nordic UART Service (NUS) поверх NimBLE.
 *
 * Поведение:
 *   - Устройство рекламирует имя ble::DEVICE_NAME.
 *   - При коннекте клиента (телефон) можно писать в RX-характеристику текст
 *     (поток токенов "R_111100 E_101010 ...").
 *   - Принимаемые куски аккумулируются в rxBuffer_ до прихода '\n' или ';',
 *     либо до закрытия соединения. На каждую "завершённую посылку"
 *     вызывается onMessage_.
 *   - В TX-характеристику можно слать notify для отчёта о состоянии в приложение
 *     (например, текущая буква).
 *
 * Зависимости: библиотека h2zero/NimBLE-Arduino (в platformio через lib_deps).
 */

#include <NimBLEDevice.h>

class BleService {
public:
    using MessageCallback = void(*)(const char* data, size_t len);

    void begin(MessageCallback cb) {
        onMessage_ = cb;
        rxLen_ = 0;

        NimBLEDevice::init(ble::DEVICE_NAME);
        // На C3 MTU крупный не получится, ставим разумный максимум —
        // NimBLE сам обсчитает реальный.
        NimBLEDevice::setMTU(247);
        NimBLEDevice::setPower(ESP_PWR_LVL_P9);

        server_ = NimBLEDevice::createServer();
        server_->setCallbacks(new ServerCallbacks(this));

        NimBLEService* svc = server_->createService(ble::SERVICE_UUID);

        rxChar_ = svc->createCharacteristic(
            ble::RX_CHAR_UUID,
            NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
        );
        rxChar_->setCallbacks(new RxCallbacks(this));

        txChar_ = svc->createCharacteristic(
            ble::TX_CHAR_UUID,
            NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::READ
        );

        svc->start();

        NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
        adv->addServiceUUID(svc->getUUID());
        adv->enableScanResponse(true);
        adv->setName(ble::DEVICE_NAME);
        adv->start();
    }

    bool isConnected() const { return connected_; }

    /// Отправить уведомление клиенту (UTF-8 строка).
    void notify(const char* msg) {
        if (!connected_ || !txChar_) return;
        txChar_->setValue((const uint8_t*)msg, strlen(msg));
        txChar_->notify();
    }

private:
    // ----- Колбэки сервера: коннект/дисконнект --------------------------------
    class ServerCallbacks : public NimBLEServerCallbacks {
    public:
        explicit ServerCallbacks(BleService* o) : owner_(o) {}
        void onConnect(NimBLEServer* /*s*/, NimBLEConnInfo& /*info*/) override {
            owner_->connected_ = true;
        }
        void onDisconnect(NimBLEServer* s, NimBLEConnInfo& /*info*/, int /*reason*/) override {
            owner_->connected_ = false;
            owner_->rxLen_ = 0;
            // Перезапустить рекламу — иначе после первого дисконнекта
            // устройство станет невидимым.
            NimBLEDevice::getAdvertising()->start();
        }
    private:
        BleService* owner_;
    };

    // ----- Колбэк RX характеристики: входящие данные --------------------------
    class RxCallbacks : public NimBLECharacteristicCallbacks {
    public:
        explicit RxCallbacks(BleService* o) : owner_(o) {}
        void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& /*info*/) override {
            const std::string& v = c->getValue();
            owner_->handleIncoming(v.data(), v.size());
        }
    private:
        BleService* owner_;
    };

    void handleIncoming(const char* data, size_t len) {
        for (size_t i = 0; i < len; ++i) {
            const char ch = data[i];
            const bool terminator = (ch == '\n' || ch == ';');
            if (terminator) {
                flushMessage();
                continue;
            }
            if (ch == '\r') continue;  // игнорируем CR

            if (rxLen_ < ble::MAX_TEXT_LEN - 1) {
                rxBuffer_[rxLen_++] = ch;
            } else {
                // Переполнение — сброс
                rxLen_ = 0;
            }
        }
        // Если клиент не послал терминатор — всё равно попробуем обработать
        // текущий буфер после небольшой паузы (см. tick).
        lastChunkMs_ = millis();
    }

    void flushMessage() {
        if (rxLen_ == 0) return;
        rxBuffer_[rxLen_] = '\0';
        if (onMessage_) onMessage_(rxBuffer_, rxLen_);
        rxLen_ = 0;
    }

public:
    /// Вызывать из loop(): если давно нет новых байт — флашим буфер.
    /// Это нужно потому что в BLE нет гарантированной "конца пакета".
    void tick() {
        if (rxLen_ > 0 && (millis() - lastChunkMs_) > 150) {
            flushMessage();
        }
    }

private:
    NimBLEServer*         server_ = nullptr;
    NimBLECharacteristic* rxChar_ = nullptr;
    NimBLECharacteristic* txChar_ = nullptr;

    MessageCallback onMessage_ = nullptr;
    bool connected_ = false;

    char     rxBuffer_[ble::MAX_TEXT_LEN];
    size_t   rxLen_ = 0;
    uint32_t lastChunkMs_ = 0;
};
