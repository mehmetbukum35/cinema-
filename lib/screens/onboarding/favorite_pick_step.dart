import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/app_cached_image.dart';
import '../../models/movie.dart';
import '../../services/tmdb_service.dart';
import '../../services/localization_service.dart';
import '../../theme/app_theme.dart';
import 'onboarding_helpers.dart';

class FavoritePickStep extends StatefulWidget {
  final int stepIndex;
  final String title;
  final bool isTV;
  final TmdbService service;
  final List<Movie> selected;
  final void Function(Movie) onToggle;
  final VoidCallback onNext;
  final VoidCallback? onSkip;

  const FavoritePickStep({
    super.key,
    required this.stepIndex,
    required this.title,
    required this.isTV,
    required this.service,
    required this.selected,
    required this.onToggle,
    required this.onNext,
    this.onSkip,
  });

  @override
  State<FavoritePickStep> createState() => _FavoritePickStepState();
}

class _FavoritePickStepState extends State<FavoritePickStep> {
  final _ctrl = TextEditingController();
  List<Movie> _results = [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    _debounce?.cancel();
    setState(() {}); // suffix icon
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      final all = await widget.service.searchMulti(query);
      final res = all.where((m) => m.isTV == widget.isTV).toList();
      if (!mounted) return;
      setState(() {
        _results = res;
        _searching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final canAdd = widget.selected.length < 3;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildDots(context, widget.stepIndex, onSkip: widget.onSkip),
              const SizedBox(height: 22),
              Text(
                widget.title,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AppLocalizations.of(context)?.get('onboarding_fav_desc') ?? '',
                style: TextStyle(color: c.dim, fontSize: 13),
              ),
              const SizedBox(height: 16),
              // Search box
              Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: TextField(
                  controller: _ctrl,
                  onChanged: _onSearch,
                  style: TextStyle(color: c.ink, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: widget.isTV
                        ? (AppLocalizations.of(
                                context,
                              )?.get('onboarding_search_hint_tv') ??
                              '')
                        : (AppLocalizations.of(
                                context,
                              )?.get('onboarding_search_hint_movie') ??
                              ''),
                    hintStyle: TextStyle(color: c.dim),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: c.dim,
                      size: 20,
                    ),
                    suffixIcon: _ctrl.text.isNotEmpty
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
                              _ctrl.clear();
                              setState(() {
                                _results = [];
                                _searching = false;
                              });
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Selected chips
        if (widget.selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.selected.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) {
                  final m = widget.selected[i];
                  return GestureDetector(
                    onTap: () => widget.onToggle(m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: c.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: c.red, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              m.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.ink,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(Icons.close_rounded, color: c.red, size: 13),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

        // Results / empty state
        Expanded(
          child: _searching
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white38,
                    ),
                  ),
                )
              : _results.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _ctrl.text.isEmpty
                          ? (widget.isTV
                                ? (AppLocalizations.of(
                                        context,
                                      )?.get('onboarding_search_empty_tv') ??
                                      '')
                                : (AppLocalizations.of(
                                        context,
                                      )?.get('onboarding_search_empty_movie') ??
                                      ''))
                          : (AppLocalizations.of(
                                  context,
                                )?.get('search_no_results') ??
                                ''),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.dim, fontSize: 14, height: 1.6),
                    ),
                  ),
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  itemCount: _results.length,
                  itemBuilder: (ctx, i) {
                    final m = _results[i];
                    final sel = widget.selected.any((s) => s.id == m.id);
                    final disabled = !sel && !canAdd;
                    return Semantics(
                      label:
                          '${m.title}${m.year.isNotEmpty ? ", ${m.year}" : ""}',
                      button: true,
                      selected: sel,
                      enabled: !disabled,
                      child: GestureDetector(
                        onTap: disabled
                            ? null
                            : () {
                                final willSelect = !sel;
                                widget.onToggle(m);
                                if (willSelect) {
                                  _ctrl.clear();
                                  setState(() {
                                    _results = [];
                                    _searching = false;
                                  });
                                }
                              },
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: disabled ? 0.3 : 1.0,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: sel
                                  ? c.red.withValues(alpha: 0.1)
                                  : c.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: sel ? c.red : c.border,
                                width: sel ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(9),
                                  ),
                                  child: AppCachedNetworkImage(
                                    imageUrl: m.posterUrl,
                                    width: 44,
                                    height: 64,
                                    fit: BoxFit.cover,
                                    preset: AppImageCachePreset.avatar,
                                    placeholder: (context, url) =>
                                        _posterPlaceholder(context),
                                    errorWidget: (context, url, error) =>
                                        _posterPlaceholder(context),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: c.ink,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (m.year.isNotEmpty)
                                        Text(
                                          m.year,
                                          style: TextStyle(
                                            color: c.dim,
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Icon(
                                    sel
                                        ? Icons.check_circle_rounded
                                        : Icons.add_circle_outline_rounded,
                                    color: sel ? c.red : c.dim,
                                    size: 22,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Continue button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: buildContinueBtn(
            context,
            label: AppLocalizations.of(context)?.get('onboarding_next') ?? '',
            onTap: widget.onNext,
          ),
        ),
      ],
    );
  }

  Widget _posterPlaceholder(BuildContext context) {
    final c = context.c;
    return Container(
      width: 44,
      height: 64,
      color: c.surface,
      child: Center(child: Icon(Icons.movie_rounded, color: c.dim, size: 18)),
    );
  }
}
