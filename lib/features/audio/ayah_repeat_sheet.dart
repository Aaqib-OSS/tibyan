import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_controller.dart';
import '../../l10n/app_localizations.dart';
import '../mushaf/mushaf_providers.dart';
import '../mushaf/presentation/widgets/illuminated_frame.dart';
import 'recitation.dart';

/// Counts offered for each verse and for the whole stretch; 0 is «∞».
const repeatCounts = [1, 3, 5, 10, 0];

/// Seconds of silence offered between repetitions.
const repeatPauses = [0, 1, 2, 3, 4, 5];

/// The verses of [surah] the reader's recitation times (numbered by the
/// recitation's riwaya, as the mushaf of that riwaya is): only those can
/// be repeated. Empty when the recitation has no timing for the surah.
final repeatableVersesProvider = FutureProvider.autoDispose
    .family<List<int>, ({int surah, int? reciterId})>((ref, k) async {
      final id =
          k.reciterId ?? (await ref.watch(currentReciterProvider.future))?.id;
      if (id == null) return const [];
      final timings = await ref
          .read(mushafRepositoryProvider)
          .timings(id, k.surah);
      return {
        for (final t in timings)
          if (t.ayah > 0) t.ayah,
      }.toList()..sort();
    });

/// «التكرار للحفظ»: the reader picks one verse or a stretch of [surah]
/// (by default [from]..[to]), how many times each verse plays, how many
/// times the whole stretch plays, and the silence between repetitions;
/// then the recitation starts. The choices are remembered.
Future<void> showAyahRepeatSheet(
  BuildContext context, {
  required int surah,
  required int from,
  int? to,
  int? reciterId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => AyahRepeatSheet(
    surah: surah,
    from: from,
    to: to ?? from,
    reciterId: reciterId,
  ),
);

class AyahRepeatSheet extends ConsumerStatefulWidget {
  const AyahRepeatSheet({
    super.key,
    required this.surah,
    required this.from,
    required this.to,
    this.reciterId,
  });

  final int surah;
  final int from;
  final int to;
  final int? reciterId;

  @override
  ConsumerState<AyahRepeatSheet> createState() => _AyahRepeatSheetState();
}

class _AyahRepeatSheetState extends ConsumerState<AyahRepeatSheet> {
  late int _from = widget.from;
  late int _to = widget.to;
  late int _verseRepeat;
  late int _repeat;
  late int _pause;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _verseRepeat = repeatCounts.contains(s.verseRepeat) ? s.verseRepeat : 3;
    _repeat = repeatCounts.contains(s.repeat) ? s.repeat : 1;
    _pause = s.repeatSilence.clamp(0, 5);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final digits = NumberFormatter(Localizations.localeOf(context));
    final theme = Theme.of(context);
    final title = theme.textTheme.titleSmall;
    final verses = ref.watch(
      repeatableVersesProvider((
        surah: widget.surah,
        reciterId: widget.reciterId,
      )),
    );
    String count(int n) => n == 0 ? l.repeatForever : l.repeatTimes(digits(n));

    Widget chips(
      List<int> values,
      int selected,
      String Function(int) label,
      ValueChanged<int> on,
    ) => Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(label(v)),
            selected: v == selected,
            onSelected: (_) => setState(() => on(v)),
          ),
      ],
    );

    Widget picker(
      String label,
      int value,
      List<int> options,
      ValueChanged<int> on,
    ) => Expanded(
      child: DropdownButtonFormField<int>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final a in options)
            DropdownMenuItem(value: a, child: Text(digits(a))),
        ],
        onChanged: (v) {
          if (v != null) setState(() => on(v));
        },
      ),
    );

    final body = switch (verses) {
      AsyncData(:final value) when value.isEmpty => [Text(l.noTiming)],
      AsyncData(:final value) => () {
        if (!value.contains(_from)) _from = value.first;
        if (!value.contains(_to)) _to = _from;
        final one = _from == _to;
        return [
          Row(
            children: [
              picker(l.repeatFromVerse, _from, value, (v) {
                _from = v;
                if (_to < v) _to = v;
              }),
              const SizedBox(width: 12),
              picker(l.repeatToVerse, _to, [
                for (final a in value)
                  if (a >= _from) a,
              ], (v) => _to = v),
            ],
          ),
          const SizedBox(height: 16),
          Semantics(header: true, child: Text(l.repeatEachVerse, style: title)),
          const SizedBox(height: 6),
          chips(repeatCounts, _verseRepeat, count, (v) => _verseRepeat = v),
          if (!one) ...[
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(l.repeatWholeRange, style: title),
            ),
            const SizedBox(height: 6),
            chips(repeatCounts, _repeat, count, (v) => _repeat = v),
          ],
          const SizedBox(height: 16),
          Semantics(header: true, child: Text(l.repeatPause, style: title)),
          const SizedBox(height: 6),
          chips(
            repeatPauses,
            _pause,
            (n) => n == 0 ? l.silenceNone : l.seconds(digits(n)),
            (v) => _pause = v,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.repeat),
            label: Text(l.repeatStart),
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(recitationProvider.notifier)
                  .playRepeat(
                    widget.surah,
                    from: _from,
                    to: _to,
                    verseRepeat: _verseRepeat,
                    repeat: _repeat,
                    silence: Duration(seconds: _pause),
                  );
            },
          ),
        ];
      }(),
      AsyncError() => [Text(l.playerError)],
      _ => [const Center(child: CircularProgressIndicator())],
    };

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                l.hifzRepeatTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            ...body,
          ],
        ),
      ),
    );
  }
}
