import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ble/ble_service.dart';
import '../core/braille_codec.dart';
import '../services/haptic_service.dart';
import '../services/permission_service.dart';
import '../services/prefs_service.dart';
import '../services/speech_service.dart';
import '../services/voice_input_service.dart';
import 'widgets/big_button.dart';
import 'widgets/status_indicator.dart';

class HomePage extends StatefulWidget {
  final BleService ble;
  final SpeechService speech;
  final VoiceInputService voice;

  const HomePage({
    super.key,
    required this.ble,
    required this.speech,
    required this.voice,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _textController = TextEditingController();
  bool _isListeningVoice = false;
  bool _isSending = false;
  StreamSubscription<String>? _notifSub;

  @override
  void initState() {
    super.initState();
    widget.ble.addListener(_onBleStateChanged);
    _notifSub = widget.ble.notifications.listen(_onDeviceNotification);
    // Автоконнект после построения UI.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoConnect());
  }

  @override
  void dispose() {
    widget.ble.removeListener(_onBleStateChanged);
    _notifSub?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _onBleStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// Уведомления от устройства озвучиваем для слепого пользователя.
  void _onDeviceNotification(String msg) {
    // Сокращённая интерпретация: устройство шлёт "POS i/N <буква>",
    // "FINISHED", "STOPPED", "LOADED <N> POS 1".
    if (msg.startsWith('FINISHED')) {
      widget.speech.speak('Чтение завершено');
      HapticService.success();
    } else if (msg.startsWith('STOPPED')) {
      widget.speech.speak('Остановлено');
    } else if (msg.startsWith('LOADED')) {
      // Уже озвучили "Текст отправлен" в _sendText, здесь не дублируем.
    }
    // POS-уведомления намеренно не озвучиваем — слепой читает букву пальцами,
    // дублирование речью будет мешать.
  }

  Future<void> _tryAutoConnect() async {
    final lastId = await PrefsService.getLastDeviceId();
    if (lastId == null) return;
    if (widget.ble.state != BleConnState.disconnected) return;

    widget.ble.lastKnownDeviceId = lastId;
    final ok = await widget.ble.reconnectIfPossible();
    if (ok) {
      widget.speech.speak('Устройство подключено');
      HapticService.success();
    }
  }

  Future<void> _onStatusTap() async {
    final st = widget.ble.state;
    if (st == BleConnState.connected) {
      await _confirmDisconnect();
    } else if (st == BleConnState.connecting || st == BleConnState.scanning) {
      // Идёт процесс — игнорируем.
      return;
    } else {
      await _findAndConnect();
    }
  }

  Future<void> _findAndConnect() async {
    HapticService.tap();
    widget.speech.speak('Ищу устройство');

    if (!await widget.ble.isBluetoothAvailable()) {
      widget.speech.speak('Включите Bluetooth');
      await widget.ble.turnOnBluetooth();
      return;
    }

    final ok = await widget.ble.findAndConnect();
    if (ok && widget.ble.lastKnownDeviceId != null) {
      await PrefsService.setLastDeviceId(widget.ble.lastKnownDeviceId!);
      widget.speech.speak('Устройство подключено');
      HapticService.success();
    } else {
      widget.speech.speak('Устройство не найдено');
      HapticService.error();
    }
  }

  Future<void> _confirmDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отключить устройство?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена', style: TextStyle(fontSize: 20)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отключить', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.ble.disconnect();
      widget.speech.speak('Отключено');
      HapticService.tap();
    }
  }

  Future<void> _toggleVoiceInput() async {
    if (_isListeningVoice) {
      await widget.voice.stop();
      setState(() => _isListeningVoice = false);
      HapticService.tap();
      return;
    }

    final hasMic = await PermissionService.hasMicrophone();
    if (!hasMic) {
      final granted = await PermissionService.requestMicrophone();
      if (!granted) {
        widget.speech.speak('Нет доступа к микрофону');
        HapticService.error();
        return;
      }
    }

    final ok = await widget.voice.init();
    if (!ok) {
      widget.speech.speak('Голосовой ввод недоступен');
      HapticService.error();
      return;
    }

    HapticService.tap();
    widget.speech.speak('Говорите');
    // Небольшая пауза, чтобы TTS успел отзвучать и не попасть в распознавание.
    await Future.delayed(const Duration(milliseconds: 700));

    setState(() => _isListeningVoice = true);

    // Локаль угадываем по последнему тексту в поле, иначе русская.
    final hasCyrillic = RegExp(r'[\u0400-\u04FF]').hasMatch(_textController.text);
    final locale = hasCyrillic || _textController.text.isEmpty ? 'ru_RU' : 'en_US';

    await widget.voice.start(
      localeId: locale,
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() {
          _textController.text = text;
          _textController.selection = TextSelection.collapsed(offset: text.length);
        });
        if (isFinal) {
          setState(() => _isListeningVoice = false);
          HapticService.success();
        }
      },
    );
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      widget.speech.speak('Сначала введите текст');
      HapticService.error();
      return;
    }

    if (widget.ble.state != BleConnState.connected) {
      widget.speech.speak('Сначала подключите устройство');
      HapticService.error();
      return;
    }

    setState(() => _isSending = true);
    HapticService.tap();

    final tokens = BrailleCodec.encode(text);
    final lang = BrailleCodec.detectLanguage(text);

    // Подстроим язык TTS под отправляемый текст — на случай если потом
    // устройство пришлёт уведомления и мы захотим их озвучить.
    await widget.speech.setLanguage(
      lang == BrailleLang.russian ? 'ru-RU' : 'en-US',
    );

    final ok = await widget.ble.sendText(tokens);

    setState(() => _isSending = false);

    if (ok) {
      widget.speech.speak('Текст отправлен');
      HapticService.success();
      // Убираем клавиатуру если она открыта.
      FocusScope.of(context).unfocus();
    } else {
      widget.speech.speak('Ошибка отправки');
      HapticService.error();
    }
  }

  Future<void> _stopReading() async {
    if (widget.ble.state != BleConnState.connected) return;
    HapticService.heavy();
    final ok = await widget.ble.stopReading();
    if (ok) {
      widget.speech.speak('Остановлено');
    }
  }

  Future<void> _clearText() async {
    if (_textController.text.isEmpty) return;
    HapticService.tap();
    setState(() => _textController.clear());
    widget.speech.speak('Текст очищен');
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.ble.state == BleConnState.connected;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'BrailleReader',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 28),
            tooltip: 'Очистить текст',
            onPressed: _textController.text.isEmpty ? null : _clearText,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              StatusIndicator(
                state: widget.ble.state,
                onTap: _onStatusTap,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Semantics(
                  textField: true,
                  label: 'Поле ввода текста',
                  hint: _isListeningVoice
                      ? 'Идёт голосовой ввод, говорите'
                      : 'Введите или продиктуйте текст',
                  child: TextField(
                    controller: _textController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontSize: 22, height: 1.4),
                    decoration: InputDecoration(
                      hintText: 'Введите текст или нажмите микрофон',
                      hintStyle: TextStyle(
                        fontSize: 20,
                        color: Theme.of(context).hintColor,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(20),
                    ),
                    onChanged: (_) => setState(() {}),
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(500),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              BigButton(
                icon: _isListeningVoice ? Icons.stop_circle : Icons.mic,
                label: _isListeningVoice ? 'Остановить' : 'Голосовой ввод',
                semanticLabel: _isListeningVoice
                    ? 'Остановить голосовой ввод'
                    : 'Начать голосовой ввод',
                hint: _isListeningVoice
                    ? 'идёт запись, нажмите чтобы остановить'
                    : 'нажмите и начните говорить',
                color: _isListeningVoice
                    ? const Color(0xFFC62828)
                    : const Color(0xFF1565C0),
                onPressed: _toggleVoiceInput,
              ),
              const SizedBox(height: 12),
              BigButton(
                icon: _isSending ? Icons.hourglass_top : Icons.send,
                label: _isSending ? 'Отправка...' : 'Отправить',
                semanticLabel: 'Отправить текст на устройство',
                hint: connected
                    ? null
                    : 'устройство не подключено, кнопка недоступна',
                color: const Color(0xFF2E7D32),
                onPressed: (connected && !_isSending && _textController.text.trim().isNotEmpty)
                    ? _sendText
                    : null,
              ),
              const SizedBox(height: 12),
              BigButton(
                icon: Icons.stop,
                label: 'Стоп',
                semanticLabel: 'Остановить чтение на устройстве',
                hint: connected ? null : 'устройство не подключено',
                color: const Color(0xFF6A1B9A),
                onPressed: connected ? _stopReading : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
