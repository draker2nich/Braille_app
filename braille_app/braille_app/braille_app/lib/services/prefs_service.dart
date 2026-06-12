import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  static const _kLastDeviceId = 'last_device_id';

  static Future<String?> getLastDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastDeviceId);
  }

  static Future<void> setLastDeviceId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastDeviceId, id);
  }

  static Future<void> clearLastDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastDeviceId);
  }
}
