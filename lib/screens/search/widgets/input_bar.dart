import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/localization_service.dart';
import '../../../theme/app_theme.dart';

/// Arama başlığı, metin alanı ve filtre düğmesi.
class SearchInputBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onOpenFilters;
  final bool hasActiveFilters;

  const SearchInputBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onOpenFilters,
    required this.hasActiveFilters,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)?.get('tab_search') ?? 'Search',
            style: TextStyle(
              color: c.ink,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: c.isLight
                        ? Border.all(color: c.border, width: 1)
                        : null,
                  ),
                  child: Semantics(
                    textField: true,
                    label:
                        AppLocalizations.of(context)?.get('search_hint') ??
                        'Movie or TV show name...',
                    child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      autofocus: false,
                      style: TextStyle(color: c.ink, fontSize: 15),
                      decoration: InputDecoration(
                        hintText:
                            AppLocalizations.of(context)?.get('search_hint') ??
                            'Movie or TV show name...',
                        hintStyle: TextStyle(color: c.dim, fontSize: 15),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: c.dim,
                          size: 20,
                        ),
                        suffixIcon: controller.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: c.dim,
                                  size: 18,
                                ),
                                tooltip:
                                    AppLocalizations.of(
                                      context,
                                    )?.get('semantics_close') ??
                                    'Close',
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  onClear();
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message:
                    AppLocalizations.of(context)?.get('filter') ?? 'Filter',
                child: Semantics(
                  button: true,
                  label:
                      AppLocalizations.of(context)?.get('filter') ?? 'Filter',
                  child: GestureDetector(
                    onTap: onOpenFilters,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasActiveFilters
                              ? c.red
                              : (c.isLight ? c.border : Colors.transparent),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        color: hasActiveFilters ? c.red : c.dim,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
