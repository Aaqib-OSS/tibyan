import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/look_kit.dart';
import '../../../core/ui/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../mushaf/presentation/widgets/illuminated_frame.dart'
    show NumberFormatter;
import '../adhkar_providers.dart';
import '../data/adhkar_data.dart';

const adhkarLocation = '/adhkar';

/// «الأذكار»: the morning and evening adhkar exactly as published, each
/// with a tap counter up to its count, the day's progress and a reset;
/// the fadl and the source under each, folded.
class AdhkarScreen extends ConsumerStatefulWidget {
  const AdhkarScreen({super.key, this.initial = AdhkarTime.morning});

  final AdhkarTime initial;

  @override
  ConsumerState<AdhkarScreen> createState() => _AdhkarScreenState();
}

class _AdhkarScreenState extends ConsumerState<AdhkarScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initial.index,
  );

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  AdhkarTime get _time => AdhkarTime.values[_tabs.index];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return LookScaffold(
      maxWidth: ContentWidth.text,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LookTopBar(
              title: l.adhkarTitle,
              actions: [
                IconButton(
                  key: const ValueKey('adhkar-reset'),
                  tooltip: l.adhkarReset,
                  onPressed: () =>
                      ref.read(adhkarProgressProvider.notifier).reset(_time),
                  icon: const Icon(Icons.restart_alt),
                ),
                IconButton(
                  key: const ValueKey('adhkar-settings'),
                  tooltip: l.adhkarSettingsTitle,
                  onPressed: () => context.push('$adhkarLocation/settings'),
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
            TabBar(
              controller: _tabs,
              tabs: [
                Tab(
                  key: const ValueKey('adhkar-tab-morning'),
                  text: l.adhkarMorning,
                ),
                Tab(
                  key: const ValueKey('adhkar-tab-evening'),
                  text: l.adhkarEvening,
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  for (final t in AdhkarTime.values) _AdhkarList(time: t),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdhkarList extends ConsumerWidget {
  const _AdhkarList({required this.time});

  final AdhkarTime time;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final items = ref.watch(adhkarProvider((l.localeName, time)));
    final counts = ref.watch(adhkarProgressProvider)[time]!;
    final digits = NumberFormatter(Locale(l.localeName));
    return items.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) {
        final done = list.where((a) => (counts[a.order] ?? 0) >= a.count);
        final fraction = list.isEmpty ? 0.0 : done.length / list.length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                l.adhkarProgress(digits(done.length), digits(list.length)),
                key: const ValueKey('adhkar-progress'),
                style: TextStyle(color: t.muted),
              ),
            ),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 12),
            for (final a in list)
              _AdhkarCard(
                key: ValueKey('adhkar-item-${a.order}'),
                item: a,
                count: counts[a.order] ?? 0,
                onTap: () async {
                  final n = await ref
                      .read(adhkarProgressProvider.notifier)
                      .tap(time, a);
                  unawaited(
                    n >= a.count
                        ? HapticFeedback.mediumImpact()
                        : HapticFeedback.selectionClick(),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _AdhkarCard extends StatelessWidget {
  const _AdhkarCard({
    super.key,
    required this.item,
    required this.count,
    required this.onTap,
  });

  final AdhkarItem item;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final digits = NumberFormatter(Locale(l.localeName));
    final complete = count >= item.count;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: complete ? t.goldText : t.border,
          width: complete ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            enabled: !complete,
            label:
                '${item.content}. ${item.countDescription}. '
                '${l.adhkarCount(digits(count), digits(item.count))}',
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('adhkar-tap-${item.order}'),
              onTap: complete ? null : onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The text exactly as published.
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(
                        item.content,
                        style: const TextStyle(fontSize: 20, height: 1.9),
                      ),
                    ),
                    if (item.translation != null &&
                        item.translation!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.translation!,
                        style: const TextStyle(height: 1.6),
                      ),
                    ],
                    if (item.transliteration != null &&
                        item.transliteration!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.transliteration!,
                        style: TextStyle(
                          color: t.muted,
                          fontStyle: FontStyle.italic,
                          height: 1.6,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.countDescription,
                            style: TextStyle(color: t.muted),
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 72),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: complete
                                  ? t.goldText.withValues(alpha: .18)
                                  : t.control.withValues(alpha: .12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (complete) ...[
                                  Icon(
                                    Icons.check,
                                    size: 18,
                                    color: t.goldText,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  l.adhkarCount(
                                    digits(count),
                                    digits(item.count),
                                  ),
                                  key: ValueKey('adhkar-count-${item.order}'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: complete ? t.goldText : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (item.fadl.isNotEmpty || item.source.isNotEmpty)
            ExpansionTile(
              key: ValueKey('adhkar-details-${item.order}'),
              title: Text(
                l.adhkarDetails,
                style: const TextStyle(fontSize: 14),
              ),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                if (item.fadl.isNotEmpty) ...[
                  Text(
                    l.adhkarFadl,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(item.fadl, style: const TextStyle(height: 1.7)),
                  const SizedBox(height: 8),
                ],
                if (item.source.isNotEmpty) ...[
                  Text(
                    l.adhkarSource,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(item.source, style: const TextStyle(height: 1.7)),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
