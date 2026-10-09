import 'package:flutter_test/flutter_test.dart';
import 'package:gym_book_app/data/models/fitness.dart';

void main() {
  test('workout plan round trips and counts exercises', () {
    final p = WorkoutPlan.fromJson({
      'id': 'p1',
      'name': 'Push',
      'days': [
        {
          'id': 'd1',
          'name': 'Day 1',
          'exercises': [
            {
              'id': 'e1',
              'name': 'Bench',
              'sets': 4,
              'reps': '8',
              'restSec': 90,
            },
          ],
        },
      ],
    });
    expect(p.exerciseCount, 1);
    expect(p.toJson()['days'], isA<List>());
    expect(p.toShareText('Gym'), contains('Bench — 4 x 8'));
  });
  test('new plan gets empty mutable days', () {
    final p = WorkoutPlan(name: 'x');
    p.days.add(WorkoutDay(name: 'A'));
    expect(p.days, hasLength(1));
  });
  test('diet meal kcal sums items', () {
    final m = DietMeal(
      name: 'B',
      items: [
        DietItem(name: 'egg', kcal: 70),
        DietItem(name: 'toast', kcal: 80),
      ],
    );
    expect(m.kcal, 150);
  });
  test('diet plan share text includes meals', () {
    final d = DietPlan(
      name: 'Cut',
      calorieTarget: 1800,
      meals: [
        DietMeal(
          name: 'Lunch',
          items: [DietItem(name: 'rice', kcal: 200)],
        ),
      ],
    );
    final t = d.toShareText('Gym');
    expect(t, contains('Lunch'));
    expect(t, contains('1800 kcal'));
  });
}
