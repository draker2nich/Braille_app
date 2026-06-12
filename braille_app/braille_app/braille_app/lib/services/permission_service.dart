import 'package:permission_handler/permission_handler.dart';

/// Группированный запрос разрешений на старте.
///
/// На Android 12+ для BLE нужны BLUETOOTH_SCAN + BLUETOOTH_CONNECT.
/// На Android < 12 — ACCESS_FINE_LOCATION + BLUETOOTH/BLUETOOTH_ADMIN.
/// Для голосового ввода — RECORD_AUDIO.
class PermissionService {
  /// Запросить все необходимые разрешения. Возвращает true если все даны.
  static Future<bool> requestAll() async {
    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse, // для старых Android
      Permission.microphone,
    ];

    final statuses = await permissions.request();
    // Учитываем что на новых Android некоторые из перечисленных
    // вернутся как granted "автоматически" (т.к. не нужны на этой версии).
    final bleScan = statuses[Permission.bluetoothScan];
    final bleConnect = statuses[Permission.bluetoothConnect];
    final mic = statuses[Permission.microphone];

    // BLE-доступ обязателен. Микрофон — желательно, но без него можно работать
    // (только текстовый ввод).
    final bleOk = (bleScan?.isGranted ?? false) &&
                  (bleConnect?.isGranted ?? false);
    // Микрофон проверяем отдельно через UI при нажатии на кнопку голоса.
    return bleOk;
  }

  static Future<bool> hasMicrophone() async {
    return await Permission.microphone.isGranted;
  }

  static Future<bool> requestMicrophone() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }
}
