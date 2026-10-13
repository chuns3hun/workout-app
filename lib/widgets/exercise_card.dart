import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../utils.dart';

class ExerciseCard extends StatelessWidget {
  final Store store;
  final Session session;
  final Exercise e;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback onSetDone;

  const ExerciseCard({
    super.key,
    required this.store,
    required this.session,
    required this.e,
    required this.onChanged,
    required this.onRemove,
    required this.onSetDone,
  });

  void _copyPrev(BuildContext context) {
    final prev = store.previous(e.name, session.date);
    if (prev.isEmpty) {
      snack(context, '이전 기록이 없습니다.');
      return;
    }
    e.sets = prev;
    e.rev++;
    onChanged();
  }

  void _addSet() {
    final last = e.sets.isEmpty ? null : e.sets.last;
    e.sets.add(SetEntry(weight: last?.weight ?? 0, reps: last?.reps ?? 0));
    onChanged();
  }

  void _addDrop() {
    if (e.sets.isEmpty) return;
    final last = e.sets.last;
    e.sets.add(SetEntry(
      weight: (last.weight * 0.8).roundToDouble(),
      reps: last.reps,
      type: SetType.DROP,
    ));
    onChanged();
  }

  void _addWarmup() {
    final firstWork = e.sets.indexWhere((s) => s.type != SetType.WARMUP);
    final pos = firstWork == -1 ? e.sets.length : firstWork;
    final ref = firstWork == -1 ? null : e.sets[firstWork];
    e.sets.insert(
      pos,
      SetEntry(
        weight: ref == null ? 0 : ((ref.weight * 0.5) / 2.5).round() * 2.5,
        reps: ref == null ? 0 : 10,
        type: SetType.WARMUP,
      ),
    );
    e.rev++;
    onChanged();
  }

