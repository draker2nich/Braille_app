import 'package:flutter_tts/flutter_tts.dart';

/// Озвучивает короткие статусные сообщения слепому пользователю.
///
/// Все сообщения короткие — это инструмент обратной связи, а не чтение текста.
/// Долгие сообщения раздражают, особенно если пользователь и так в курсе
/// что произошло.
class SpeechService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  String _currentLang = 'ru-RU';

  /// Инициализировать TTS. Безопасно вызывать многократно.
  Future<void> init() async {
    if (_ready) return;
    try {
      await _tts.setLanguage(_currentLang);
      await _tts.setSpeechRate(0.55);
      await _tts.setPitch(1.0);
      // Эти настройки полезны для слепых: говорить даже когда другое аудио
      // активно (например, музыка).
      await _tts.setSharedInstance(true);
      _ready = true;
    } catch (_) {
      // Если TTS недоступен — приложение остаётся работоспособным,
      // просто без озвучки.
      _ready = false;
    }
  }

  /// Сменить язык озвучки в зависимости от языка вводимого текста.
  Future<void> setLanguage(String langCode) async {
    if (_currentLang == langCode) return;
    _currentLang = langCode;
    if (_ready) {
      await _tts.setLanguage(langCode);
    }
  }

  /// Озвучить короткое сообщение. Прерывает предыдущее, если оно ещё идёт.
  Future<void> speak(String text) async {
    if (!_ready) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // Молчим — озвучка не должна валить приложение.
    }
  }

  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
