import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// UUIDs Nordic UART Service — должны совпадать с прошивкой.
class _Uuids {
  static final service = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final rx      = Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E'); // app -> device (write)
  static final tx      = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E'); // device -> app (notify)
}

/// Состояние подключения, наблюдаемое UI.
enum BleConnState {
  disconnected,
  scanning,
  connecting,
  connected,
  failed,
}

/// Сервис управления BLE-устройством BrailleReader.
///
/// Возможности:
///   - Сканирование с фильтром по NUS service UUID.
///   - Подключение к выбранному устройству.
///   - Автоконнект к запомненному устройству (по remoteId/MAC).
///   - Отправка текстовых пакетов (с автоматической нарезкой по MTU).
///   - Подписка на TX-уведомления от устройства (статус, текущая буква).
///
/// Класс расширяет ChangeNotifier для биндинга с UI.
class BleService extends ChangeNotifier {
  BleConnState _state = BleConnState.disconnected;
  BleConnState get state => _state;

  BluetoothDevice? _device;
  BluetoothDevice? get device => _device;

  BluetoothCharacteristic? _rxChar;
  BluetoothCharacteristic? _txChar;

  /// Последнее уведомление от устройства (например, "POS 2/5 А" или "FINISHED").
  String _lastNotification = '';
  String get lastNotification => _lastNotification;

  /// Поток уведомлений от устройства — UI/TTS подписываются на него.
  final _notificationsController = StreamController<String>.broadcast();
  Stream<String> get notifications => _notificationsController.stream;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _notifySub;

  /// MAC-адрес последнего успешно подключённого устройства.
  /// Используется для автоконнекта при следующем запуске.
  String? lastKnownDeviceId;

  /// Установить состояние и оповестить слушателей.
  void _setState(BleConnState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  /// Поддерживается ли BLE на устройстве (и включён ли).
  Future<bool> isBluetoothAvailable() async {
    final supported = await FlutterBluePlus.isSupported;
    if (!supported) return false;
    final adapterState = await FlutterBluePlus.adapterState.first;
    return adapterState == BluetoothAdapterState.on;
  }

  /// Попросить пользователя включить Bluetooth (Android only).
  Future<void> turnOnBluetooth() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (_) {
      // Пользователь отказался — ничего не делаем, UI покажет статус.
    }
  }

  /// Сканировать BLE-устройства с NUS-сервисом.
  ///
  /// Возвращает первое найденное за `timeout` секунд устройство с правильным
  /// именем (или с правильным сервисом). Если найдено несколько — берём с
  /// сильнейшим сигналом.
  Future<BluetoothDevice?> scanForDevice({
    Duration timeout = const Duration(seconds: 8),
    String? expectedName,
  }) async {
    _setState(BleConnState.scanning);

    final found = <ScanResult>[];
    final completer = Completer<BluetoothDevice?>();

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        // Фильтруем по сервису ИЛИ по имени — некоторые BLE-устройства
        // не рекламируют сервис в advData, только в scan response.
        final hasService = r.advertisementData.serviceUuids.contains(_Uuids.service);
        final nameMatches = expectedName == null
            ? r.advertisementData.advName.toLowerCase().contains('braille')
            : r.advertisementData.advName == expectedName;
        if (hasService || nameMatches) {
          found.add(r);
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
      );
      // Ждём окончания скана
      await FlutterBluePlus.isScanning.where((s) => s == false).first;
    } catch (e) {
      _setState(BleConnState.failed);
      await _scanSub?.cancel();
      return null;
    }
    await _scanSub?.cancel();

    if (found.isEmpty) {
      _setState(BleConnState.disconnected);
      return null;
    }

