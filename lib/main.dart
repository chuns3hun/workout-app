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

// ---------- 모델 ----------
class SetEntry {
  double weight;
  int reps;
  bool done;
  SetEntry({this.weight = 0, this.reps = 0, this.done = false});
  Map<String, dynamic> toJson() => {'w': weight, 'r': reps, 'd': done};
  factory SetEntry.fromJson(Map<String, dynamic> j) => SetEntry(
        weight: (j['w'] as num).toDouble(),
        reps: j['r'] as int,
        done: j['d'] as bool,
      );
}

class Exercise {
  String name;
  List<SetEntry> sets;
  int rev = 0;
  Exercise(this.name, this.sets);
  double get volume =>
      sets.where((s) => s.done).fold(0.0, (a, s) => a + s.weight * s.reps);
  Map<String, dynamic> toJson() =>
      {'n': name, 's': sets.map((e) => e.toJson()).toList()};
  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        j['n'] as String,
        (j['s'] as List)
            .map((e) => SetEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Session {
  String date;
  List<Exercise> exercises;
  String? routine;
  bool isFinished;

  Session(this.date, this.exercises, [this.routine, this.isFinished = false]);
  double get volume => exercises.fold(0.0, (a, e) => a + e.volume);
  bool get hasDone => exercises.any((e) => e.sets.any((x) => x.done));
  
  Map<String, dynamic> toJson() => {
        'd': date,
        'e': exercises.map((e) => e.toJson()).toList(),
        'rt': routine,
        'fin': isFinished,
      };
      
  factory Session.fromJson(Map<String, dynamic> j) => Session(
        j['d'] as String,
        (j['e'] as List)
            .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
            .toList(),
        j['rt'] as String?,
        (j['fin'] as bool?) ?? false,
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

// ---------- 저장소 ----------
class Store {
  final List<Session> sessions = [];
  final List<Routine> routines = [];
  int defaultRestSeconds = 90;

  static const _keys = ['sessions', 'routines', 'rest_sec'];

  static List<T> _l<T>(dynamic raw, T Function(Map<String, dynamic>) f) =>
      ((raw as List?) ?? []).map((e) => f(e as Map<String, dynamic>)).toList();

  Map<String, dynamic> _toMap() => {
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'routines': routines.map((r) => r.toJson()).toList(),
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
    for (final r in routines) {
      names.addAll(r.exercises);
    }
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
              .map((x) => SetEntry(weight: x.weight, reps: x.reps))
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
}

Widget lineChart(List<double> ys) {
  if (ys.length < 2) {
    return const SizedBox(
        height: 120, child: Center(child: Text('그래프는 기록 2개 이상부터 표시')));
  }

  final minY = ys.reduce((a, b) => a < b ? a : b);
  final maxY = ys.reduce((a, b) => a > b ? a : b);
  final margin = (maxY - minY) == 0 ? 1.0 : (maxY - minY) * 0.1;

  return SizedBox(
    height: 200,
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
            getDrawingHorizontalLine: (value) =>
                FlLine(color: Colors.white10, strokeWidth: 1),
            getDrawingVerticalLine: (value) =>
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

// ---------- 운동 화면 ----------
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
      _toast('🎉 오늘 운동을 완료했습니다!');
    }
  }

  Widget _restBar() {
    final r = _remaining();
    final text = r == 0
        ? '휴식 종료'
        : '휴식 ${r ~/ 60}:${(r % 60).toString().padLeft(2, '0')}';
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
        title: const Text('백업 / 복원'),
        content: const Text('백업 파일을 다운로드하거나, 이전에 저장한 백업 파일(.json)을 선택하여 복원하세요.'),
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
              _toast('백업 파일 다운로드 시작됨');
            },
            child: const Text('파일로 백업'),
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
                      _toast('복원 완료되었습니다.');
                    } catch (_) {
                      _toast('파일 형식 오류');
                    }
                  });
                }
              });
            },
            child: const Text('파일에서 복원'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadRoutine() async {
    final routines = widget.store.routines;
    if (routines.isEmpty) {
      _toast('루틴이 없습니다. 메뉴의 루틴에서 만드세요');
      return;
    }
    final r = await showDialog<Routine>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('루틴 선택'),
        children: [
          for (final x in routines)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, x),
              child: Text('${x.name} (${x.exercises.length})'),
            ),
        ],
      ),
    );
    if (r == null) return;
    var replace = false;
    if (session.exercises.isNotEmpty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('${r.name} 불러오기'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('교체 (현재 운동 기록 삭제)'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'add'),
              child: const Text('현재 운동에 추가'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      replace = choice == 'replace';
    }
    setState(() {
      if (replace) {
        session.exercises.clear();
        session.routine = null;
      }
      for (final name in r.exercises) {
        if (session.exercises.any((e) => e.name == name)) continue;
        final prev = widget.store.previous(name, session.date);
        session.exercises
            .add(Exercise(name, prev.isEmpty ? [SetEntry()] : prev));
      }
      final cur = session.routine;
      if (cur == null) {
        session.routine = r.name;
      } else if (!cur.split(' + ').contains(r.name)) {
        session.routine = '$cur + ${r.name}';
      }
    });
    _save();
  }

  Future<void> _addExercise() async {
    final c = TextEditingController();
    final pastNames = widget.store.getAllExerciseNames();
    
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('운동 종목'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: '종목명 입력')),
            if (pastNames.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('이전 종목 선택:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: pastNames
                    .take(10)
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
    );
    if (name == null || name.isEmpty) return;
    final prev = widget.store.previous(name, session.date);
    setState(() =>
        session.exercises.add(Exercise(name, prev.isEmpty ? [SetEntry()] : prev)));
    _save();
  }

  void _bump(Exercise e, double d) {
    setState(() {
      for (final s in e.sets) {
        final w = s.weight + d;
        s.weight = w < 0 ? 0.0 : w;
      }
      e.rev++;
    });
    _save();
  }

  Widget _card(Exercise e) {
    final prev = widget.store.previous(e.name, session.date);
    final pr = widget.store.pr(e.name);
    final info = [
      if (prev.isNotEmpty)
        '지난번: ${prev.map((s) => '${_fmt(s.weight)}kg×${s.reps}').join(', ')}',
      if (pr > 0) 'PR: ${_fmt(pr)}kg',
      '볼륨: ${_fmt(e.volume)}kg',
    ].join(' · ');
    return Card(
      key: ObjectKey(e),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(e.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: Colors.cyanAccent))),
              IconButton(
                icon: const Icon(Icons.delete, size: 20),
                onPressed: () {
                  setState(() => session.exercises.remove(e));
                  _save();
                },
              ),
            ]),
            Text(info, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 6),
            for (final s in e.sets)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: s.done ? Colors.cyanAccent.withOpacity(0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(key: ObjectKey(s), children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('w${e.rev}'),
                      initialValue: s.weight == 0 ? '' : _fmt(s.weight),
                      decoration: const InputDecoration(labelText: 'kg'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        s.weight = double.tryParse(v) ?? 0;
                        _save();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: s.reps == 0 ? '' : '${s.reps}',
                      decoration: const InputDecoration(labelText: '회'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        s.reps = int.tryParse(v) ?? 0;
                        _save();
                      },
                    ),
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
                ]),
              ),
            Wrap(children: [
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('세트 추가'),
                onPressed: () {
                  final last = e.sets.isEmpty ? null : e.sets.last;
                  setState(() => e.sets.add(SetEntry(
                      weight: last?.weight ?? 0, reps: last?.reps ?? 0)));
                  _save();
                },
              ),
              TextButton(
                  onPressed: () => _bump(e, -2.5), child: const Text('전체 −2.5kg')),
              TextButton(
                  onPressed: () => _bump(e, 2.5), child: const Text('전체 +2.5kg')),
            ]),
          ],
        ),
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
                _nav('달력', Icons.calendar_month, () => CalendarPage(store: st)),
                _nav('루틴', Icons.folder, () => RoutinePage(store: st)),
                _nav('기록', Icons.history, () => HistoryPage(store: st)),
                _nav('통계', Icons.bar_chart, () => StatsPage(store: st)),
                ListTile(
                  leading: const Icon(Icons.save_alt, color: Colors.cyanAccent),
                  title: const Text('백업 / 복원'),
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
          if (session.routine != null)
            Text('루틴: ${session.routine}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.cyanAccent)),
          Text('총 볼륨 ${_fmt(session.volume)}kg (완료 세트 기준)',
              style: const TextStyle(color: Colors.grey)),
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

                // 미래 날짜 여부
                final isFuture = date.isAfter(DateTime(now.year, now.month, now.day));
                
                // 세션 및 완료 여부 조회
                final session = widget.store.sessions.firstWhere(
                  (s) => s.date == dKey,
                  orElse: () => Session(dKey, []),
                );

                Color bgColor = Colors.transparent;
                if (!isFuture) {
                  if (session.isFinished) {
                    bgColor = Colors.green.withOpacity(0.4); // 운동 완료: 초록색
                  } else if (dKey != todayStr || session.exercises.isNotEmpty) {
                    bgColor = Colors.red.withOpacity(0.3); // 과거 미완료/휴식일: 빨간색
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

  Future<void> _rename(Routine r) async {
    final n = await _ask('루틴 이름 변경', r.name);
    if (n == null || n.isEmpty) return;
    setState(() => r.name = n);
    _save();
  }

  Future<void> _addExercise(Routine r) async {
    final pastNames = widget.store.getAllExerciseNames();
    final c = TextEditingController();
    
    final n = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('운동 종목'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: '종목명 입력')),
            if (pastNames.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('이전 종목 선택:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: pastNames
                    .take(10)
                    .map((name) => ActionChip(
                          label: Text(name),
                          onPressed: () => Navigator.pop(ctx, name),
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
    );
    if (n == null || n.isEmpty || r.exercises.contains(n)) return;
    setState(() => r.exercises.add(n));
    _save();
  }

  void _move(Routine r, int i, int d) {
    final j = i + d;
    if (j < 0 || j >= r.exercises.length) return;
    setState(() {
      final t = r.exercises.removeAt(i);
      r.exercises.insert(j, t);
    });
    _save();
  }

  Future<void> _deleteRoutine(Routine r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('루틴 삭제'),
        content: Text('"${r.name}" 루틴을 삭제할까요? (과거 기록은 유지됩니다)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => widget.store.routines.remove(r));
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
          ? const Center(child: Text('루틴 없음. + 버튼으로 추가'))
          : ListView(children: [
              for (final r in routines)
                ExpansionTile(
                  key: ObjectKey(r),
                  title: Text(r.name, style: const TextStyle(color: Colors.cyanAccent)),
                  subtitle: Text('${r.exercises.length}개 운동'),
                  children: [
                    for (var i = 0; i < r.exercises.length; i++)
                      ListTile(
                        key: ValueKey('${r.name}-${r.exercises[i]}'),
                        title: Text(r.exercises[i]),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              icon: const Icon(Icons.arrow_upward),
                              onPressed: () => _move(r, i, -1)),
                          IconButton(
                              icon: const Icon(Icons.arrow_downward),
                              onPressed: () => _move(r, i, 1)),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() => r.exercises.removeAt(i));
                              _save();
                            },
                          ),
                        ]),
                      ),
                    Wrap(children: [
                      TextButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('운동 추가'),
                          onPressed: () => _addExercise(r)),
                      TextButton.icon(
                          icon: const Icon(Icons.edit),
                          label: const Text('이름 변경'),
                          onPressed: () => _rename(r)),
                      TextButton.icon(
                          icon: const Icon(Icons.delete),
                          label: const Text('루틴 삭제'),
                          onPressed: () => _deleteRoutine(r)),
                    ]),
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
  Future<void> _delete(Session s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.date} 기록 삭제'),
        content: const Text('삭제하면 복구할 수 없습니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    widget.store.sessions.remove(s);
    await widget.store.save();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final today = dateKey(DateTime.now());
    final list = widget.store.sessions
        .where((s) => s.date != today && s.exercises.isNotEmpty)
        .toList()
        .reversed
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('기록')),
      body: list.isEmpty
          ? const Center(child: Text('기록 없음'))
          : ListView(children: [
              for (final s in list)
                ListTile(
                  key: ObjectKey(s),
                  title: Row(
                    children: [
                      Text(s.routine == null ? s.date : '${s.date} · ${s.routine}',
                          style: const TextStyle(color: Colors.cyanAccent)),
                      if (s.isFinished) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.check_circle, size: 16, color: Colors.green),
                      ]
                    ],
                  ),
                  subtitle: Text(
                      '${s.exercises.map((e) => e.name).join(', ')} · 볼륨 ${_fmt(s.volume)}kg'),
                  onTap: () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => SessionPage(
                                store: widget.store, session: s)));
                    if (mounted) setState(() {});
                  },
                  trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _delete(s)),
                ),
            ]),
    );
  }
}

