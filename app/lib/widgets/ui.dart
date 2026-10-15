import 'package:flutter/material.dart';

import '../theme.dart';

/// Whitespace follows the reading preference; control sizes stay independent.
class AiraGap extends StatelessWidget {
  final double? width, height;
  const AiraGap({super.key, this.width, this.height});
  @override
  Widget build(BuildContext context) {
    final layout = AiraLayout.of(context);
    return SizedBox(
      width: width == null ? null : layout.space(width!),
      height: height == null ? null : layout.space(height!),
    );
  }
}

class AiraPadding extends StatelessWidget {
  final EdgeInsets padding;
  final Widget child;
  const AiraPadding({super.key, required this.padding, required this.child});
  @override
  Widget build(BuildContext context) =>
      Padding(padding: AiraLayout.of(context).insets(padding), child: child);
}

class AiraCard extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  const AiraCard({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(24),
  });
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: AiraColors.line.withValues(alpha: .7)),
    ),
    child: AiraPadding(padding: padding, child: child),
  );
}

class SectionHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  const SectionHeading(this.title, {super.key, this.subtitle, this.action});
  @override
  Widget build(BuildContext c) => AiraPadding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(c).textTheme.headlineMedium),
              if (subtitle != null) ...[
                const AiraGap(height: 8),
                Text(
                  subtitle!,
                  style: Theme.of(c).textTheme.bodyMedium
                      ?.copyWith(color: AiraColors.muted),
                ),
              ],
            ],
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

class Notice extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const Notice(
    this.text, {
    super.key,
    this.icon = Icons.info_outline_rounded,
    this.color = AiraColors.lavender,
  });
  @override
  Widget build(BuildContext c) => Container(
    padding: AiraLayout.of(c)
        .insets(const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21),
        const AiraGap(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(c).textTheme.bodySmall
                ?.copyWith(color: AiraColors.ink),
          ),
        ),
      ],
    ),
  );
}

void showMessage(BuildContext c, String text) =>
    ScaffoldMessenger.of(c).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
Future<bool> confirmAction(
  BuildContext c,
  String title,
  String body, {
  String confirm = 'Confirm',
}) async =>
    await showDialog<bool>(
      context: c,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(confirm),
          ),
        ],
      ),
    ) ??
    false;
