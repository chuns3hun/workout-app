import 'package:flutter/material.dart';
import '../store.dart';
import '../utils.dart';
import '../web_io.dart';

/// 백업 / 복원 다이얼로그
Future<void> showDataDialog(BuildContext context, Store st) async {
  Future<String?>? picked;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('백업 · 복원'),
      content: Text('마지막 JSON 백업: ${st.lastBackup ?? '없음'}',
          style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(
          onPressed: () async {
            downloadFile(
                st.exportJson(),
                'workout_backup_${dateKey(DateTime.now())}.json',
                'application/json');
            await st.markBackup();
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('JSON 백업'),
        ),
        TextButton(
          onPressed: () {
            // 엑셀에서 한글이 깨지지 않도록 BOM 추가
            downloadFile('\uFEFF${st.exportCsv()}',
                'workout_${dateKey(DateTime.now())}.csv', 'text/csv');
            Navigator.pop(ctx);
          },
          child: const Text('CSV 내보내기'),
        ),
        TextButton(
          onPressed: () {
            // 탭 직후 동기적으로 호출해야 iOS Safari에서 파일 선택창이 열림
            picked = pickTextFile();
            Navigator.pop(ctx);
          },
          child: const Text('JSON 복원'),
        ),
      ],
    ),
  );

  final pending = picked;
  if (pending == null) return;
  final raw = await pending;
  if (raw == null || !context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('백업 복원'),
      content: const Text('현재 저장된 기록을 백업 파일의 내용으로 덮어씁니다. 계속할까요?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('복원', style: TextStyle(color: Colors.tealAccent))),
      ],
    ),
  );
  if (ok != true) return;

  try {
    await st.importJson(raw);
    snack(context, '복원 완료');
  } catch (e) {
    snack(context, '복원 실패: 올바른 백업 파일이 아닙니다.');
  }
}