    // Берём самый сильный сигнал.
    found.sort((a, b) => b.rssi.compareTo(a.rssi));
    return found.first.device;
  }

  /// Найти и подключиться к устройству, запомнить его.
  Future<bool> findAndConnect() async {
    final device = await scanForDevice();
    if (device == null) return false;
    return connect(device);
  }

  /// Попытаться подключиться к запомненному устройству по сохранённому ID.
  Future<bool> reconnectIfPossible() async {
    if (lastKnownDeviceId == null) return false;
    try {
      // Сначала проверим bonded-устройства (если ранее уже было сопряжено).
      final bonded = await FlutterBluePlus.bondedDevices;
      BluetoothDevice? device;
      for (final d in bonded) {
        if (d.remoteId.str == lastKnownDeviceId) {
          device = d;
          break;
        }
      }
      // Не нашли в bonded — сканируем.
      device ??= await scanForDevice();
      if (device == null || device.remoteId.str != lastKnownDeviceId) {
        // Если ID не совпал — всё равно попробуем подключиться к найденному,
        // вдруг пользователь сбросил спаривание.
        device = await scanForDevice();
      }
      if (device == null) return false;
      return connect(device);
    } catch (_) {
      return false;
    }
  }

  /// Подключиться к конкретному устройству.
  Future<bool> connect(BluetoothDevice device) async {
    _setState(BleConnState.connecting);

    // Старое соединение, если есть, разорвать.
    await _device?.disconnect();
    await _connSub?.cancel();
    await _notifySub?.cancel();

    _device = device;

    // Подписка на изменения состояния соединения (нужна чтобы реагировать
    // на удалённое отключение, ребут устройства и т.д.).
    _connSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        _setState(BleConnState.disconnected);
        _rxChar = null;
        _txChar = null;
      }
    });

    try {
      await device.connect(
        timeout: const Duration(seconds: 12),
        autoConnect: false,
      );
      // На Android после connect полезно запросить MTU побольше — иначе
      // максимум 23 байта (минус 3 на заголовок = 20 байт полезных).
      // 247 — практический максимум для большинства телефонов.
      try {
        await device.requestMtu(247);
      } catch (_) {
        // Не критично — продолжим с дефолтным MTU.
      }

      // Найти наш сервис и характеристики.
      final services = await device.discoverServices();
      BluetoothService? nus;
      for (final s in services) {
        if (s.uuid == _Uuids.service) {
          nus = s;
          break;
        }
      }
      if (nus == null) {
        await device.disconnect();
        _setState(BleConnState.failed);
        return false;
      }

      for (final c in nus.characteristics) {
        if (c.uuid == _Uuids.rx) _rxChar = c;
        if (c.uuid == _Uuids.tx) _txChar = c;
      }
      if (_rxChar == null || _txChar == null) {
        await device.disconnect();
        _setState(BleConnState.failed);
        return false;
      }

      // Подписаться на уведомления от устройства.
      await _txChar!.setNotifyValue(true);
      _notifySub = _txChar!.lastValueStream.listen((bytes) {
        if (bytes.isEmpty) return;
        try {
          final msg = utf8.decode(bytes, allowMalformed: true).trim();
          if (msg.isEmpty) return;
          _lastNotification = msg;
          _notificationsController.add(msg);
          notifyListeners();
        } catch (_) {
          // Битые байты — игнор.
        }
      });

      lastKnownDeviceId = device.remoteId.str;
      _setState(BleConnState.connected);
      return true;
    } catch (e) {
      _setState(BleConnState.failed);
      return false;
    }
  }

  /// Разорвать соединение.
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    await _connSub?.cancel();
    await _device?.disconnect();
    _device = null;
    _rxChar = null;
    _txChar = null;
    _setState(BleConnState.disconnected);
  }

  /// Отправить текст (уже в виде токенов "R_111000 ...") в устройство.
  ///
  /// Автоматически нарезает на чанки по MTU и добавляет терминатор '\n' в конце.
  Future<bool> sendText(String tokens) async {
    if (_rxChar == null || _state != BleConnState.connected) return false;

    final payload = '$tokens\n';
    final bytes = utf8.encode(payload);

    // Размер чанка: MTU - 3 байта ATT-заголовка. Запросили 247 -> 244 полезных.
    // Если не удалось поднять MTU — flutter_blue_plus вернёт 23, тогда 20.
    final mtu = _device?.mtuNow ?? 23;
    final chunkSize = (mtu - 3).clamp(20, 512);

    try {
      for (var i = 0; i < bytes.length; i += chunkSize) {
        final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        await _rxChar!.write(
          bytes.sublist(i, end),
          withoutResponse: false, // надёжная доставка для коротких пакетов
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Послать команду STOP устройству.
  Future<bool> stopReading() async {
    return sendText('STOP');
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _notifySub?.cancel();
    _notificationsController.close();
    _device?.disconnect();
    super.dispose();
  }
}
