import 'package:speech_to_text/speech_to_text.dart';

/// Распознавание речи через системный движок Android.
///
/// На Android 13+ доступно полностью оффлайн (после скачивания языкового
/// пакета один раз). На более старых версиях работает через Google Speech.
///
/// Для слепых критично: пользователь должен мочь начать ввод одним длинным
/// касанием экрана/большой кнопки, и не должен ждать никаких звуковых
/// «биипов» — мы сами вибрируем при старте/остановке.
class VoiceInputService {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  bool _listening = false;

  bool get isListening => _listening;
  bool get isReady => _ready;

  /// Инициализация. Возвращает true если распознавание доступно.
  Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(
        onStatus: (s) {
          // status: "notListening" приходит когда сессия закончилась.
          if (s == 'notListening' || s == 'done') _listening = false;
        },
        onError: (_) {
          _listening = false;
        },
      );
      return _ready;
    } catch (_) {
      _ready = false;
      return false;
    }
  }

  /// Начать распознавание. Колбэк onResult вызывается на каждое обновление
  /// (по мере того, как пользователь говорит), `isFinal=true` — итоговый
  /// результат после паузы.
  Future<void> start({
    required String localeId, // например, 'ru_RU' или 'en_US'
    required void Function(String text, bool isFinal) onResult,
  }) async {
    if (!_ready) {
      final ok = await init();
      if (!ok) return;
    }
    if (_listening) await stop();

    _listening = true;
    await _stt.listen(
      localeId: localeId,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      onResult: (r) {
        onResult(r.recognizedWords, r.finalResult);
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  Future<void> stop() async {
    if (!_listening) return;
    try {
      await _stt.stop();
    } catch (_) {}
    _listening = false;
  }
}
