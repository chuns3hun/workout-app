import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'utils.dart';

class Store extends ChangeNotifier {
  final List<Session> sessions = [];
  final List<Routine> routines = [];
  final List<BodyRecord> bodyRecords = [];
  int defaultRestSeconds = 90;
  String? lastBackup;

  static const _keys = ['sessions', 'routines', 'body_records', 'rest_sec', 'last_backup'];

  static List<T> _l<T>(dynamic raw, T Function(Map<String, dynamic>) f) =>
      ((raw as List?) ?? []).map((e) => f(e as Map<String, dynamic>)).toList();

  Map<String, dynamic> _toMap() => {
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'routines': routines.map((r) => r.toJson()).toList(),
        'body_records': bodyRecords.map((b) => b.toJson()).toList(),
        'rest_sec': defaultRestSeconds,
        'last_backup': lastBackup,
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
    if (m['last_backup'] != null) {
      lastBackup = m['last_backup'] as String?;
    }
    notifyListeners();
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
    notifyListeners();
  }

  bool get needsBackup {
    if (lastBackup == null) return true;
    final b = DateTime.tryParse(lastBackup!);
    if (b == null) return true;
    return DateTime.now().difference(b).inDays >= 7;
  }

  int? daysSinceBackup() {
    if (lastBackup == null) return null;
    final b = DateTime.tryParse(lastBackup!);
    if (b == null) return null;
    return DateTime.now().difference(b).inDays;
  }

  Future<void> markBackup() async {
    lastBackup = dateKey(DateTime.now());
    await save();
  }

  Future<void> setRestSeconds(int sec) async {
    defaultRestSeconds = sec;
    await save();
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

  List<String> recentExerciseNames() {
    final names = <String>{};
    for (final r in routines) names.addAll(r.exercises);
    for (final s in sessions) {
      for (final e in s.exercises) {
        if (e.name.isNotEmpty) names.add(e.name);
      }
    }
    return names.toList()..sort();
  }

  Exercise newExercise(String name, String date, {String fallbackMuscle = '가슴'}) {
    final prev = previous(name, date);
    return Exercise(
      name,
      prev.isEmpty ? [SetEntry()] : prev,
      targetMuscle: fallbackMuscle,
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
          if (x.done && x.weight > m) m = x.weight;
        }
      }
    }
    return m;
  }

  String recommendNext(Exercise e, String date) {
    final prevSets = previous(e.name, date).where((s) => s.type == SetType.MAIN).toList();
    if (prevSets.isEmpty) return '기록 부족 (첫 수행)';

    final lastWeight = prevSets.first.weight;
    final lastReps = prevSets.first.reps;
    final lastRpe = prevSets.first.rpe ?? 8.0;

    if (lastReps >= e.maxReps && lastRpe <= 8.5) {
      return '🎯 목표 달성! ${fmt(lastWeight + 2.5)}kg 추천';
    }

    if (lastRpe <= 7.0) {
      return '추천: ${fmt(lastWeight + 2.5)}kg × ${lastReps}회';
    } else if (lastRpe >= 9.5) {
      return '추천: ${fmt(lastWeight)}kg × ${lastReps}회 (중량 유지)';
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