import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _fmt(double w) =>
    w == w.truncateToDouble() ? w.toInt().toString() : w.toStringAsFixed(1);

String dateKey(DateTime n) =>
    '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';

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

  // 추정 1RM 계산 (Epley 공식: W * (1 + R/30))
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
  int rev = 0;

  Exercise(this.name, this.sets, {this.targetMuscle = '가슴', this.memo = ''});

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
      };

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        j['n'] as String,
        (j['s'] as List)
            .map((e) => SetEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        targetMuscle: j['tm'] as String? ?? '기타',
        memo: j['memo'] as String? ?? '',
      );
}

class Session {
  String date;
  List<Exercise> exercises;
  String? routine;
  bool isFinished;
  String sessionNote;

  Session(this.date, this.exercises,
      [this.routine, this.isFinished = false, this.sessionNote = '']);

  double get volume => exercises.fold(0.0, (a, e) => a + e.volume);

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

  static const _keys = ['sessions', 'routines', 'body_records', 'rest_sec'];

  static List<T> _l<T>(dynamic raw, T Function(Map<String, dynamic>) f) =>
      ((raw as List?) ?? []).map((e) => f(e as Map<String, dynamic>)).toList();

  Map<String, dynamic> _toMap() => {
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'routines': routines.map((r) => r.toJson()).toList(),
        'body_records': bodyRecords.map((b) => b.toJson()).toList(),
        'rest_sec': defaultRestSeconds,
      };

