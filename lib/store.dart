import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'utils.dart';

/// 앱 전체 데이터 + 저장/불러오기.
/// save()는 250ms 디바운스 후 저장하고 리스너(달력·통계 등)에 알림.
class Store extends ChangeNotifier {
  final List<Session> sessions = [];
  final List<Routine> routines = [];
  final List<BodyRecord> bodyRecords = [];
  int defaultRestSeconds = 90;
  String? lastBackup;

  static const _keys = ['sessions', 'routines', 'body_records', 'rest_sec'];
  Timer? _debounce;

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

  void save() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _persist);
  }

  Future<void> saveNow() {
    _debounce?.cancel();
    return _persist();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    final m = _toMap();
    for (final k in _keys) {
      await p.setString(k, jsonEncode(m[k]));
    }
    notifyListeners();
  }

  void setRestSeconds(int v) {
    defaultRestSeconds = v.clamp(10, 900).toInt();
    save();
  }

  Future<void> markBackup() async {
    lastBackup = dateKey(DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setString('last_backup', lastBackup!);
    notifyListeners();
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
    await saveNow();
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
      return '🎯 목표 달성! ${fmt(lastWeight + 2.5)}kg 추천';
    }
    if (lastRpe <= 7.0) {
      return '추천: ${fmt(lastWeight + 2.5)}kg × $lastReps회';
    } else if (lastRpe >= 9.5) {
      return '추천: ${fmt(lastWeight)}kg × $lastReps회 (중량 유지)';
    } else {
      return '추천: ${fmt(lastWeight)}kg × ${lastReps + 1}회 (+1회 도전)';
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
