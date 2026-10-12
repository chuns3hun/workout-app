import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<String> kMuscles = ['가슴', '등', '어깨', '하체', '이두', '삼두', '복근', '기타'];

// iOS 숫자 키패드에는 소수점이 없으므로 decimal 옵션 필요 (62.5kg 입력용)
const TextInputType kDecimalKb = TextInputType.numberWithOptions(decimal: true);

String _fmt(double w) =>
    w == w.truncateToDouble() ? w.toInt().toString() : w.toStringAsFixed(1);

String dateKey(DateTime n) =>
    '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';

DateTime weekStart(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

void _download(String content, String filename, String mime) {
  final blob = html.Blob([utf8.encode(content)], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  Future.delayed(
      const Duration(seconds: 1), () => html.Url.revokeObjectUrl(url));
}

// ---------- 세트 타입 및 모델 ----------
enum SetType { WARMUP, MAIN, DROP }

extension SetTypeExt on SetType {
  String get label {
    switch (this) {
      case SetType.WARMUP:
        return '웜업';
      case SetType.MAIN:
        return '작업';
      case SetType.DROP:
        return '드롭';
    }
  }
}

class SetEntry {
  double weight;
  int reps;
  bool done;
  SetType type;
  double? rpe;

  SetEntry({
    this.weight = 0,
    this.reps = 0,
    this.done = false,
    this.type = SetType.MAIN,
    this.rpe,
  });

  double get estimated1RM => reps > 0 ? weight * (1 + reps / 30.0) : 0;

  Map<String, dynamic> toJson() => {
        'w': weight,
        'r': reps,
        'd': done,
        't': type.index,
        'rpe': rpe,
      };

  factory SetEntry.fromJson(Map<String, dynamic> j) => SetEntry(
        weight: (j['w'] as num).toDouble(),
        reps: j['r'] as int,
        done: j['d'] as bool,
        type: SetType.values[(j['t'] as int?) ?? 1],
        rpe: (j['rpe'] as num?)?.toDouble(),
      );
}

class Exercise {
  String name;
  String targetMuscle;
  List<SetEntry> sets;
  String memo;
  String supersetGroup;
  int minReps;
  int maxReps;
  bool isCollapsed;
  int rev = 0;

  Exercise(
    this.name,
    this.sets, {
    this.targetMuscle = '기타',
    this.memo = '',
    this.supersetGroup = 'NONE',
    this.minReps = 8,
    this.maxReps = 12,
    this.isCollapsed = false,
  });

  double get volume => sets
      .where((s) => s.done && s.type != SetType.WARMUP)
      .fold(0.0, (a, s) => a + s.weight * s.reps);

  double get max1RM => sets
      .where((s) => s.done && s.type != SetType.WARMUP)
      .fold(0.0, (m, s) => s.estimated1RM > m ? s.estimated1RM : m);

  Map<String, dynamic> toJson() => {
        'n': name,
        'tm': targetMuscle,
        's': sets.map((e) => e.toJson()).toList(),
        'memo': memo,
        'ss': supersetGroup,
        'minR': minReps,
        'maxR': maxReps,
        'col': isCollapsed,
      };

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        j['n'] as String,
        (j['s'] as List)
            .map((e) => SetEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        targetMuscle: j['tm'] as String? ?? '기타',
        memo: j['memo'] as String? ?? '',
        supersetGroup: j['ss'] as String? ?? 'NONE',
        minReps: j['minR'] as int? ?? 8,
        maxReps: j['maxR'] as int? ?? 12,
        isCollapsed: j['col'] as bool? ?? false,
      );
}

class Session {
  String date;
  List<Exercise> exercises;
  String? routine;
  bool isFinished;
  String sessionNote;

  Session(
    this.date,
    this.exercises, [
    this.routine,
    this.isFinished = false,
    this.sessionNote = '',
  ]);

  double get volume => exercises.fold(0.0, (a, e) => a + e.volume);

  String get summaryText {
    if (routine != null && routine!.isNotEmpty) return routine!;
    if (exercises.isNotEmpty) {
      final names = exercises.map((e) => e.name).take(2).join(', ');
      return exercises.length > 2 ? '$names..' : names;
    }
    return '';
  }

  Map<String, dynamic> toJson() => {
        'd': date,
        'e': exercises.map((e) => e.toJson()).toList(),
        'rt': routine,
        'fin': isFinished,
        'sn': sessionNote,
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        j['d'] as String,
        (j['e'] as List)
            .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
            .toList(),
        j['rt'] as String?,
        (j['fin'] as bool?) ?? false,
        j['sn'] as String? ?? '',
      );
}

class Routine {
  String name;
  List<String> exercises;
  Routine(this.name, this.exercises);

  Map<String, dynamic> toJson() => {'n': name, 'x': exercises};
  factory Routine.fromJson(Map<String, dynamic> j) => Routine(
        j['n'] as String,
        (j['x'] as List).map((e) => e as String).toList(),
      );
}

class BodyRecord {
  String date;
  double weight;
  double? muscle;
  double? fat;

  BodyRecord(this.date, this.weight, [this.muscle, this.fat]);

  Map<String, dynamic> toJson() => {
        'd': date,
        'w': weight,
        'm': muscle,
        'f': fat,
      };

  factory BodyRecord.fromJson(Map<String, dynamic> j) => BodyRecord(
        j['d'] as String,
        (j['w'] as num).toDouble(),
        (j['m'] as num?)?.toDouble(),
        (j['f'] as num?)?.toDouble(),
      );
}

// ---------- 저장소 ----------
class Store {
  final List<Session> sessions = [];
  final List<Routine> routines = [];
  final List<BodyRecord> bodyRecords = [];
  int defaultRestSeconds = 90;
  String? lastBackup;

  static const _keys = ['sessions', 'routines', 'body_records', 'rest_sec'];

  static List<T> _l<T>(dynamic raw, T Function(Map<String, dynamic>) f) =>
      ((raw as List?) ?? []).map((e) => f(e as Map<String, dynamic>)).toList();

  // 종목이 없는 빈 세션은 저장하지 않음
  Map<String, dynamic> _toMap() => {
        'sessions': sessions
            .where((s) => s.exercises.isNotEmpty)
            .map((s) => s.toJson())
            .toList(),
        'routines': routines.map((r) => r.toJson()).toList(),
        'body_records': bodyRecords.map((b) => b.toJson()).toList(),
        'rest_sec': defaultRestSeconds,
      };

  void _apply(Map<String, dynamic> m) {
    if (m['sessions'] != null) {
      final l = _l(m['sessions'], Session.fromJson)
          .where((s) => s.exercises.isNotEmpty)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      sessions
        ..clear()
        ..addAll(l);
    }
    if (m['routines'] != null) {
      routines
        ..clear()
        ..addAll(_l(m['routines'], Routine.fromJson));
    }
    if (m['body_records'] != null) {
      bodyRecords
        ..clear()
        ..addAll(_l(m['body_records'], BodyRecord.fromJson)
          ..sort((a, b) => a.date.compareTo(b.date)));
    }
    if (m['rest_sec'] != null) {
      defaultRestSeconds = m['rest_sec'] as int? ?? 90;
    }
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final m = <String, dynamic>{};
    for (final k in _keys) {
      final s = p.getString(k);
      if (s != null) m[k] = jsonDecode(s);
    }
    _apply(m);
    lastBackup = p.getString('last_backup');
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    final m = _toMap();
    for (final k in _keys) {
      await p.setString(k, jsonEncode(m[k]));
    }
  }

  Future<void> markBackup() async {
    lastBackup = dateKey(DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setString('last_backup', lastBackup!);
  }

  int? daysSinceBackup() {
    if (lastBackup == null) return null;
    final d = DateTime.tryParse(lastBackup!);
    if (d == null) return null;
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
  }

  // 기록이 3회 이상 쌓였고, 백업이 없거나 14일 이상 지났을 때
  bool get needsBackup {
    if (sessions.where((s) => s.exercises.isNotEmpty).length < 3) return false;
    final d = daysSinceBackup();
    return d == null || d >= 14;
  }

  String exportJson() => jsonEncode(_toMap());

  String exportCsv() {
    final sb = StringBuffer();
    sb.writeln(
        'Date,Routine,Exercise,TargetMuscle,SetType,Weight,Reps,RPE,Completed');
    for (final s in sessions) {
      for (final e in s.exercises) {
        for (final set in e.sets) {
          sb.writeln(
              '${s.date},"${s.routine ?? ''}","${e.name}","${e.targetMuscle}",${set.type.label},${set.weight},${set.reps},${set.rpe ?? ''},${set.done}');
        }
      }
    }
    return sb.toString();
  }

  Future<void> importJson(String raw) async {
    final d = jsonDecode(raw);
    final map = d is List ? {'sessions': d} : d as Map<String, dynamic>;
    if (!map.containsKey('sessions')) {
      throw const FormatException('백업 파일 형식이 아닙니다.');
    }
    final before = jsonDecode(jsonEncode(_toMap())) as Map<String, dynamic>;
    try {
      _apply(map);
    } catch (e) {
      _apply(before);
      rethrow;
    }
    await save();
  }

  Session today() {
    final k = dateKey(DateTime.now());
    return sessions.firstWhere((s) => s.date == k, orElse: () {
      final s = Session(k, []);
      sessions.add(s);
      return s;
    });
  }

  List<String> getAllExerciseNames() {
    final names = <String>{};
    for (final r in routines) names.addAll(r.exercises);
    for (final s in sessions) {
      for (final e in s.exercises) {
        if (e.name.isNotEmpty) names.add(e.name);
      }
    }
    return names.toList()..sort();
  }

  // 최근에 수행한 순서 → 루틴 종목 순
  List<String> recentExerciseNames() {
    final names = <String>[];
    for (final s in sessions.reversed) {
      for (final e in s.exercises) {
        if (e.name.isNotEmpty && !names.contains(e.name)) names.add(e.name);
      }
    }
    for (final r in routines) {
      for (final n in r.exercises) {
        if (!names.contains(n)) names.add(n);
      }
    }
    return names;
  }

  Exercise? lastExercise(String name, String date) {
    for (final s in sessions.reversed) {
      if (s.date.compareTo(date) >= 0) continue;
      for (final e in s.exercises) {
        if (e.name == name) return e;
      }
    }
    return null;
  }

  // 이전 기록이 있으면 부위·목표 횟수·메모를 이어받음
  Exercise newExercise(String name, String date,
      {String fallbackMuscle = '기타'}) {
    final last = lastExercise(name, date);
    final prev = previous(name, date);
    return Exercise(
      name,
      prev.isEmpty ? [SetEntry()] : prev,
      targetMuscle: last?.targetMuscle ?? fallbackMuscle,
      memo: last?.memo ?? '',
      minReps: last?.minReps ?? 8,
      maxReps: last?.maxReps ?? 12,
    );
  }

  List<SetEntry> previous(String name, String date) {
    for (final s in sessions.reversed) {
      if (s.date.compareTo(date) >= 0) continue;
      for (final e in s.exercises) {
        if (e.name == name) {
          return e.sets
              .map((x) => SetEntry(
                    weight: x.weight,
                    reps: x.reps,
                    type: x.type,
                    rpe: x.rpe,
                  ))
              .toList();
        }
      }
    }
    return [];
  }

  double pr(String name) {
    double m = 0;
    for (final s in sessions) {
      for (final e in s.exercises) {
        if (e.name != name) continue;
        for (final x in e.sets) {
          if (x.done && x.type != SetType.WARMUP && x.weight > m) {
            m = x.weight;
          }
        }
      }
    }
    return m;
  }

  String recommendNext(Exercise e, String date) {
    final prevSets =
        previous(e.name, date).where((s) => s.type == SetType.MAIN).toList();
    if (prevSets.isEmpty) return '기록 부족 (첫 수행)';

    final lastWeight = prevSets.first.weight;
    final lastReps = prevSets.first.reps;
    final lastRpe = prevSets.first.rpe ?? 8.0;

    if (lastReps >= e.maxReps && lastRpe <= 8.5) {
      return '🎯 목표 달성! ${_fmt(lastWeight + 2.5)}kg 추천';
    }

    if (lastRpe <= 7.0) {
      return '추천: ${_fmt(lastWeight + 2.5)}kg × ${lastReps}회';
    } else if (lastRpe >= 9.5) {
      return '추천: ${_fmt(lastWeight)}kg × ${lastReps}회 (중량 유지)';
    } else {
      return '추천: ${_fmt(lastWeight)}kg × ${lastReps + 1}회 (+1회 도전)';
    }
  }

  List<MapEntry<String, double>> get1RMHistory(String exerciseName) {
    final List<MapEntry<String, double>> history = [];
    for (final s in sessions) {
      for (final e in s.exercises) {
        if (e.name == exerciseName && e.max1RM > 0) {
          history.add(MapEntry(s.date, e.max1RM));
        }
      }
    }
    return history;
  }
}

Widget lineChart(List<double> ys) {
  if (ys.length < 2) {
    return const SizedBox(
        height: 100,
        child: Center(
            child: Text('기록 2개 이상부터 그래프 표시',
                style: TextStyle(color: Colors.grey, fontSize: 12))));
  }

  final minY = ys.reduce((a, b) => a < b ? a : b);
  final maxY = ys.reduce((a, b) => a > b ? a : b);
  final margin = (maxY - minY) == 0 ? 1.0 : (maxY - minY) * 0.1;

  return SizedBox(
    height: 160,
    child: Padding(
      padding: const EdgeInsets.only(right: 16, top: 16, left: 8, bottom: 8),
      child: LineChart(
        LineChartData(
          minY: minY - margin,
          maxY: maxY + margin,
          titlesData: const FlTitlesData(
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.white12, strokeWidth: 0.5),
            getDrawingVerticalLine: (_) =>
                FlLine(color: Colors.white12, strokeWidth: 0.5),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])
              ],
              isCurved: true,
              color: Colors.tealAccent,
              barWidth: 2,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.tealAccent.withOpacity(0.08),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  await store.load();
  runApp(MaterialApp(
    themeMode: ThemeMode.dark,
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF09090B),
      cardTheme: CardThemeData(
        color: const Color(0xFF121215),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF27272A), width: 1),
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: Colors.tealAccent,
        surface: Color(0xFF121215),
      ),
    ),
    home: SessionPage(store: store),
  ));
}