  Future<void> _edit(BuildContext context) async {
    final memoC = TextEditingController(text: e.memo);
    final minC = TextEditingController(text: '${e.minReps}');
    final maxC = TextEditingController(text: '${e.maxReps}');
    String muscle = kMuscles.contains(e.targetMuscle) ? e.targetMuscle : '기타';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(e.name),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('타겟 부위',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                DropdownButton<String>(
                  value: muscle,
                  isExpanded: true,
                  items: kMuscles
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setSt(() => muscle = v!),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: minC,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: '목표 최소 횟수'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: maxC,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: '목표 최대 횟수'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: memoC,
                  maxLines: null,
                  decoration: const InputDecoration(labelText: '종목 메모'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('저장')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    var mn = int.tryParse(minC.text.trim()) ?? e.minReps;
    var mx = int.tryParse(maxC.text.trim()) ?? e.maxReps;
    if (mn < 1) mn = 1;
    if (mx < mn) mx = mn;
    e.targetMuscle = muscle;
    e.minReps = mn;
    e.maxReps = mx;
    e.memo = memoC.text.trim();
    onChanged();
  }

  String _setLabel(int idx) {
    final t = e.sets[idx].type;
    if (t == SetType.WARMUP) return 'W';
    if (t == SetType.DROP) return 'D';
    return '${e.sets.take(idx + 1).where((x) => x.type == SetType.MAIN).length}';
  }

  @override
  Widget build(BuildContext context) {
    final pr = store.pr(e.name);
    final prevSets = store.previous(e.name, session.date);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context, pr),
            if (!e.isCollapsed) ..._body(prevSets),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, double pr) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () {
              e.isCollapsed = !e.isCollapsed;
              onChanged();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(e.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(e.targetMuscle,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey)),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '${e.sets.length}세트 · PR ${fmt(pr)}kg · 볼륨 ${fmt(e.volume)}kg · 목표 ${e.minReps}~${e.maxReps}회',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
        Icon(e.isCollapsed ? Icons.expand_more : Icons.expand_less,
            size: 20, color: Colors.grey),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
          onSelected: (v) {
            if (v == 'copy') {
              _copyPrev(context);
            } else if (v == 'edit') {
              _edit(context);
            } else if (v == 'del') {
              onRemove();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'copy', child: Text('이전 세트 불러오기')),
            PopupMenuItem(value: 'edit', child: Text('종목 설정')),
            PopupMenuItem(value: 'del', child: Text('종목 삭제')),
          ],
        ),
      ],
    );
  }

  List<Widget> _body(List<SetEntry> prevSets) {
    final prevSummary = prevSets.isEmpty
        ? '이전 기록 없음'
        : '이전: ${prevSets.asMap().entries.map((en) => '${en.key + 1}세트 ${fmt(en.value.weight)}kg×${en.value.reps}회').join(' | ')}';

    return [
      if (e.memo.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 10),
          child: Text('메모: ${e.memo}',
              style: const TextStyle(color: Colors.amber, fontSize: 11)),
        ),
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Text(prevSummary,
            style: TextStyle(color: Colors.grey[400], fontSize: 11)),
      ),
      const SizedBox(height: 2),
      Text(store.recommendNext(e, session.date),
          style: const TextStyle(fontSize: 11, color: Colors.tealAccent)),
      const SizedBox(height: 6),
      for (var idx = 0; idx < e.sets.length; idx++)
        _setRow(e.sets[idx], idx, prevSets.length > idx ? prevSets[idx] : null),
      Row(children: [
        TextButton(
          onPressed: _addSet,
          child: const Text('+ 세트',
              style: TextStyle(fontSize: 12, color: Colors.tealAccent)),
        ),
        TextButton(
          onPressed: _addWarmup,
          child: const Text('+ 웜업',
              style: TextStyle(fontSize: 12, color: Colors.amber)),
        ),
        TextButton(
          onPressed: _addDrop,
          child: const Text('+ 드롭(-20%)',
              style: TextStyle(fontSize: 12, color: Colors.orangeAccent)),
        ),
      ]),
    ];
  }

  Widget _field({
    required Key key,
    required String initial,
    required String hint,
    required TextInputType kb,
    required ValueChanged<String> onText,
  }) {
    return TextFormField(
      key: key,
      initialValue: initial,
      keyboardType: kb,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
        isDense: true,
        border: InputBorder.none,
      ),
      onChanged: onText,
    );
  }

  Widget _setRow(SetEntry s, int idx, SetEntry? prev) {
    final Color labelColor = s.type == SetType.WARMUP
        ? Colors.amber
        : s.type == SetType.DROP
            ? Colors.orangeAccent
            : Colors.grey;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              s.type = SetType.values[(s.type.index + 1) % SetType.values.length];
              onChanged();
            },
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: labelColor.withOpacity(0.6)),
              ),
              child: Text(_setLabel(idx),
                  style: TextStyle(color: labelColor, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _field(
              key: ValueKey('w_${e.rev}_$idx'),
              initial: s.weight == 0 ? '' : fmt(s.weight),
              hint: prev != null ? '${fmt(prev.weight)}kg' : 'kg',
              kb: kDecimalKb,
              onText: (v) {
                s.weight = parseNum(v) ?? 0;
                store.save();
              },
            ),
          ),
          Expanded(
            child: _field(
              key: ValueKey('r_${e.rev}_$idx'),
              initial: s.reps == 0 ? '' : '${s.reps}',
              hint: prev != null ? '${prev.reps}회' : '회',
              kb: TextInputType.number,
              onText: (v) {
                s.reps = int.tryParse(v) ?? 0;
                store.save();
              },
            ),
          ),
          SizedBox(
            width: 52,
            child: _field(
              key: ValueKey('p_${e.rev}_$idx'),
              initial: s.rpe == null ? '' : fmt(s.rpe!),
              hint: prev?.rpe != null ? fmt(prev!.rpe!) : 'RPE',
              kb: kDecimalKb,
              onText: (v) {
                final n = parseNum(v);
                s.rpe = (n != null && n >= 1 && n <= 10) ? n : null;
                store.save();
              },
            ),
          ),
          Checkbox(
            value: s.done,
            activeColor: Colors.tealAccent,
            checkColor: Colors.black,
            onChanged: (v) {
              s.done = v ?? false;
              onChanged();
              if (v == true) onSetDone();
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove, size: 14, color: Colors.grey),
            onPressed: () {
              e.sets.removeAt(idx);
              e.rev++;
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}