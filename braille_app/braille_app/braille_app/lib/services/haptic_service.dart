import 'package:vibration/vibration.dart';

/// Короткие тактильные паттерны для обратной связи.
///
/// Для слепого пользователя вибрация — единственный быстрый невербальный канал
/// подтверждения действий. TalkBack тоже звучит, но он медленный.
class HapticService {
  static bool? _hasVibrator;

  static Future<bool> _canVibrate() async {
    _hasVibrator ??= await Vibration.hasVibrator() ?? false;
    return _hasVibrator!;
  }

  /// Короткое подтверждение (нажатие, действие выполнено).
  static Future<void> tap() async {
    if (!await _canVibrate()) return;
    Vibration.vibrate(duration: 30);
  }

  /// Успех — двойной короткий.
  static Future<void> success() async {
    if (!await _canVibrate()) return;
    Vibration.vibrate(pattern: [0, 40, 80, 40]);
  }

  /// Ошибка — длинный.
  static Future<void> error() async {
    if (!await _canVibrate()) return;
    Vibration.vibrate(duration: 250);
  }

  /// Сильное предупреждение/завершение операции.
  static Future<void> heavy() async {
    if (!await _canVibrate()) return;
    Vibration.vibrate(duration: 120);
  }
}
