import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../utils.dart';
import '../widgets/line_chart.dart';

class BodyPage extends StatefulWidget {
  final Store store;
  const BodyPage({super.key, required this.store});

  @override
  State<BodyPage> createState() => _BodyPageState();
}

class _BodyPageState extends State<BodyPage> {
  final _wCtrl = TextEditingController();
  final _mCtrl = TextEditingController();
  final _fCtrl = TextEditingController();
  int _metric = 0; // 0 체중, 1 골격근량, 2 체지방률

  @override
  void dispose() {
    _wCtrl.dispose();
    _mCtrl.dispose();
    _fCtrl.dispose();
    super.dispose();
  }

  void _add() {
    final w = parseNum(_wCtrl.text);
    if (w == null) return;
    setState(() {
      widget.store.bodyRecords.add(BodyRecord(
          dateKey(DateTime.now()), w, parseNum(_mCtrl.text), parseNum(_fCtrl.text)));
    });
    widget.store.save();
    _wCtrl.clear();
    _mCtrl.clear();
    _fCtrl.clear();
  }

  Widget _input(TextEditingController c, String label) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: kDecimalKb,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final all = widget.store.bodyRecords;
    final records = all.reversed.toList();

    late final List<double> data;
    late final String label;
    late final String unit;
    if (_metric == 0) {
      data = all.map((r) => r.weight).toList();
      label = '체중';
      unit = 'kg';
    } else if (_metric == 1) {
      data = all.where((r) => r.muscle != null).map((r) => r.muscle!).toList();
      label = '골격근량';
      unit = 'kg';
    } else {
      data = all.where((r) => r.fat != null).map((r) => r.fat!).toList();
      label = '체지방률';
      unit = '%';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('신체 기록')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            _input(_wCtrl, '체중(kg)'),
            const SizedBox(width: 8),
            _input(_mCtrl, '골격근(kg)'),
            const SizedBox(width: 8),
            _input(_fCtrl, '체지방(%)'),
          ]),
          const SizedBox(height: 8),
          FilledButton(onPressed: _add, child: const Text('오늘 기록 추가')),
          const SizedBox(height: 16),
          Wrap(spacing: 8, children: [
            for (final (i, t) in ['체중', '골격근량', '체지방률'].indexed)
              ChoiceChip(
                label: Text(t),
                selected: _metric == i,
                onSelected: (_) => setState(() => _metric = i),
              ),
          ]),
          const SizedBox(height: 12),
          Text('$label 추이 ($unit)',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          lineChart(data),
          const Divider(),
          for (final r in records)
            ListTile(
              title: Text('${r.date}: ${fmt(r.weight)}kg'),
              subtitle: Text(
                  '골격근 ${r.muscle != null ? fmt(r.muscle!) : "-"}kg · 체지방 ${r.fat != null ? fmt(r.fat!) : "-"}%'),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                onPressed: () {
                  setState(() => widget.store.bodyRecords.remove(r));
                  widget.store.save();
                },
              ),
            ),
        ],
      ),
    );
  }
}