  void _apply(Map<String, dynamic> m) {
    if (m['sessions'] != null) {
      final l = _l(m['sessions'], Session.fromJson)
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
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    final m = _toMap();
    for (final k in _keys) {
      await p.setString(k, jsonEncode(m[k]));
    }
  }

  String exportJson() => jsonEncode(_toMap());

  String exportCsv() {
    final sb = StringBuffer();
    sb.writeln('Date,Routine,Exercise,TargetMuscle,SetType,Weight,Reps,RPE,Completed');
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
    final before = jsonDecode(jsonEncode(_toMap())) as Map<String, dynamic>;
    try {
      _apply(d is List ? {'sessions': d} : d as Map<String, dynamic>);
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
          if (x.done && x.weight > m) m = x.weight;
        }
      }
    }
    return m;
  }

  String recommendNext(String name, String date) {
    final prevSets = previous(name, date).where((s) => s.type == SetType.MAIN).toList();
    if (prevSets.isEmpty) return '기록 부족 (첫 수행)';

    final lastWeight = prevSets.first.weight;
    final lastReps = prevSets.first.reps;
    final lastRpe = prevSets.first.rpe ?? 8.0;

    if (lastRpe <= 7.0) {
      return '추천: ${_fmt(lastWeight + 2.5)}kg × ${lastReps}회 (+2.5kg 증량 권장)';
    } else if (lastRpe >= 9.5) {
      return '추천: ${_fmt(lastWeight)}kg × ${lastReps}회 (현재 중량 유지)';
    } else {
      return '추천: ${_fmt(lastWeight)}kg × ${lastReps + 1}회 (+1회 도전 권장)';
    }
  }

  // 종목별 1RM 기록 추세 추출
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
        height: 120, child: Center(child: Text('기록 2개 이상부터 그래프 표시')));
  }

  final minY = ys.reduce((a, b) => a < b ? a : b);
  final maxY = ys.reduce((a, b) => a > b ? a : b);
  final margin = (maxY - minY) == 0 ? 1.0 : (maxY - minY) * 0.1;

  return SizedBox(
    height: 180,
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
                FlLine(color: Colors.white10, strokeWidth: 1),
            getDrawingVerticalLine: (_) =>
                FlLine(color: Colors.white10, strokeWidth: 1),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])
              ],
              isCurved: true,
              color: Colors.cyanAccent,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.cyanAccent.withOpacity(0.15),
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
      scaffoldBackgroundColor: const Color(0xFF121212),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E1E1E),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      colorScheme: const ColorScheme.dark(
        primary: Colors.cyanAccent,
        surface: Color(0xFF1E1E1E),
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

class _SessionPageState extends State<SessionPage> {
  late Session session;
  bool get isToday => widget.session == null;

  Timer? _ticker;
  DateTime? _restEnd;

  @override
  void initState() {
    super.initState();
    session = widget.session ?? widget.store.today();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
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
      setState(() {});
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
      _toast('🎉 오늘 운동 완료!');
    }
  }

  Widget _restBar() {
    final r = _remaining();
    final text = r == 0
        ? '휴식 종료!'
        : '휴식 중 ${r ~/ 60}:${(r % 60).toString().padLeft(2, '0')}';
    return Material(
      elevation: 8,
      color: const Color(0xFF2C2C2C),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                  child: Text(text,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: Colors.cyanAccent))),
              TextButton(
                  onPressed: () => _startRest(r + 30), child: const Text('+30초')),
              TextButton(onPressed: _stopRest, child: const Text('닫기')),
            ]),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('기본 휴식: ', style: TextStyle(fontSize: 12)),
                for (final sec in [60, 90, 120, 180])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ChoiceChip(
                      label: Text('${sec}초'),
                      selected: widget.store.defaultRestSeconds == sec,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            widget.store.defaultRestSeconds = sec;
                          });
                          _save();
                        }
                      },
                    ),
                  )
              ],
            )
          ],
        ),
      ),
    );
  }

  Future<void> _backup() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('백업 / 복원 / CSV'),
        content: const Text('원하는 작업을 선택하세요.'),
        actions: [
          TextButton(
            onPressed: () {
              final jsonStr = widget.store.exportJson();
              final bytes = utf8.encode(jsonStr);
              final blob = html.Blob([bytes]);
              final url = html.Url.createObjectUrlFromBlob(blob);
              html.AnchorElement(href: url)
                ..setAttribute("download", "workout_backup_${dateKey(DateTime.now())}.json")
                ..click();
              html.Url.revokeObjectUrl(url);
              if (ctx.mounted) Navigator.pop(ctx);
              _toast('JSON 백업 다운로드 시작');
            },
            child: const Text('JSON 백업'),
          ),
          TextButton(
            onPressed: () {
              final csvStr = widget.store.exportCsv();
              final bytes = utf8.encode(csvStr);
              final blob = html.Blob([bytes]);
              final url = html.Url.createObjectUrlFromBlob(blob);
              html.AnchorElement(href: url)
                ..setAttribute("download", "workout_data_${dateKey(DateTime.now())}.csv")
                ..click();
              html.Url.revokeObjectUrl(url);
              if (ctx.mounted) Navigator.pop(ctx);
              _toast('CSV 내보내기 시작');
            },
            child: const Text('CSV 내보내기'),
          ),
          TextButton(
            onPressed: () {
              final input = html.FileUploadInputElement()..accept = '.json';
              input.click();
              input.onChange.listen((e) {
                final files = input.files;
                if (files != null && files.isNotEmpty) {
                  final reader = html.FileReader();
                  reader.readAsText(files[0]);
                  reader.onLoadEnd.listen((e) async {
                    try {
                      final content = reader.result as String;
                      await widget.store.importJson(content);
                      session = widget.store.today();
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) setState(() {});
                      _toast('복원 완료!');
                    } catch (_) {
                      _toast('파일 오류');
                    }
                  });
                }
              });
            },
            child: const Text('JSON 복원'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadRoutine() async {
    final routines = widget.store.routines;
    if (routines.isEmpty) {
      _toast('등록된 루틴이 없습니다.');
      return;
    }
    final r = await showDialog<Routine>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('루틴 불러오기'),
        children: [
          for (final x in routines)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, x),
              child: Text('${x.name} (${x.exercises.length}개 종목)'),
            ),
        ],
      ),
    );
    if (r == null) return;
    setState(() {
      for (final name in r.exercises) {
        if (session.exercises.any((e) => e.name == name)) continue;
        final prev = widget.store.previous(name, session.date);
        session.exercises
            .add(Exercise(name, prev.isEmpty ? [SetEntry()] : prev));
      }
      session.routine = r.name;
    });
    _save();
  }

  Future<void> _addExercise() async {
    final c = TextEditingController();
    String muscle = '가슴';
    final pastNames = widget.store.getAllExerciseNames();

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          title: const Text('운동 종목 추가'),
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
                items: ['가슴', '등', '어깨', '하체', '이두', '삼두', '복근']
                    .map((m) => DropdownMenuItem(value: m, child: Text('타겟 부위: $m')))
                    .toList(),
                onChanged: (v) => setSt(() => muscle = v!),
              ),
              if (pastNames.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('이전 기록 종목 선택:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Wrap(
                  spacing: 4,
                  children: pastNames
                      .take(6)
                      .map((n) => ActionChip(
                            label: Text(n),
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
    final prev = widget.store.previous(name, session.date);
    setState(() => session.exercises.add(Exercise(
          name,
          prev.isEmpty ? [SetEntry()] : prev,
          targetMuscle: muscle,
        )));
    _save();
  }

  void _copyPreviousSets(Exercise e) {
    final prev = widget.store.previous(e.name, session.date);
    if (prev.isEmpty) {
      _toast('이전 기록이 없습니다.');
      return;
    }
    setState(() {
      e.sets = prev.map((s) => SetEntry(weight: s.weight, reps: s.reps, type: s.type, rpe: s.rpe)).toList();
      e.rev++;
    });
    _save();
    _toast('이전 기록을 복사했습니다.');
  }

  Widget _card(Exercise e) {
    final pr = widget.store.pr(e.name);
    final rec = widget.store.recommendNext(e.name, session.date);

    return Card(
      key: ObjectKey(e),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(e.name,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.cyanAccent)),
              const SizedBox(width: 8),
              Chip(
                label: Text(e.targetMuscle, style: const TextStyle(fontSize: 10)),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('이전 기록 복사', style: TextStyle(fontSize: 11)),
                onPressed: () => _copyPreviousSets(e),
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20),
                onPressed: () {
                  setState(() => session.exercises.remove(e));
                  _save();
                },
              ),
            ]),
            Text('PR: ${_fmt(pr)}kg · 볼륨: ${_fmt(e.volume)}kg · 최고1RM: ${_fmt(e.max1RM)}kg',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 16, color: Colors.cyanAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(rec,
                        style: const TextStyle(fontSize: 12, color: Colors.cyanAccent)),
                  ),
                ],
              ),
            ),
            for (var idx = 0; idx < e.sets.length; idx++) ...[
              _setRow(e, e.sets[idx], idx),
            ],
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('세트 추가'),
                  onPressed: () {
                    final last = e.sets.isEmpty ? null : e.sets.last;
                    setState(() => e.sets.add(SetEntry(
                          weight: last?.weight ?? 0,
                          reps: last?.reps ?? 0,
                          type: SetType.MAIN,
                        )));
                    _save();
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.south_west, size: 16, color: Colors.orangeAccent),
                  label: const Text('드롭세트(-20%)', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
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
                ),
              ],
            ),
            TextFormField(
              initialValue: e.memo,
              decoration: const InputDecoration(
                hintText: '종목 메모 (예: 의자 높이 3번, 자극 집중)',
                isDense: true,
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) {
                e.memo = v;
                _save();
              },
            )
          ],
        ),
      ),
    );
  }

  Widget _setRow(Exercise e, SetEntry s, int idx) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          DropdownButton<SetType>(
            value: s.type,
            underline: const SizedBox(),
            items: SetType.values
                .map((t) => DropdownMenuItem(value: t, child: Text(t.label, style: const TextStyle(fontSize: 12))))
                .toList(),
            onChanged: (v) {
              setState(() => s.type = v!);
              _save();
            },
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextFormField(
              key: ValueKey('w_${e.rev}_$idx'),
              initialValue: s.weight == 0 ? '' : _fmt(s.weight),
              decoration: const InputDecoration(labelText: 'kg', isDense: true),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                s.weight = double.tryParse(v) ?? 0;
                _save();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              key: ValueKey('r_${e.rev}_$idx'),
              initialValue: s.reps == 0 ? '' : '${s.reps}',
              decoration: const InputDecoration(labelText: '회', isDense: true),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                s.reps = int.tryParse(v) ?? 0;
                _save();
              },
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<double?>(
            value: s.rpe,
            hint: const Text('RPE', style: TextStyle(fontSize: 11)),
            underline: const SizedBox(),
            items: [6.0, 7.0, 8.0, 8.5, 9.0, 9.5, 10.0]
                .map((r) => DropdownMenuItem(value: r, child: Text('@$r', style: const TextStyle(fontSize: 11))))
                .toList(),
            onChanged: (v) {
              setState(() => s.rpe = v);
              _save();
            },
          ),
          Checkbox(
            value: s.done,
            activeColor: Colors.cyanAccent,
            checkColor: Colors.black,
            onChanged: (v) {
              setState(() => s.done = v ?? false);
              _save();
              if (v == true && isToday) _startRest(widget.store.defaultRestSeconds);
            },
          ),
        ],
      ),
    );
  }

  Widget _nav(String title, IconData icon, Widget Function() page) => ListTile(
        leading: Icon(icon, color: Colors.cyanAccent),
        title: Text(title),
        onTap: () async {
          Navigator.pop(context);
          await Navigator.push(
              context, MaterialPageRoute(builder: (_) => page()));
          if (mounted) setState(() {});
        },
      );

  @override
  Widget build(BuildContext context) {
    final st = widget.store;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(isToday ? '오늘 운동 ${session.date}' : session.date),
            if (session.isFinished) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('완료됨', style: TextStyle(fontSize: 12, color: Colors.white)),
              )
            ]
          ],
        ),
      ),
      drawer: isToday
          ? Drawer(
              child: ListView(children: [
                const DrawerHeader(
                  child: Center(
                    child: Text('WORKOUT LOG',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.cyanAccent)),
                  ),
                ),
                _nav('달력 (출석/완료)', Icons.calendar_month, () => CalendarPage(store: st)),
                _nav('루틴 관리', Icons.folder, () => RoutinePage(store: st)),
                _nav('신체 기록 (체중/근육량)', Icons.monitor_weight, () => BodyPage(store: st)),
                _nav('운동 기록 목록', Icons.history, () => HistoryPage(store: st)),
                _nav('통계 & 부위별 볼륨 & 1RM', Icons.bar_chart, () => StatsPage(store: st)),
                ListTile(
                  leading: const Icon(Icons.save_alt, color: Colors.cyanAccent),
                  title: const Text('백업 / 복원 / CSV'),
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
          backgroundColor: Colors.cyanAccent,
          foregroundColor: Colors.black,
          onPressed: _addExercise,
          child: const Icon(Icons.add)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        children: [
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('루틴 불러오기'),
                onPressed: _loadRoutine,
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: session.isFinished ? Colors.grey[800] : Colors.cyanAccent,
                  foregroundColor: session.isFinished ? Colors.white : Colors.black,
                ),
                icon: Icon(session.isFinished ? Icons.undo : Icons.check_circle),
                label: Text(session.isFinished ? '완료 취소' : '운동 완료'),
                onPressed: _toggleFinish,
              ),
            ],
          ),
          TextFormField(
            initialValue: session.sessionNote,
            decoration: const InputDecoration(
              hintText: '오늘 컨디션 / 피로도 / 운동 메모 입력',
              prefixIcon: Icon(Icons.edit_note, color: Colors.cyanAccent),
            ),
            onChanged: (v) {
              session.sessionNote = v;
              _save();
            },
          ),
          const SizedBox(height: 12),
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

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final firstDayOfWeek = DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday % 7;
    final now = DateTime.now();
    final todayStr = dateKey(now);

    return Scaffold(
      appBar: AppBar(
        title: Text('${_focusedMonth.year}년 ${_focusedMonth.month}월'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() {
              _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
            }),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() {
              _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: const [
              Text('일', style: TextStyle(color: Colors.red)),
              Text('월'), Text('화'), Text('수'), Text('목'), Text('금'),
              Text('토', style: TextStyle(color: Colors.blue)),
            ],
          ),
          const Divider(),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.0,
              ),
              itemCount: firstDayOfWeek + daysInMonth,
              itemBuilder: (context, index) {
                if (index < firstDayOfWeek) return const SizedBox.shrink();
                final day = index - firstDayOfWeek + 1;
                final date = DateTime(_focusedMonth.year, _focusedMonth.month, day);
                final dKey = dateKey(date);

                final isFuture = date.isAfter(DateTime(now.year, now.month, now.day));
                
                final session = widget.store.sessions.firstWhere(
                  (s) => s.date == dKey,
                  orElse: () => Session(dKey, []),
                );

                Color bgColor = Colors.transparent;
                if (!isFuture) {
                  if (session.isFinished) {
                    bgColor = Colors.green.withOpacity(0.4);
                  } else if (dKey != todayStr || session.exercises.isNotEmpty) {
                    bgColor = Colors.red.withOpacity(0.3);
                  }
                }

                return GestureDetector(
                  onTap: () {
                    if (session.exercises.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SessionPage(store: widget.store, session: session),
                        ),
                      );
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: dKey == todayStr
                          ? Border.all(color: Colors.cyanAccent, width: 2)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontWeight: dKey == todayStr ? FontWeight.bold : FontWeight.normal,
                          color: isFuture ? Colors.grey : Colors.white,
                        ),
                      ),
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

  void _addRecord() {
    final w = double.tryParse(_wCtrl.text);
    if (w == null) return;
    final m = double.tryParse(_mCtrl.text);
    final f = double.tryParse(_fCtrl.text);

    setState(() {
      widget.store.bodyRecords.add(BodyRecord(dateKey(DateTime.now()), w, m, f));
    });
    widget.store.save();
    _wCtrl.clear();
    _mCtrl.clear();
    _fCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.store.bodyRecords.reversed.toList();
    final weights = widget.store.bodyRecords.map((r) => r.weight).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('신체 변화 기록')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Text('오늘 신체 측정값 입력', style: TextStyle(color: Colors.cyanAccent)),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _wCtrl, decoration: const InputDecoration(labelText: '체중(kg)'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: _mCtrl, decoration: const InputDecoration(labelText: '골격근량(kg)'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: _fCtrl, decoration: const InputDecoration(labelText: '체지방률(%)'))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: _addRecord, child: const Text('기록 추가')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('체중 변화 추이', style: TextStyle(color: Colors.cyanAccent)),
          lineChart(weights),
          const Divider(),
          for (final r in records)
            ListTile(
              title: Text('${r.date}: ${_fmt(r.weight)}kg'),
              subtitle: Text('골격근량: ${r.muscle != null ? _fmt(r.muscle!) : "-"}kg · 체지방률: ${r.fat != null ? _fmt(r.fat!) : "-"}%'),
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
  Future<String?> _ask(String title, [String initial = '']) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('확인')),
        ],
      ),
    );
  }

  void _save() => widget.store.save();

  Future<void> _addRoutine() async {
    final n = await _ask('루틴 이름 (예: 푸시데이)');
    if (n == null || n.isEmpty) return;
    setState(() => widget.store.routines.add(Routine(n, [])));
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final routines = widget.store.routines;
    return Scaffold(
      appBar: AppBar(title: const Text('루틴')),
      floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.cyanAccent,
          foregroundColor: Colors.black,
          onPressed: _addRoutine,
          child: const Icon(Icons.add)),
      body: routines.isEmpty
          ? const Center(child: Text('등록된 루틴이 없습니다.'))
          : ListView(children: [
              for (final r in routines)
                ExpansionTile(
                  title: Text(r.name, style: const TextStyle(color: Colors.cyanAccent)),
                  subtitle: Text('${r.exercises.length}개 종목'),
                  children: [
                    for (var i = 0; i < r.exercises.length; i++)
                      ListTile(
                        title: Text(r.exercises[i]),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() => r.exercises.removeAt(i));
                            _save();
                          },
                        ),
                      ),
                  ],
                ),
            ]),
    );
  }
}

