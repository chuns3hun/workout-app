import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';

class RoutinePage extends StatefulWidget {
  final Store store;
  const RoutinePage({super.key, required this.store});

  @override
  State<RoutinePage> createState() => _RoutinePageState();
}

class _RoutinePageState extends State<RoutinePage> {
  Future<void> _addExercise(Routine r) async {
    final c = TextEditingController();
    final pastNames = widget.store.recentExerciseNames();

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${r.name}에 종목 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: c,
              autofocus: true,
              decoration: const InputDecoration(hintText: '종목명 입력 (예: 벤치프레스)'),
            ),
            if (pastNames.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('이전 기록 종목 선택:',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: pastNames
                    .take(8)
                    .map((n) => ActionChip(
                          label: Text(n, style: const TextStyle(fontSize: 11)),
                          onPressed: () => Navigator.pop(ctx, n),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('추가')),
        ],
      ),
    );

    if (name == null || name.isEmpty || r.exercises.contains(name)) return;
    setState(() => r.exercises.add(name));
    widget.store.save();
  }

  Future<void> _addRoutine() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('새 루틴 이름'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('확인')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      setState(() => widget.store.routines.add(Routine(name, [])));
      widget.store.save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final routines = widget.store.routines;
    return Scaffold(
      appBar: AppBar(title: const Text('루틴 관리')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.tealAccent,
        foregroundColor: Colors.black,
        onPressed: _addRoutine,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          if (routines.isEmpty)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(
                  child: Text('+ 버튼으로 루틴을 만드세요.',
                      style: TextStyle(color: Colors.grey, fontSize: 13))),
            ),
          for (final r in routines)
            ExpansionTile(
              title: Text(r.name,
                  style: const TextStyle(
                      color: Colors.tealAccent, fontWeight: FontWeight.bold)),
              subtitle: Text('${r.exercises.length}개 종목'),
              children: [
                for (var i = 0; i < r.exercises.length; i++)
                  ListTile(
                    dense: true,
                    title: Text('• ${r.exercises[i]}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                      onPressed: () {
                        setState(() => r.exercises.removeAt(i));
                        widget.store.save();
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() => routines.remove(r));
                          widget.store.save();
                        },
                        child: const Text('루틴 삭제',
                            style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('종목 추가',
                            style: TextStyle(fontSize: 12)),
                        onPressed: () => _addExercise(r),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
