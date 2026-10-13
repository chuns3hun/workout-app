import 'package:flutter/material.dart';

const List<String> kMuscles = ['가슴', '등', '어깨', '하체', '이두', '삼두', '복근', '기타'];

// iOS 숫자 키패드에는 소수점이 없으므로 decimal 옵션 필요 (62.5kg 입력용)
const TextInputType kDecimalKb = TextInputType.numberWithOptions(decimal: true);

String fmt(double w) =>
    w == w.truncateToDouble() ? w.toInt().toString() : w.toStringAsFixed(1);

String dateKey(DateTime n) =>
    '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';

DateTime weekStart(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

void snack(BuildContext c, String m) {
  if (!c.mounted) return;
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
}
