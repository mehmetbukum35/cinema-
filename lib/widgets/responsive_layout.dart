import 'package:flutter/material.dart';

/// Kısa ekranlarda içeriği kaydırılabilir tutan, dar ekran kenar boşluklarını
/// standartlaştıran uygulama geneli dialog kabuğu.
class ResponsiveAlertDialog extends StatelessWidget {
  final Widget? title;
  final Widget content;
  final List<Widget> actions;
  final Color? backgroundColor;
  final Color? surfaceTintColor;
  final ShapeBorder? shape;

  const ResponsiveAlertDialog({
    super.key,
    this.title,
    required this.content,
    this.actions = const [],
    this.backgroundColor,
    this.surfaceTintColor,
    this.shape,
  });

  @override
  Widget build(BuildContext context) {
    final horizontalInset = MediaQuery.sizeOf(context).width < 360
        ? 16.0
        : 24.0;
    return AlertDialog(
      scrollable: true,
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: 24,
      ),
      backgroundColor: backgroundColor,
      surfaceTintColor: surfaceTintColor,
      shape: shape,
      title: title,
      content: content,
      actions: actions,
    );
  }
}

/// Etiket ve değer alanlarını dar genişlikte veya büyük yazı ölçeğinde güvenli
/// biçimde paylaştırır. Değer uzunsa satır kırar; metinler birbirini itemez.
class AdaptiveLabelValueRow extends StatelessWidget {
  final Widget label;
  final Widget value;
  final double gap;

  const AdaptiveLabelValueRow({
    super.key,
    required this.label,
    required this.value,
    this.gap = 12,
  });

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final stackVertically = screenWidth < 300 || textScale > 1.5;

    if (stackVertically) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label,
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerRight, child: value),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: label),
        SizedBox(width: gap),
        Flexible(
          child: Align(alignment: Alignment.topRight, child: value),
        ),
      ],
    );
  }
}
