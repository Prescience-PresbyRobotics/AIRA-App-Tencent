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

/// A short, visual entry point. Details live on the destination page.
class AiraSummaryCard extends StatelessWidget {
  final String title, subtitle;
  final String? value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const AiraSummaryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.value,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AiraColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 132, minWidth: 48),
          child: AiraPadding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: AiraColors.forest, size: 25),
                    ),
                    const AiraGap(width: 16),
                    if (value != null)
                      Expanded(
                        child: Text(
                          value!,
                          style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: AiraColors.muted,
                    ),
                  ],
                ),
                const AiraGap(height: 18),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const AiraGap(height: 5),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Cards reflow instead of clipping when device text is enlarged.
class AiraCardGrid extends StatelessWidget {
  final List<Widget> children;
  const AiraCardGrid({super.key, required this.children});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final gap = AiraLayout.of(context).space(18);
      final twoColumns =
          bounds.maxWidth >= 460 &&
          MediaQuery.textScalerOf(context).scale(20) < 28;
      final width = twoColumns ? (bounds.maxWidth - gap) / 2 : bounds.maxWidth;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class AiraDetailPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const AiraDetailPage({
    super.key,
    required this.title,
    required this.children,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), backgroundColor: AiraColors.cream),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: AiraLayout.of(context).insets(const EdgeInsets.all(28)),
            children: children,
          ),
        ),
      ),
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
