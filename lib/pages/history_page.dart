import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../utils.dart';
import 'session_page.dart';

class HistoryPage extends StatefulWidget {
  final Store store;
  const HistoryPage({super.key, required this.store});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  Future<void> _delete(Session s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.date} 기록 삭제'),
        content: const Text('이 날의 운동 기록을 삭제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => widget.store.sessions.remove(s));
    widget.store.save();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.store.sessions
        .where((s) => s.exercises.isNotEmpty)
        .toList()
        .reversed
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('운동 목록')),
      body: ListView(children: [
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(
                child: Text('기록이 없습니다.',
                    style: TextStyle(color: Colors.grey, fontSize: 13))),
          ),
        for (final s in list)
          ListTile(
            leading: Icon(
              s.isFinished ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: s.isFinished ? Colors.green : Colors.grey,
            ),
            title: Text(s.date),
            subtitle: Text(
                '${s.summaryText.isEmpty ? '' : '${s.summaryText} · '}볼륨 ${fmt(s.volume)}kg'),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.grey),
              onPressed: () => _delete(s),
            ),
            onTap: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          SessionPage(store: widget.store, session: s)));
              if (mounted) setState(() {});
            },
          ),
      ]),
    );
  }
}