// ---------- 운동 기록 화면 ----------
class SessionPage extends StatefulWidget {
  final Store store;
  final Session? session;
  const SessionPage({super.key, required this.store, this.session});

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage>
    with WidgetsBindingObserver {
  late Session session;
  bool get isToday => widget.session == null;
  // 날짜가 오늘인 세션이면 휴식 타이머 사용
  bool get _isLive => session.date == dateKey(DateTime.now());

  Timer? _ticker;
  DateTime? _restEnd;

  @override
  void initState() {
    super.initState();
    session = widget.session ?? widget.store.today();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  // 앱을 켜 둔 채 날짜가 바뀐 경우 새 날짜 세션으로 전환
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    if (isToday && session.date != dateKey(DateTime.now())) {
      setState(() => session = widget.store.today());
    } else if (_restEnd != null) {
      setState(() {});
    }
  }

  void _save() => widget.store.save();

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

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

  void _toggleFinish() {
    setState(() {
      session.isFinished = !session.isFinished;
    });
    _save();
    if (session.isFinished) {
      _stopRest();
      _toast('🎉 운동 완료 기록됨');
    }
  }

  Widget _restBar() {
    final r = _remaining();
    final text = r == 0
        ? '휴식 종료'
        : '휴식 ${r ~/ 60}:${(r % 60).toString().padLeft(2, '0')}';
    return Container(
      color: const Color(0xFF18181B),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(text,
              style: const TextStyle(
                  color: Colors.tealAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const Spacer(),
          TextButton(
              onPressed: () => _startRest(r + 30),
              child: const Text('+30초', style: TextStyle(color: Colors.white70))),
          IconButton(
              icon: const Icon(Icons.close, size: 20), onPressed: _stopRest),
        ],
      ),
    );
  }

  // ----- 데이터 관리 (백업 / 복원) -----
  Future<void> _backup() async {
    final st = widget.store;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('데이터 관리'),
        content: Text('마지막 JSON 백업: ${st.lastBackup ?? '없음'}',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () async {
              _download(
                  st.exportJson(),
                  'workout_backup_${dateKey(DateTime.now())}.json',
                  'application/json');
              await st.markBackup();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) setState(() {});
            },
            child: const Text('JSON 백업'),
          ),
          TextButton(
            onPressed: () {
              // 엑셀에서 한글이 깨지지 않도록 BOM 추가
              _download('\uFEFF${st.exportCsv()}',
                  'workout_${dateKey(DateTime.now())}.csv', 'text/csv');
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('CSV 내보내기'),
          ),
          TextButton(
            onPressed: () {
              // 파일 선택은 사용자 탭 동작 안에서 바로 호출해야 iOS Safari에서 동작함
              _pickRestoreFile();
              Navigator.pop(ctx);
            },
            child: const Text('JSON 복원'),
          ),
        ],
      ),
    );
  }

  void _pickRestoreFile() {
    final input = html.FileUploadInputElement()
      ..accept = '.json,application/json';
    input.onChange.listen((_) => _readRestoreFile(input));
    input.click();
  }

  Future<void> _readRestoreFile(html.FileUploadInputElement input) async {
    final files = input.files;
    if (files == null || files.isEmpty) return;
    final reader = html.FileReader()..readAsText(files.first);
    await reader.onLoad.first;
    final raw = reader.result as String;
    if (!mounted) return;

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
              child: const Text('복원',
                  style: TextStyle(color: Colors.tealAccent))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await widget.store.importJson(raw);
      setState(() {
        _stopRestSilently();
        session = widget.store.today();
      });
      _toast('복원 완료');
    } catch (e) {
      _toast('복원 실패: 올바른 백업 파일이 아닙니다.');
    }
  }

  void _stopRestSilently() {
    _ticker?.cancel();
    _restEnd = null;
  }

  // ----- 휴식 시간 설정 -----
  Future<void> _setRest() async {
    final c = TextEditingController(text: '${widget.store.defaultRestSeconds}');
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
            Wrap(
              spacing: 6,
              children: [
                for (final s in [60, 90, 120, 180])
                  ActionChip(label: Text('$s초'), onPressed: () => c.text = '$s'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())),
              child: const Text('확인')),
        ],
      ),
    );
    if (v == null) return;
    widget.store.defaultRestSeconds = v.clamp(10, 900).toInt();
    _save();
    if (mounted) setState(() {});
    _toast('휴식 시간 ${widget.store.defaultRestSeconds}초로 설정됨');
  }

  // ----- 루틴 불러오기 -----
  Future<void> _loadRoutine() async {
    final routines = widget.store.routines;
    if (routines.isEmpty) {
      _toast('등록된 루틴이 없습니다.');
      return;
    }

    final selectedRoutine = await showDialog<Routine>(
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

    if (selectedRoutine == null) return;

    if (session.exercises.isNotEmpty) {
      final shouldReplace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('루틴 불러오기'),
          content: Text(
              '현재 화면에 작성된 종목들을 지우고 "${selectedRoutine.name}" 루틴으로 교체할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('덧붙이기'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('기존 항목 비우고 교체',
                  style: TextStyle(color: Colors.tealAccent)),
            ),
          ],
        ),
      );

      if (shouldReplace == null) return;

      if (shouldReplace == true) {
        setState(() {
          session.exercises.clear();
        });
      }
    }

    setState(() {
      for (final name in selectedRoutine.exercises) {
        if (session.exercises.any((e) => e.name == name)) continue;
        session.exercises.add(widget.store.newExercise(name, session.date));
      }
      session.routine = selectedRoutine.name;
    });
    _save();
    _toast('${selectedRoutine.name} 루틴을 불러왔습니다.');
  }

  // ----- 종목 추가 -----
  Future<void> _addExercise() async {
    final c = TextEditingController();
    String muscle = '가슴';
    final pastNames = widget.store.recentExerciseNames();

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
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
                )
              ]
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
    setState(() => session.exercises.add(
        widget.store.newExercise(name, session.date, fallbackMuscle: muscle)));
    _save();
  }

  // ----- 종목 설정 (부위 / 목표 횟수 / 메모) -----
  Future<void> _editExercise(Exercise e) async {
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
                Row(
                  children: [
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
                  ],
                ),
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

    setState(() {
      e.targetMuscle = muscle;
      e.minReps = mn;
      e.maxReps = mx;
      e.memo = memoC.text.trim();
    });
    _save();
  }

  void _copyPreviousSets(Exercise e) {
    final prev = widget.store.previous(e.name, session.date);
    if (prev.isEmpty) {
      _toast('이전 기록이 없습니다.');
      return;
    }
    setState(() {
      e.sets = prev
          .map((s) => SetEntry(
              weight: s.weight, reps: s.reps, type: s.type, rpe: s.rpe))
          .toList();
      e.rev++;
    });
    _save();
  }

  // 첫 작업 세트 바로 앞에 웜업 세트 삽입 (무게는 작업 세트의 50%를 2.5kg 단위로 반올림)
  void _addWarmup(Exercise e) {
    final firstWork = e.sets.indexWhere((s) => s.type != SetType.WARMUP);
    final pos = firstWork == -1 ? e.sets.length : firstWork;
    final ref = firstWork == -1 ? null : e.sets[firstWork];
    setState(() {
      e.sets.insert(
        pos,
        SetEntry(
          weight: ref == null ? 0 : ((ref.weight * 0.5) / 2.5).round() * 2.5,
          reps: ref == null ? 0 : 10,
          type: SetType.WARMUP,
        ),
      );
      e.rev++;
    });
    _save();
  }

  String _setLabel(Exercise e, int idx) {
    final t = e.sets[idx].type;
    if (t == SetType.WARMUP) return 'W';
    if (t == SetType.DROP) return 'D';
    return '${e.sets.take(idx + 1).where((x) => x.type == SetType.MAIN).length}';
  }

  Widget _card(Exercise e) {
    final pr = widget.store.pr(e.name);
    final rec = widget.store.recommendNext(e, session.date);
    final prevSets = widget.store.previous(e.name, session.date);

    String prevSummary = '이전 기록 없음';
    if (prevSets.isNotEmpty) {
      final summaryList = prevSets
          .asMap()
          .entries
          .map((entry) =>
              '${entry.key + 1}세트 ${_fmt(entry.value.weight)}kg×${entry.value.reps}회')
          .join(' | ');
      prevSummary = '이전: $summaryList';
    }

    return Card(
      key: ObjectKey(e),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(e.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(e.targetMuscle,
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                      e.isCollapsed
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      size: 20,
                      color: Colors.tealAccent),
                  onPressed: () {
                    setState(() => e.isCollapsed = !e.isCollapsed);
                    _save();
                  },
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '이전 기록 불러오기',
                  icon: const Icon(Icons.content_copy,
                      size: 16, color: Colors.tealAccent),
                  onPressed: () => _copyPreviousSets(e),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                  onSelected: (v) {
                    if (v == 'edit') {
                      _editExercise(e);
                    } else if (v == 'del') {
                      setState(() => session.exercises.remove(e));
                      _save();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('종목 설정')),
                    PopupMenuItem(value: 'del', child: Text('종목 삭제')),
                  ],
                ),
              ],
            ),
            if (e.isCollapsed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '${e.sets.length}세트 · PR ${_fmt(pr)}kg · 볼륨 ${_fmt(e.volume)}kg',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              )
            else ...[
              Text(
                  'PR ${_fmt(pr)}kg  ·  볼륨 ${_fmt(e.volume)}kg  ·  목표 ${e.minReps}~${e.maxReps}회',
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
              if (e.memo.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('메모: ${e.memo}',
                    style: const TextStyle(color: Colors.amber, fontSize: 11)),
              ],
              const SizedBox(height: 4),
              Text(prevSummary,
                  style: TextStyle(color: Colors.grey[400], fontSize: 11)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(rec,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.tealAccent)),
              ),
              const SizedBox(height: 8),
              for (var idx = 0; idx < e.sets.length; idx++)
                _setRow(e, e.sets[idx], idx,
                    prevSets.length > idx ? prevSets[idx] : null),
              Wrap(
                children: [
                  TextButton(
                    onPressed: () {
                      final last = e.sets.isEmpty ? null : e.sets.last;
                      setState(() => e.sets.add(SetEntry(
                            weight: last?.weight ?? 0,
                            reps: last?.reps ?? 0,
                            type: SetType.MAIN,
                          )));
                      _save();
                    },
                    child: const Text('+ 세트',
                        style: TextStyle(fontSize: 12, color: Colors.tealAccent)),
                  ),
                  TextButton(
                    onPressed: () => _addWarmup(e),
                    child: const Text('+ 웜업',
                        style: TextStyle(fontSize: 12, color: Colors.amber)),
                  ),
                  TextButton(
                    onPressed: () {
                      final last = e.sets.isEmpty ? null : e.sets.last;
                      if (last == null) return;
                      setState(() => e.sets.add(SetEntry(
                            weight: (last.weight * 0.8).roundToDouble(),
                            reps: last.reps,
                            type: SetType.DROP,
                          )));
                      _save();
                    },
                    child: const Text('-20% 드롭',
                        style:
                            TextStyle(fontSize: 12, color: Colors.amberAccent)),
                  ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _setRow(Exercise e, SetEntry s, int idx, SetEntry? prevSet) {
    final prevWHint = prevSet != null ? '${_fmt(prevSet.weight)}kg' : 'kg';
    final prevRHint = prevSet != null ? '${prevSet.reps}회' : '회';
    final prevRpeHint = prevSet?.rpe != null ? _fmt(prevSet!.rpe!) : 'RPE';

    final label = _setLabel(e, idx);
    final Color labelColor = s.type == SetType.WARMUP
        ? Colors.amber
        : s.type == SetType.DROP
            ? Colors.orangeAccent
            : Colors.grey;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          // 번호를 탭하면 웜업 → 작업 → 드롭 순으로 타입 변경
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() {
                s.type = SetType.values[(s.type.index + 1) % SetType.values.length];
              });
              _save();
            },
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: labelColor.withOpacity(0.6)),
              ),
              child: Text(label,
                  style: TextStyle(color: labelColor, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              key: ValueKey('w_${e.rev}_$idx'),
              initialValue: s.weight == 0 ? '' : _fmt(s.weight),
              decoration: InputDecoration(
                hintText: prevWHint,
                hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                isDense: true,
                border: InputBorder.none,
              ),
              keyboardType: kDecimalKb,
              style: const TextStyle(fontSize: 14),
              onChanged: (v) {
                s.weight = parseNum(v) ?? 0;
                _save();
              },
            ),
          ),
          Expanded(
            child: TextFormField(
              key: ValueKey('r_${e.rev}_$idx'),
              initialValue: s.reps == 0 ? '' : '${s.reps}',
              decoration: InputDecoration(
                hintText: prevRHint,
                hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                isDense: true,
                border: InputBorder.none,
              ),
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 14),
              onChanged: (v) {
                s.reps = int.tryParse(v) ?? 0;
                _save();
              },
            ),
          ),
          SizedBox(
            width: 52,
            child: TextFormField(
              key: ValueKey('p_${e.rev}_$idx'),
              initialValue: s.rpe == null ? '' : _fmt(s.rpe!),
              decoration: InputDecoration(
                hintText: prevRpeHint,
                hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                isDense: true,
                border: InputBorder.none,
              ),
              keyboardType: kDecimalKb,
              style: const TextStyle(fontSize: 14),
              onChanged: (v) {
                final n = parseNum(v);
                s.rpe = (n != null && n >= 1 && n <= 10) ? n : null;
                _save();
              },
            ),
          ),
          Checkbox(
            value: s.done,
            activeColor: Colors.tealAccent,
            checkColor: Colors.black,
            onChanged: (v) {
              setState(() => s.done = v ?? false);
              _save();
              if (v == true && _isLive) {
                _startRest(widget.store.defaultRestSeconds);
              }
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove, size: 14, color: Colors.grey),
            onPressed: () {
              setState(() {
                e.sets.removeAt(idx);
                e.rev++; // 입력창 상태를 새로 만들어 값 불일치 방지
              });
              _save();
            },
          )
        ],
      ),
    );
  }

  Widget _nav(String title, IconData icon, Widget Function() page) => ListTile(
        leading: Icon(icon, color: Colors.tealAccent, size: 20),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        onTap: () async {
          Navigator.pop(context);
          await Navigator.push(
              context, MaterialPageRoute(builder: (_) => page()));
          if (mounted) setState(() {});
        },
      );

  Widget _backupBanner() {
    final d = widget.store.daysSinceBackup();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              d == null
                  ? '아직 백업하지 않았습니다. 브라우저 데이터를 지우면 기록이 사라집니다.'
                  : '마지막 백업 후 $d일 지났습니다.',
              style: const TextStyle(fontSize: 11, color: Colors.amber),
            ),
          ),
          TextButton(
              onPressed: _backup,
              child: const Text('백업', style: TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.store;
    return Scaffold(
      appBar: AppBar(
        title: Text(isToday ? '오늘 운동' : session.date,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      drawer: isToday
          ? Drawer(
              backgroundColor: const Color(0xFF121215),
              child: ListView(children: [
                const DrawerHeader(
                  child: Center(
                    child: Text('WORKOUT LOG',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.tealAccent)),
                  ),
                ),
                _nav('달력', Icons.calendar_today, () => CalendarPage(store: st)),
                _nav('루틴 관리', Icons.folder_open, () => RoutinePage(store: st)),
                _nav('신체 기록', Icons.show_chart, () => BodyPage(store: st)),
                _nav('운동 목록', Icons.history, () => HistoryPage(store: st)),
                _nav('통계 & 1RM', Icons.bar_chart, () => StatsPage(store: st)),
                ListTile(
                  leading: const Icon(Icons.timer, color: Colors.tealAccent, size: 20),
                  title: const Text('휴식 시간', style: TextStyle(fontSize: 14)),
                  trailing: Text('${st.defaultRestSeconds}초',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    _setRest();
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.download, color: Colors.tealAccent, size: 20),
                  title: const Text('데이터 관리 (백업·복원)',
                      style: TextStyle(fontSize: 14)),
                  onTap: () {
                    Navigator.pop(context);
                    _backup();
                  },
                ),
              ]),
            )
          : null,
      bottomNavigationBar: _restEnd == null ? null : _restBar(),
      floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.tealAccent,
          foregroundColor: Colors.black,
          onPressed: _addExercise,
          child: const Icon(Icons.add)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
        children: [
          if (isToday && st.needsBackup) _backupBanner(),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('루틴 불러오기', style: TextStyle(fontSize: 12)),
                onPressed: _loadRoutine,
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      session.isFinished ? Colors.green : Colors.grey[800],
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: Icon(
                    session.isFinished
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 16),
                label: Text(session.isFinished ? '오늘 운동 완료' : '운동 완료하기',
                    style: const TextStyle(fontSize: 12)),
                onPressed: _toggleFinish,
              )
            ],
          ),
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
              _save();
            },
          ),
          const SizedBox(height: 8),
          for (final e in session.exercises) _card(e),
        ],
      ),
    );
  }
}