// ---------- 과거 기록 목록 ----------
class HistoryPage extends StatefulWidget {
  final Store store;
  const HistoryPage({super.key, required this.store});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  @override
  Widget build(BuildContext context) {
    final list = widget.store.sessions.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('운동 기록 목록')),
      body: ListView(children: [
        for (final s in list)
          ListTile(
            title: Text('${s.date} ${s.routine ?? ''}'),
            subtitle: Text('볼륨 ${_fmt(s.volume)}kg ${s.sessionNote.isNotEmpty ? "· " + s.sessionNote : ""}'),
            trailing: Icon(s.isFinished ? Icons.check_circle : Icons.hourglass_bottom,
                color: s.isFinished ? Colors.green : Colors.grey),
            onTap: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SessionPage(store: widget.store, session: s)));
              if (mounted) setState(() {});
            },
          )
      ]),
    );
  }
}

// ---------- 통계 & 1RM 그래프 ----------
class StatsPage extends StatefulWidget {
  final Store store;
  const StatsPage({super.key, required this.store});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  String? selectedExercise;

  @override
  Widget build(BuildContext context) {
    final Map<String, int> muscleSets = {};
    for (final s in widget.store.sessions) {
      for (final e in s.exercises) {
        final count = e.sets.where((x) => x.done && x.type == SetType.MAIN).length;
        muscleSets[e.targetMuscle] = (muscleSets[e.targetMuscle] ?? 0) + count;
      }
    }

    final exercises = widget.store.getAllExerciseNames();
    if (selectedExercise == null && exercises.isNotEmpty) {
      selectedExercise = exercises.first;
    }

    final history1RM = selectedExercise != null
        ? widget.store.get1RMHistory(selectedExercise!)
        : <MapEntry<String, double>>[];

    return Scaffold(
      appBar: AppBar(title: const Text('통계 & 부위별 볼륨 & 1RM')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('부위별 완료 작업 세트 수', style: TextStyle(color: Colors.cyanAccent)),
          const SizedBox(height: 8),
          for (final entry in muscleSets.entries)
            ListTile(
              title: Text(entry.key),
              trailing: Text('${entry.value} 세트', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          const Divider(),
          const SizedBox(height: 8),
          const Text('종목별 1RM 추세 그래프', style: TextStyle(color: Colors.cyanAccent)),
          if (exercises.isNotEmpty)
            DropdownButton<String>(
              value: selectedExercise,
              isExpanded: true,
              items: exercises
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setState(() => selectedExercise = v),
            ),
          const SizedBox(height: 8),
          lineChart(history1RM.map((e) => e.value).toList()),
        ],
      ),
    );
  }
}