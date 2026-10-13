import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../utils.dart';

class FoodPage extends StatefulWidget {
  final Store store;
  const FoodPage({super.key, required this.store});

  @override
  State<FoodPage> createState() => _FoodPageState();
}

class _FoodPageState extends State<FoodPage> {
  bool _isLoading = false;
  String selectedMealType = '점심';

  void _analyzeAndAddFood() {
    final input = html.FileUploadInputElement()..accept = 'image/*';
    input.click();
    input.onChange.listen((e) {
      final files = input.files;
      if (files != null && files.isNotEmpty) {
        final reader = html.FileReader();
        reader.readAsDataUrl(files[0]);
        reader.onLoadEnd.listen((e) async {
          final dataUrl = reader.result as String;
          final base64Image = dataUrl.split(',').last;

          setState(() => _isLoading = true);

          try {
            final foods = await FoodAnalyzer.analyzeMealImage(base64Image);
            final newMeal = MealEntry(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              date: dateKey(DateTime.now()),
              mealType: selectedMealType,
              imageBase64: base64Image,
              foods: foods,
            );

            setState(() {
              widget.store.meals.add(newMeal);
            });
            await widget.store.save();
            if (mounted) {
              snack(context, '✨ AI 식단 분석이 완료되었습니다.');
            }
          } catch (err) {
            if (mounted) {
              snack(context, '분석 실패: ${err.toString()}');
            }
          } finally {
            if (mounted) setState(() => _isLoading = false);
          }
        });
      }
    });
  }

  void _addManualFoodItem(MealEntry meal) {
    final nameCtrl = TextEditingController();
    final calCtrl = TextEditingController();
    final cCtrl = TextEditingController();
    final pCtrl = TextEditingController();
    final fCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('음식 항목 수동 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(hintText: '음식명 (예: 제육볶음)')),
            TextField(controller: calCtrl, decoration: const InputDecoration(hintText: '칼로리 (kcal)'), keyboardType: TextInputType.number),
            TextField(controller: cCtrl, decoration: const InputDecoration(hintText: '탄수화물 (g)'), keyboardType: TextInputType.number),
            TextField(controller: pCtrl, decoration: const InputDecoration(hintText: '단백질 (g)'), keyboardType: TextInputType.number),
            TextField(controller: fCtrl, decoration: const InputDecoration(hintText: '지방 (g)'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final item = FoodItem(
                name: nameCtrl.text.trim().isEmpty ? '음식' : nameCtrl.text.trim(),
                calories: double.tryParse(calCtrl.text) ?? 0,
                carbs: double.tryParse(cCtrl.text) ?? 0,
                protein: double.tryParse(pCtrl.text) ?? 0,
                fat: double.tryParse(fCtrl.text) ?? 0,
              );
              setState(() {
                meal.foods.add(item);
              });
              widget.store.save();
              Navigator.pop(ctx);
            },
            child: const Text('추가'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayStr = dateKey(DateTime.now());
    final todayMeals = widget.store.meals.where((m) => m.date == todayStr).toList();

    double totalCal = todayMeals.fold(0.0, (a, b) => a + b.totalCalories);
    double totalC = todayMeals.fold(0.0, (a, b) => a + b.totalCarbs);
    double totalP = todayMeals.fold(0.0, (a, b) => a + b.totalProtein);
    double totalF = todayMeals.fold(0.0, (a, b) => a + b.totalFat);

    return Scaffold(
      appBar: AppBar(title: const Text('식단 기록 (Vision AI)')),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.tealAccent),
                  SizedBox(height: 16),
                  Text('🤖 AI가 학식 영양소를 분석하고 있습니다...', style: TextStyle(color: Colors.tealAccent)),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Colors.tealAccent.withOpacity(0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('오늘 총 섭취 영양소', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text('${fmt(totalCal)} kcal',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text('탄수화물: ${fmt(totalC)}g', style: const TextStyle(fontSize: 12)),
                            Text('단백질: ${fmt(totalP)}g', style: const TextStyle(fontSize: 12, color: Colors.amberAccent)),
                            Text('지방: ${fmt(totalF)}g', style: const TextStyle(fontSize: 12)),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    DropdownButton<String>(
                      value: selectedMealType,
                      items: ['아침', '점심', '저녁', '간식']
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setState(() => selectedMealType = v!),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.tealAccent,
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.camera_alt, size: 18),
                      label: const Text('학식 사진 업로드'),
                      onPressed: _analyzeAndAddFood,
                    ),
                  ],
                ),
                const Divider(height: 24),
                if (todayMeals.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text('오늘 기록된 식단이 없습니다. 학식 사진을 올려보세요!', style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  for (final meal in todayMeals.reversed)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('${meal.mealType} - ${fmt(meal.totalCalories)} kcal',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 18, color: Colors.grey),
                                  onPressed: () => _addManualFoodItem(meal),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                                  onPressed: () {
                                    setState(() => widget.store.meals.remove(meal));
                                    widget.store.save();
                                  },
                                ),
                              ],
                            ),
                            if (meal.imageBase64 != null) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  base64Decode(meal.imageBase64!),
                                  height: 160,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            for (var idx = 0; idx < meal.foods.length; idx++) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    Text('• ${meal.foods[idx].name}', style: const TextStyle(fontSize: 13)),
                                    const Spacer(),
                                    Text(
                                      '${fmt(meal.foods[idx].calories)}kcal (탄:${fmt(meal.foods[idx].carbs)}g/단:${fmt(meal.foods[idx].protein)}g/지:${fmt(meal.foods[idx].fat)}g)',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 14, color: Colors.grey),
                                      onPressed: () {
                                        setState(() => meal.foods.removeAt(idx));
                                        widget.store.save();
                                      },
                                    )
                                  ],
                                ),
                              )
                            ]
                          ],
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}