// ---------- 달력 화면 ----------
class CalendarPage extends StatefulWidget {
  final Store store;
  const CalendarPage({super.key, required this.store});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedMonth = DateTime.now();

  void _moveMonth(int delta) {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth =
        DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final firstDayOfWeek =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday % 7;
    final now = DateTime.now();
    final todayStr = dateKey(now);

    return Scaffold(
      appBar: AppBar(
        title: Text('${_focusedMonth.year}년 ${_focusedMonth.month}월'),
        actions: [
          IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _moveMonth(-1)),
          IconButton(
              icon: const Icon(Icons.today),
              onPressed: () => setState(() => _focusedMonth = DateTime.now())),
          IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _moveMonth(1)),
        ],
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: const [
              Text('일', style: TextStyle(color: Colors.red, fontSize: 12)),
              Text('월', style: TextStyle(fontSize: 12)),
              Text('화', style: TextStyle(fontSize: 12)),
              Text('수', style: TextStyle(fontSize: 12)),
              Text('목', style: TextStyle(fontSize: 12)),
              Text('금', style: TextStyle(fontSize: 12)),
              Text('토', style: TextStyle(color: Colors.blue, fontSize: 12)),
            ],
          ),
          const Divider(),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(6),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.8,
              ),
              itemCount: firstDayOfWeek + daysInMonth,
              itemBuilder: (context, index) {
                if (index < firstDayOfWeek) return const SizedBox.shrink();
                final day = index - firstDayOfWeek + 1;
                final date =
                    DateTime(_focusedMonth.year, _focusedMonth.month, day);
                final dKey = dateKey(date);

                final session = widget.store.sessions.firstWhere(
                  (s) => s.date == dKey,
                  orElse: () => Session(dKey, []),
                );

                final hasData = session.exercises.isNotEmpty;
                Color bgColor = Colors.transparent;

                if (hasData) {
                  bgColor = session.isFinished
                      ? Colors.green.withOpacity(0.35)
                      : Colors.redAccent.withOpacity(0.35);
                }

                final summary = session.summaryText;

                return GestureDetector(
                  onTap: () async {
                    if (hasData) {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SessionPage(
                              store: widget.store, session: session),
                        ),
                      );
                      // 완료 상태가 바뀌었을 수 있으므로 갱신
                      if (mounted) setState(() {});
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: dKey == todayStr
                          ? Border.all(color: Colors.tealAccent, width: 1.5)
                          : Border.all(color: Colors.white10, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: dKey == todayStr
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: dKey == todayStr
                                ? Colors.tealAccent
                                : Colors.white,
                          ),
                        ),
                        if (summary.isNotEmpty) ...[
                          const Spacer(),
                          Text(
                            summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white70,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- 신체 변화 기록 화면 ----------
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

  int _selectedMetric = 0;

  void _addRecord() {
    final w = parseNum(_wCtrl.text);
    if (w == null) return;
    final m = parseNum(_mCtrl.text);
    final f = parseNum(_fCtrl.text);

    setState(() {
      widget.store.bodyRecords
          .add(BodyRecord(dateKey(DateTime.now()), w, m, f));
    });
    widget.store.save();
    _wCtrl.clear();
    _mCtrl.clear();
    _fCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.store.bodyRecords.reversed.toList();

    List<double> chartData = [];
    String metricLabel = '';
    String unit = '';

    if (_selectedMetric == 0) {
      chartData = widget.store.bodyRecords.map((r) => r.weight).toList();
      metricLabel = '체중';
      unit = 'kg';
    } else if (_selectedMetric == 1) {
      chartData = widget.store.bodyRecords
          .where((r) => r.muscle != null)
          .map((r) => r.muscle!)
          .toList();
      metricLabel = '골격근량';
      unit = 'kg';
    } else {
      chartData = widget.store.bodyRecords
          .where((r) => r.fat != null)
          .map((r) => r.fat!)
          .toList();
      metricLabel = '체지방률';
      unit = '%';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('신체 변화 기록')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                  child: TextField(
                      controller: _wCtrl,
                      decoration: const InputDecoration(labelText: '체중(kg)'),
                      keyboardType: kDecimalKb)),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _mCtrl,
                      decoration: const InputDecoration(labelText: '골격근량(kg)'),
                      keyboardType: kDecimalKb)),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _fCtrl,
                      decoration: const InputDecoration(labelText: '체지방률(%)'),
                      keyboardType: kDecimalKb)),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addRecord,
                child: const Text('입력'),
              )
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('체중'),
                selected: _selectedMetric == 0,
                onSelected: (selected) {
                  if (selected) setState(() => _selectedMetric = 0);
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('골격근량'),
                selected: _selectedMetric == 1,
                onSelected: (selected) {
                  if (selected) setState(() => _selectedMetric = 1);
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('체지방률'),
                selected: _selectedMetric == 2,
                onSelected: (selected) {
                  if (selected) setState(() => _selectedMetric = 2);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('$metricLabel 추이 ($unit)',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          lineChart(chartData),
          const Divider(),
          for (final r in records)
            ListTile(
              title: Text('${r.date}: ${_fmt(r.weight)}kg'),
              subtitle: Text(
                  '골격근량: ${r.muscle != null ? _fmt(r.muscle!) : "-"}kg · 체지방률: ${r.fat != null ? _fmt(r.fat!) : "-"}%'),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                onPressed: () {
                  setState(() {
                    widget.store.bodyRecords.remove(r);
                  });
                  widget.store.save();
                },
              ),
            )
        ],
      ),
    );
  }
}

