import 'package:flutter/material.dart';
import '../../ble/ble_service.dart';

/// Крупная плашка статуса подключения наверху главного экрана.
///
/// Для зрячего: цветная плашка с иконкой.
/// Для слепого: TalkBack озвучивает "Подключено к BrailleReader" или
/// "Не подключено, нажмите чтобы найти устройство".
class StatusIndicator extends StatelessWidget {
  final BleConnState state;
  final VoidCallback? onTap;

  const StatusIndicator({
    super.key,
    required this.state,
    this.onTap,
  });

  ({Color color, IconData icon, String label, String semantic, String? hint}) _info() {
    switch (state) {
      case BleConnState.connected:
        return (
          color: const Color(0xFF2E7D32),
          icon: Icons.bluetooth_connected,
          label: 'Подключено',
          semantic: 'Устройство BrailleReader подключено',
          hint: 'нажмите чтобы отключиться',
        );
      case BleConnState.connecting:
        return (
          color: const Color(0xFFEF6C00),
          icon: Icons.bluetooth_searching,
          label: 'Подключение...',
          semantic: 'Идёт подключение к устройству',
          hint: null,
        );
      case BleConnState.scanning:
        return (
          color: const Color(0xFFEF6C00),
          icon: Icons.search,
          label: 'Поиск устройства...',
          semantic: 'Идёт поиск устройства BrailleReader',
          hint: null,
        );
      case BleConnState.failed:
        return (
          color: const Color(0xFFC62828),
          icon: Icons.error_outline,
          label: 'Не удалось подключиться',
          semantic: 'Не удалось подключиться к устройству',
          hint: 'нажмите чтобы попробовать снова',
        );
      case BleConnState.disconnected:
        return (
          color: const Color(0xFF424242),
          icon: Icons.bluetooth_disabled,
          label: 'Не подключено',
          semantic: 'Устройство не подключено',
          hint: 'нажмите чтобы найти устройство',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info();
    final isLoading = state == BleConnState.connecting ||
                      state == BleConnState.scanning;

    return Semantics(
      button: onTap != null,
      label: info.semantic,
      hint: info.hint,
      child: ExcludeSemantics(
        child: Material(
          color: info.color,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  if (isLoading)
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  else
                    Icon(info.icon, size: 32, color: Colors.white),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      info.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