// ---------- 통계 ----------
class StatsPage extends StatelessWidget {
  final Store store;
  const StatsPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final cutoff = dateKey(DateTime.now().subtract(const Duration(days: 6)));
    final recent = store.sessions
        .where((s) => s.date.compareTo(cutoff) >= 0 && s.hasDone)
        .toList();
    final weekVol = recent.fold(0.0, (a, s) => a + s.volume);
    final withVol = store.sessions.where((s) => s.volume > 0).toList();
    final trend = withVol.length > 20
        ? withVol.sublist(withVol.length - 20)
        : withVol;
    final names = <String>{
      for (final s in store.sessions)
        for (final e in s.exercises) e.name,
    };
    final prs = [
      for (final n in names)
        if (store.pr(n) > 0) MapEntry(n, store.pr(n)),
    ]..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      appBar: AppBar(title: const Text('통계')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Text('최근 7일 운동 횟수: ${recent.length}회'),
        Text('최근 7일 총 볼륨: ${_fmt(weekVol)}kg'),
        const SizedBox(height: 12),
        Text('세션별 볼륨 추세 (최근 ${trend.length}회)',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.cyanAccent)),
        lineChart([for (final s in trend) s.volume]),
        const SizedBox(height: 12),
        Text('종목별 PR (완료 세트 최대 중량)',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.cyanAccent)),
        if (prs.isEmpty) const Text('기록 없음'),
        for (final p in prs) Text('${p.key}: ${_fmt(p.value)}kg'),
      ]),
    );
  }
}