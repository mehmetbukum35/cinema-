import 'package:flutter/material.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

const kTotalSteps = 5;

Widget buildDots(
  BuildContext context,
  int currentStep, {
  VoidCallback? onSkip,
}) {
  final c = context.c;
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(
        children: List.generate(kTotalSteps, (i) {
          return Padding(
            padding: EdgeInsets.only(right: i < kTotalSteps - 1 ? 6 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: i == currentStep ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == currentStep ? c.red : c.textFaint,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        }),
      ),
      if (onSkip != null)
        GestureDetector(
          onTap: onSkip,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: c.glassFill,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              AppLocalizations.of(context)?.get('onboarding_skip') ?? '',
              style: TextStyle(
                color: c.dim,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
    ],
  );
}

Widget buildContinueBtn(
  BuildContext context, {
  required String label,
  required VoidCallback? onTap,
}) {
  final c = context.c;
  final enabled = onTap != null;
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        gradient: enabled ? LinearGradient(colors: [c.red, c.crimson]) : null,
        color: enabled ? null : c.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: enabled ? Colors.white : c.dim,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