// ---------- 루틴 관리 ----------
class RoutinePage extends StatefulWidget {
  final Store store;
  const RoutinePage({super.key, required this.store});

  @override
  State<RoutinePage> createState() => _RoutinePageState();
}

class _RoutinePageState extends State<RoutinePage> {
  Future<void> _addExerciseToRoutine(Routine r) async {
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
              )
            ]
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty || r.exercises.contains(name)) return;
    setState(() => r.exercises.add(name));
    widget.store.save();
  }

  @override
  Widget build(BuildContext context) {
    final routines = widget.store.routines;
    return Scaffold(
      appBar: AppBar(title: const Text('루틴 관리')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.tealAccent,
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
        onPressed: () async {
          final c = TextEditingController();
          final name = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('새 루틴 이름'),
              content: TextField(controller: c, autofocus: true),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, c.text.trim()),
                    child: const Text('확인'))
              ],
            ),
          );
          if (name != null && name.isNotEmpty) {
            setState(() => widget.store.routines.add(Routine(name, [])));
            widget.store.save();
          }
        },
      ),
      body: ListView(
        children: [
          for (final r in routines)
            ExpansionTile(
              title: Text(r.name,
                  style: const TextStyle(
                      color: Colors.tealAccent, fontWeight: FontWeight.bold)),
              subtitle: Text('${r.exercises.length}개 종목 등록됨'),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                onPressed: () {
                  setState(() => widget.store.routines.remove(r));
                  widget.store.save();
                },
              ),
              children: [
                for (var i = 0; i < r.exercises.length; i++)
                  ListTile(
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('운동 종목 추가',
                            style: TextStyle(fontSize: 12)),
                        onPressed: () => _addExerciseToRoutine(r),
                      ),
                    ],
                  ),
                )
              ],
            )
        ],
      ),
    );
  }
}

// ---------- 히스토리 ----------
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
              child: const Text('삭제',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => widget.store.sessions.remove(s));
    widget.store.save();
  }

  @override
  Widget build(BuildContext context) {
    // 종목이 없는 빈 세션은 표시하지 않음
    final list = widget.store.sessions
        .where((s) => s.exercises.isNotEmpty)
        .toList()
        .reversed
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('운동 목록')),
      body: ListView(children: [
        for (final s in list)
          ListTile(
            title: Text(s.date),
            subtitle: Text(
                '${s.summaryText.isEmpty ? '' : '${s.summaryText} · '}볼륨 ${_fmt(s.volume)}kg'),
            leading: Icon(
              s.isFinished ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: s.isFinished ? Colors.green : Colors.grey,
            ),
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
          )
      ]),
    );
  }
}

// ---------- 통계 ----------
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
    return _fmt(v);
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
            '최고 추정 1RM ${_fmt(best)}kg · PR ${_fmt(st.pr(_selected!))}kg · ${hist.length}회 수행',
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
        Row(
          children: [
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
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const Text('완료된 세트 없음',
              style: TextStyle(color: Colors.grey, fontSize: 12))
        else
          for (final en in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
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
                    width: 44,
                    child: Text('${en.value}세트',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }
}