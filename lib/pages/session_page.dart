import 'dart:async';
import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../utils.dart';
import '../widgets/exercise_card.dart';
import 'data_dialog.dart';

String fmtDuration(int sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  if (h > 0) {
    return '$h시간 ${m.toString().padLeft(2, '0')}분 ${s.toString().padLeft(2, '0')}초';
  }
  return '$m분 ${s.toString().padLeft(2, '0')}초';
}

/// 운동 기록 화면. session == null 이면 "오늘" 탭용.
class SessionPage extends StatefulWidget {
  final Store store;
  final Session? session;
  const SessionPage({super.key, required this.store, this.session});

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> with WidgetsBindingObserver {
  late Session session;
  bool get isToday => widget.session == null;
  bool get _isLive => session.date == dateKey(DateTime.now());

  Timer? _ticker;
  DateTime? _restEnd;
  Timer? _workoutTicker;

  @override
  void initState() {
    super.initState();
    session = widget.session ?? widget.store.today();
    widget.store.addListener(_onStore);
    WidgetsBinding.instance.addObserver(this);
    if (session.startTime != null && !session.isFinished) {
      _startWorkoutTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_onStore);
    _ticker?.cancel();
    _workoutTicker?.cancel();
    super.dispose();
  }

  void _onStore() {
    if (!mounted) return;
    setState(() {
      if (isToday && !widget.store.sessions.contains(session)) {
        session = widget.store.today();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    setState(() {
      if (isToday && session.date != dateKey(DateTime.now())) {
        session = widget.store.today();
      }
    });
  }

  void _changed() {
    setState(() {});
    widget.store.save();
  }

  // ----- 실시간 운동 타이머 -----
  void _startWorkoutTimer() {
    _workoutTicker?.cancel();
    _workoutTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && session.startTime != null && !session.isFinished) {
        setState(() {
          session.durationSeconds =
              DateTime.now().difference(session.startTime!).inSeconds;
        });
      }
    });
  }

  void _toggleWorkoutStart() {
    setState(() {
      if (session.startTime == null) {
        session.startTime = DateTime.now();
        _startWorkoutTimer();
        snack(context, '🏋️ 운동을 시작합니다!');
      } else {
        session.startTime = null;
        _workoutTicker?.cancel();
      }
    });
    _changed();
  }

  // ----- 휴식 타이머 -----
  int _remaining() {
    final ms = _restEnd?.difference(DateTime.now()).inMilliseconds ?? 0;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  void _startRest(int sec) {
    _ticker?.cancel();
    _restEnd = DateTime.now().add(Duration(seconds: sec));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining() == 0) _ticker?.cancel();
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  void _stopRest() {
    _ticker?.cancel();
    setState(() => _restEnd = null);
  }

  Widget _restBar() {
    final r = _remaining();
    final text = r == 0
        ? '휴식 종료'
        : '휴식 ${r ~/ 60}:${(r % 60).toString().padLeft(2, '0')}';
    return Container(
      color: const Color(0xFF18181B),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        Text(text,
            style: const TextStyle(
                color: Colors.tealAccent,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        const Spacer(),
        TextButton(
            onPressed: () => _startRest(r + 30),
            child: const Text('+30초', style: TextStyle(color: Colors.white70))),
        IconButton(icon: const Icon(Icons.close, size: 20), onPressed: _stopRest),
      ]),
    );
  }

  // ----- 동작 -----
  void _toggleFinish() {
    setState(() {
      session.isFinished = !session.isFinished;
      if (session.isFinished) {
        _stopRest();
        _workoutTicker?.cancel();
        snack(context, '🎉 운동 완료! 총 ${fmtDuration(session.durationSeconds)} 운동함');
      } else if (session.startTime != null) {
        _startWorkoutTimer();
      }
    });
    _changed();
  }

  Future<void> _loadRoutine() async {
    final routines = widget.store.routines;
    if (routines.isEmpty) {
      snack(context, '등록된 루틴이 없습니다. (더보기 > 루틴 관리)');
      return;
    }

    final picked = await showDialog<Routine>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('루틴 선택'),
        children: [
          for (final x in routines)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, x),
              child: Text('${x.name} (${x.exercises.length}개 종목)'),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;

    if (session.exercises.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('루틴 불러오기'),
          content: Text('현재 종목을 지우고 "${picked.name}" 루틴으로 교체할까요?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('덧붙이기')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('기존 항목 비우고 교체',
                    style: TextStyle(color: Colors.tealAccent))),
          ],
        ),
      );
      if (replace == null) return;
      if (replace) session.exercises.clear();
    }

    for (final name in picked.exercises) {
      if (session.exercises.any((e) => e.name == name)) continue;
      session.exercises.add(widget.store.newExercise(name, session.date));
    }
    session.routine = picked.name;
    _changed();
    if (mounted) snack(context, '${picked.name} 루틴을 불러왔습니다.');
  }

  Future<void> _addExercise() async {
    final c = TextEditingController();
    String muscle = '가슴';
    final pastNames = widget.store.recentExerciseNames();

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('종목 추가'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: c,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '종목명 입력')),
              const SizedBox(height: 12),
              DropdownButton<String>(
                value: muscle,
                isExpanded: true,
                items: kMuscles
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setSt(() => muscle = v!),
              ),
              if (pastNames.isNotEmpty) ...[
                const SizedBox(height: 12),
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
      ),
    );

    if (name == null || name.isEmpty) return;
    session.exercises.add(
        widget.store.newExercise(name, session.date, fallbackMuscle: muscle));
    _changed();
  }

  Widget _backupBanner() {
    final d = widget.store.daysSinceBackup();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Expanded(
          child: Text(
            d == null
                ? '아직 백업하지 않았습니다. 브라우저 데이터를 지우면 기록이 사라집니다.'
                : '마지막 백업 후 $d일 지났습니다.',
            style: const TextStyle(fontSize: 11, color: Colors.amber),
          ),
        ),
        TextButton(
            onPressed: () => showDataDialog(context, widget.store),
            child: const Text('백업', style: TextStyle(fontSize: 12))),
      ]),
    );
  }

  Widget _workoutTimerBanner() {
    final isRunning = session.startTime != null && !session.isFinished;

    return Card(
      color: isRunning
          ? Colors.tealAccent.withOpacity(0.12)
          : Colors.white10,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isRunning ? Icons.timer : Icons.timer_outlined,
              color: isRunning ? Colors.tealAccent : Colors.grey,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.isFinished
                      ? '오늘 총 운동 시간'
                      : isRunning
                          ? '운동 진행 중'
                          : '운동 대기 중',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Text(
                  fmtDuration(session.durationSeconds),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isRunning ? Colors.tealAccent : Colors.white,
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (!session.isFinished)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRunning ? Colors.amber : Colors.tealAccent,
                  foregroundColor: Colors.black,
                ),
                icon: Icon(isRunning ? Icons.pause : Icons.play_arrow),
                label: Text(isRunning ? '일시정지' : '운동 시작'),
                onPressed: _toggleWorkoutStart,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.store;
    return Scaffold(
      appBar: AppBar(
        title: Text(isToday ? '오늘 운동' : session.date),
        actions: [
          IconButton(
            tooltip: '루틴 불러오기',
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: _loadRoutine,
          ),
        ],
      ),
      bottomNavigationBar: _restEnd == null ? null : _restBar(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.tealAccent,
        foregroundColor: Colors.black,
        onPressed: _addExercise,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          if (isToday && st.needsBackup) _backupBanner(),
          _workoutTimerBanner(),
          if (session.exercises.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  '종목이 없습니다.\n+ 버튼으로 추가하거나 상단 폴더 아이콘으로 루틴을 불러오세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            ),
          for (final ex in session.exercises)
            ExerciseCard(
              key: ObjectKey(ex),
              store: st,
              session: session,
              e: ex,
              onChanged: _changed,
              onRemove: () {
                session.exercises.remove(ex);
                _changed();
              },
              onSetDone: () {
                if (_isLive) _startRest(st.defaultRestSeconds);
              },
            ),
          if (session.exercises.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey('sn_${session.date}'),
              initialValue: session.sessionNote,
              maxLines: null,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: '세션 메모 (컨디션, 특이사항)',
                isDense: true,
                prefixIcon: Icon(Icons.notes, size: 16),
              ),
              onChanged: (v) {
                session.sessionNote = v;
                st.save();
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor:
                    session.isFinished ? Colors.green : Colors.grey[800],
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
              ),
              icon: Icon(
                  session.isFinished
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18),
              label: Text(session.isFinished ? '운동 완료됨 (탭하면 취소)' : '운동 완료'),
              onPressed: _toggleFinish,
            ),
          ],
        ],
      ),
    );
  }
}