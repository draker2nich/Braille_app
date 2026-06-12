import 'package:flutter/material.dart';

/// Крупная кнопка для слепых пользователей.
///
/// Особенности:
///   - Минимум 88dp по высоте (Material рекомендация для accessibility 48dp,
///     но для слепых берём с запасом).
///   - Жирный контрастный текст.
///   - Иконка + подпись.
///   - Семантический ярлык для TalkBack отдельно от визуальной подписи —
///     слепой слышит развёрнутое описание, зрячий помощник видит коротко.
///   - Состояние disabled с явным сообщением «недоступно».
class BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String semanticLabel; // что зачитывается TalkBack
  final String? hint;          // дополнительная подсказка для TalkBack
  final VoidCallback? onPressed;
  final Color? color;

  const BigButton({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    this.hint,
    this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    final bg = color ?? theme.colorScheme.primary;

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      hint: hint,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 120,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: enabled ? bg : Colors.grey.shade400,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 4,
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 48),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
