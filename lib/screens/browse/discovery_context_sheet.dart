import 'package:flutter/material.dart';

import '../../models/discovery_context.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';

class DiscoveryContextCard extends StatelessWidget {
  const DiscoveryContextCard({
    super.key,
    required this.value,
    required this.onTap,
  });

  final DiscoveryContext value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label:
          tr?.get('discovery_context_title') ??
          'Bu akşam ne izlemek istiyorsun?',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: value.isDefault ? c.border : c.gold,
                width: value.isDefault ? 1 : 1.5,
              ),
              boxShadow: c.cardShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.gold.withValues(alpha: 0.14),
                  ),
                  child: Icon(Icons.tune_rounded, color: c.gold),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr?.get('discovery_context_title') ??
                            'Bu akşam ne izlemek istiyorsun?',
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        value.isDefault
                            ? tr?.get('discovery_context_desc') ??
                                  'O anki isteğine göre önerileri ayarla'
                            : _summary(context, value),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.dim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.dim),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _summary(BuildContext context, DiscoveryContext value) {
    final tr = AppLocalizations.of(context);
    String text(String key, String fallback) => tr?.get(key) ?? fallback;
    final labels = <String>[
      switch (value.media) {
        DiscoveryMedia.movie => text('discovery_movie', 'Film'),
        DiscoveryMedia.tv => text('discovery_tv', 'Dizi'),
        DiscoveryMedia.any => text('discovery_any', 'Fark etmez'),
      },
      switch (value.familiarity) {
        DiscoveryFamiliarity.safe => text('discovery_safe', 'Güvenli'),
        DiscoveryFamiliarity.balanced => text('discovery_balanced', 'Dengeli'),
        DiscoveryFamiliarity.surprise => text('discovery_surprise', 'Sürpriz'),
      },
      switch (value.origin) {
        DiscoveryOrigin.local => text('discovery_local', 'Yerli'),
        DiscoveryOrigin.foreign => text('discovery_foreign', 'Yabancı'),
        DiscoveryOrigin.any => text('discovery_any', 'Fark etmez'),
      },
    ];
    if (value.duration != DiscoveryDuration.any) {
      labels.add(switch (value.duration) {
        DiscoveryDuration.short => text('discovery_short', 'Kısa'),
        DiscoveryDuration.medium => text('discovery_medium', 'Orta'),
        DiscoveryDuration.long => text('discovery_long', 'Uzun'),
        DiscoveryDuration.any => '',
      });
    }
    return labels.join(' · ');
  }
}

class DiscoveryContextSheet extends StatefulWidget {
  const DiscoveryContextSheet({super.key, required this.initialValue});

  final DiscoveryContext initialValue;

  @override
  State<DiscoveryContextSheet> createState() => _DiscoveryContextSheetState();
}

class _DiscoveryContextSheetState extends State<DiscoveryContextSheet> {
  late DiscoveryContext _value = widget.initialValue;

  String _tr(BuildContext context, String key, String fallback) =>
      AppLocalizations.of(context)?.get(key) ?? fallback;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _tr(
                context,
                'discovery_context_title',
                'Bu akşam ne izlemek istiyorsun?',
              ),
              style: TextStyle(
                color: c.ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _tr(
                context,
                'discovery_context_sheet_desc',
                'Bu seçimler yalnızca bu oturumdaki önerileri etkiler.',
              ),
              style: TextStyle(color: c.dim, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 22),
            _ChoiceSection<DiscoveryMedia>(
              title: _tr(context, 'discovery_media_title', 'Ne izleyelim?'),
              selected: _value.media,
              options: [
                (
                  DiscoveryMedia.any,
                  _tr(context, 'discovery_any', 'Fark etmez'),
                ),
                (DiscoveryMedia.movie, _tr(context, 'discovery_movie', 'Film')),
                (DiscoveryMedia.tv, _tr(context, 'discovery_tv', 'Dizi')),
              ],
              onSelected: (media) =>
                  setState(() => _value = _value.copyWith(media: media)),
            ),
            _ChoiceSection<DiscoveryDuration>(
              title: _tr(context, 'discovery_duration_title', 'Ne kadar uzun?'),
              selected: _value.duration,
              options: [
                (
                  DiscoveryDuration.any,
                  _tr(context, 'discovery_any', 'Fark etmez'),
                ),
                (
                  DiscoveryDuration.short,
                  _tr(context, 'discovery_short', 'Kısa'),
                ),
                (
                  DiscoveryDuration.medium,
                  _tr(context, 'discovery_medium', 'Orta'),
                ),
                (
                  DiscoveryDuration.long,
                  _tr(context, 'discovery_long', 'Uzun'),
                ),
              ],
              onSelected: (duration) =>
                  setState(() => _value = _value.copyWith(duration: duration)),
            ),
            _ChoiceSection<DiscoveryFamiliarity>(
              title: _tr(
                context,
                'discovery_familiarity_title',
                'Ne kadar keşif?',
              ),
              selected: _value.familiarity,
              options: [
                (
                  DiscoveryFamiliarity.safe,
                  _tr(context, 'discovery_safe', 'Güvenli'),
                ),
                (
                  DiscoveryFamiliarity.balanced,
                  _tr(context, 'discovery_balanced', 'Dengeli'),
                ),
                (
                  DiscoveryFamiliarity.surprise,
                  _tr(context, 'discovery_surprise', 'Sürpriz'),
                ),
              ],
              onSelected: (familiarity) => setState(
                () => _value = _value.copyWith(familiarity: familiarity),
              ),
            ),
            _ChoiceSection<DiscoveryOrigin>(
              title: _tr(context, 'discovery_origin_title', 'Hangi taraftan?'),
              subtitle: _tr(
                context,
                'discovery_origin_hint',
                'Yerli: tercih ettiğin sinemalar (yoksa uygulama diline göre).',
              ),
              selected: _value.origin,
              options: [
                (
                  DiscoveryOrigin.any,
                  _tr(context, 'discovery_any', 'Fark etmez'),
                ),
                (
                  DiscoveryOrigin.local,
                  _tr(context, 'discovery_local', 'Yerli'),
                ),
                (
                  DiscoveryOrigin.foreign,
                  _tr(context, 'discovery_foreign', 'Yabancı'),
                ),
              ],
              onSelected: (origin) =>
                  setState(() => _value = _value.copyWith(origin: origin)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _value),
                style: FilledButton.styleFrom(
                  backgroundColor: c.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  _tr(context, 'discovery_apply', 'Önerileri hazırla'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (!_value.isDefault)
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const DiscoveryContext()),
                child: Text(
                  _tr(context, 'discovery_clear', 'Seçimleri temizle'),
                  style: TextStyle(color: c.dim),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceSection<T> extends StatelessWidget {
  const _ChoiceSection({
    required this.title,
    this.subtitle,
    required this.selected,
    required this.options,
    required this.onSelected,
  });

  final String title;
  final String? subtitle;
  final T selected;
  final List<(T, String)> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: c.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(color: c.dim, fontSize: 12, height: 1.35),
            ),
          ],
          const SizedBox(height: 9),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (value, label) in options)
                  Semantics(
                    selected: selected == value,
                    button: true,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: selected == value,
                        onSelected: (_) => onSelected(value),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
