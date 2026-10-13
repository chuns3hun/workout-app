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
    this.targetMuscle = '가슴',
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

// ---------- 식단 모델 ----------
class FoodItem {
  String name;
  double calories;
  double carbs;
  double protein;
  double fat;

  FoodItem({
    required this.name,
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fat,
  });

  Map<String, dynamic> toJson() => {
        'n': name,
        'cal': calories,
        'c': carbs,
        'p': protein,
        'f': fat,
      };

  factory FoodItem.fromJson(Map<String, dynamic> j) => FoodItem(
        name: j['n'] as String,
        calories: (j['cal'] as num).toDouble(),
        carbs: (j['c'] as num).toDouble(),
        protein: (j['p'] as num).toDouble(),
        fat: (j['f'] as num).toDouble(),
      );
}

class MealEntry {
  String id;
  String date;
  String mealType;
  String? imageBase64;
  List<FoodItem> foods;

  MealEntry({
    required this.id,
    required this.date,
    required this.mealType,
    this.imageBase64,
    required this.foods,
  });

  double get totalCalories => foods.fold(0.0, (a, b) => a + b.calories);
  double get totalCarbs => foods.fold(0.0, (a, b) => a + b.carbs);
  double get totalProtein => foods.fold(0.0, (a, b) => a + b.protein);
  double get totalFat => foods.fold(0.0, (a, b) => a + b.fat);

  Map<String, dynamic> toJson() => {
        'id': id,
        'd': date,
        'mt': mealType,
        'img': imageBase64,
        'f': foods.map((e) => e.toJson()).toList(),
      };

  factory MealEntry.fromJson(Map<String, dynamic> j) => MealEntry(
        id: j['id'] as String,
        date: j['d'] as String,
        mealType: j['mt'] as String? ?? '점심',
        imageBase64: j['img'] as String?,
        foods: (j['f'] as List)
            .map((e) => FoodItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}