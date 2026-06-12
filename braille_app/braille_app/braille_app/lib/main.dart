import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ble/ble_service.dart';
import 'services/permission_service.dart';
import 'services/prefs_service.dart';
import 'services/speech_service.dart';
import 'services/voice_input_service.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Только portrait — приложение для слепых не нуждается в ландшафте.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const BrailleApp());
}

class BrailleApp extends StatefulWidget {
  const BrailleApp({super.key});

  @override
  State<BrailleApp> createState() => _BrailleAppState();
}

class _BrailleAppState extends State<BrailleApp> {
  final _ble = BleService();
  final _speech = SpeechService();
  final _voice = VoiceInputService();

  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Запрашиваем разрешения в самом начале.
    await PermissionService.requestAll();

    // TTS инициализируем заранее — он понадобится для первых же сообщений.
    await _speech.init();

    // Достаём сохранённый ID, чтобы попытаться авто-коннект на главном экране.
    final id = await PrefsService.getLastDeviceId();
    _ble.lastKnownDeviceId = id;

    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _ble.dispose();
    _speech.dispose();
    _voice.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Тема: высокий контраст, крупный шрифт. Тёмная тема включается системно.
    final lightScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1565C0),
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1565C0),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'BrailleReader',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: lightScheme,
        useMaterial3: true,
        textTheme: const TextTheme().apply(fontSizeFactor: 1.0),
      ),
      darkTheme: ThemeData(
        colorScheme: darkScheme,
        useMaterial3: true,
      ),
      home: _ready
          ? HomePage(ble: _ble, speech: _speech, voice: _voice)
          : const _SplashScreen(),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
