import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../utils.dart';
import '../widgets/line_chart.dart';

class StatsPage extends StatefulWidget {
  final Store store;
  const StatsPage({super.key, required this.store});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  String? _selected;
  int _period = 0; // 0: 이번 주, 1: 최근 4주

  Store get st => widget.store;

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(t,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      );

  String _compact(double v) {
    if (v == 0) return '';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return fmt(v);
  }

  Widget _exerciseSection() {
    final names = st
        .recentExerciseNames()
        .where((n) => st.get1RMHistory(n).isNotEmpty)
        .toList();
    if (names.isEmpty) {
      return const Text('완료된 세트 기록이 없습니다.',
          style: TextStyle(color: Colors.grey, fontSize: 12));
    }
    if (_selected == null || !names.contains(_selected)) _selected = names.first;
    final hist = st.get1RMHistory(_selected!);
    final best = hist.fold<double>(0, (m, e) => e.value > m ? e.value : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<String>(
          value: _selected,
          isExpanded: true,
          items: names
              .map((n) => DropdownMenuItem(value: n, child: Text(n)))
              .toList(),
          onChanged: (v) => setState(() => _selected = v),
        ),
        const SizedBox(height: 4),
        Text(
            '최고 추정 1RM ${fmt(best)}kg · PR ${fmt(st.pr(_selected!))}kg · ${hist.length}회 수행',
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        lineChart(hist.map((e) => e.value).toList()),
      ],
    );
  }

  Widget _weeklyVolume() {
    final thisWeek = weekStart(DateTime.now());
    final weeks = <DateTime>[
      for (var i = 7; i >= 0; i--)
        DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7 * i)
    ];
    final sums = <String, double>{};
    for (final s in st.sessions) {
      final d = DateTime.tryParse(s.date);
      if (d == null) continue;
      final k = dateKey(weekStart(d));
      sums[k] = (sums[k] ?? 0) + s.volume;
    }
    final vals = [for (final w in weeks) sums[dateKey(w)] ?? 0.0];
    final maxV = vals.fold<double>(0, (m, v) => v > m ? v : m);
    if (maxV == 0) {
      return const Text('기록 없음',
          style: TextStyle(color: Colors.grey, fontSize: 12));
    }

    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < weeks.length; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(_compact(vals[i]),
                      style: const TextStyle(fontSize: 9, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Container(
                    height: 100 * vals[i] / maxV,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == weeks.length - 1
                          ? Colors.tealAccent
                          : Colors.tealAccent.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${weeks[i].month}/${weeks[i].day}',
                      style: const TextStyle(fontSize: 9, color: Colors.grey)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _muscleSets() {
    final now = DateTime.now();
    final from = _period == 0
        ? weekStart(now)
        : DateTime(now.year, now.month, now.day - 27);

    final counts = <String, int>{};
    for (final s in st.sessions) {
      final d = DateTime.tryParse(s.date);
      if (d == null || d.isBefore(from)) continue;
      for (final e in s.exercises) {
        final n =
            e.sets.where((x) => x.done && x.type != SetType.WARMUP).length;
        if (n > 0) counts[e.targetMuscle] = (counts[e.targetMuscle] ?? 0) + n;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          ChoiceChip(
            label: const Text('이번 주'),
            selected: _period == 0,
            onSelected: (_) => setState(() => _period = 0),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('최근 4주'),
            selected: _period == 1,
            onSelected: (_) => setState(() => _period = 1),
          ),
        ]),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const Text('완료된 세트 없음',
              style: TextStyle(color: Colors.grey, fontSize: 12))
        else
          for (final en in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(
                    width: 44,
                    child: Text(en.key, style: const TextStyle(fontSize: 12))),
                Expanded(
                  child: LinearProgressIndicator(
                    value: en.value / entries.first.value,
                    minHeight: 8,
                    color: Colors.tealAccent,
                    backgroundColor: Colors.white10,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  child: Text('${en.value}세트',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              ]),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('통계')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _title('종목별 추정 1RM 추이'),
            _exerciseSection(),
            _title('주간 총 볼륨 (kg, 최근 8주)'),
            _weeklyVolume(),
            _title('부위별 완료 세트 수 (웜업 제외)'),
            _muscleSets(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
