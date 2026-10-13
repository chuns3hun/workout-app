import 'package:flutter/material.dart';
import '../store.dart';
import 'body_page.dart';
import 'data_dialog.dart';
import 'history_page.dart';
import 'routine_page.dart';

class MorePage extends StatelessWidget {
  final Store store;
  const MorePage({super.key, required this.store});

  void _open(BuildContext c, Widget page) =>
      Navigator.push(c, MaterialPageRoute(builder: (_) => page));

  Future<void> _setRest(BuildContext context) async {
    final c = TextEditingController(text: '${store.defaultRestSeconds}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('휴식 시간'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: c,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(suffixText: '초'),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 6, children: [
              for (final s in [60, 90, 120, 180])
                ActionChip(label: Text('$s초'), onPressed: () => c.text = '$s'),
            ]),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())),
              child: const Text('확인')),
        ],
      ),
    );
    if (v != null) store.setRestSeconds(v);
  }

  Widget _tile(IconData icon, String title, VoidCallback onTap,
          {String? trailing}) =>
      ListTile(
        leading: Icon(icon, color: Colors.tealAccent, size: 22),
        title: Text(title, style: const TextStyle(fontSize: 15)),
        trailing: trailing == null
            ? const Icon(Icons.chevron_right, color: Colors.grey)
            : Text(trailing,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('더보기')),
        body: ListView(children: [
          _tile(Icons.folder_open, '루틴 관리',
              () => _open(context, RoutinePage(store: store))),
          _tile(Icons.monitor_weight_outlined, '신체 기록',
              () => _open(context, BodyPage(store: store))),
          _tile(Icons.history, '운동 목록',
              () => _open(context, HistoryPage(store: store))),
          _tile(Icons.timer_outlined, '휴식 시간', () => _setRest(context),
              trailing: '${store.defaultRestSeconds}초'),
          _tile(Icons.cloud_download_outlined, '백업 · 복원',
              () => showDataDialog(context, store),
              trailing: store.lastBackup ?? '백업 없음'),
        ]),
      ),
    );
  }
}
