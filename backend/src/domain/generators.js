// Rule-based workout / diet generators. These are deterministic and run locally: NO LLM is involved.
// (The original app routes "Generate with AI" through a hosted model; that service is not available here.)
import { randomUUID } from 'node:crypto';

const E = { BW: 'Bodyweight Only', BAND: 'Resistance Bands', DB: 'Dumbbells', BB: 'Barbell', CABLE: 'Cables', GYM: 'Full Gym' };
export const EQUIPMENT = Object.values(E);
export const GOALS = ['Build Muscle', 'Lose Fat', 'Get Stronger', 'General Fitness', 'Endurance'];
export const LEVELS = ['Beginner', 'Intermediate', 'Advanced'];
export const DIET_PREFERENCES = ['Vegetarian', 'Non Vegetarian', 'Eggetarian', 'Vegan'];

// slug, name, category, equipment[], joint-stress tags, kind
const L = (slug, name, category, equipment, stress = [], kind = 'compound') => ({ id: `lib:${slug}`, slug, name, category, equipment, stress, kind, builtIn: true });
export const EXERCISE_LIBRARY = [
  L('push-up', 'Push-up', 'Chest', [E.BW], ['shoulder', 'wrist']),
  L('incline-push-up', 'Incline Push-up', 'Chest', [E.BW], ['wrist']),
  L('db-bench-press', 'Dumbbell Bench Press', 'Chest', [E.DB, E.GYM], ['shoulder']),
  L('bb-bench-press', 'Barbell Bench Press', 'Chest', [E.BB, E.GYM], ['shoulder']),
  L('cable-fly', 'Cable Fly', 'Chest', [E.CABLE, E.GYM], ['shoulder'], 'isolation'),
  L('band-chest-press', 'Band Chest Press', 'Chest', [E.BAND], []),
  L('pull-up', 'Pull-up', 'Back', [E.BW, E.GYM], ['shoulder']),
  L('lat-pulldown', 'Lat Pulldown', 'Back', [E.CABLE, E.GYM], ['shoulder']),
  L('db-row', 'One-arm Dumbbell Row', 'Back', [E.DB, E.GYM], ['back']),
  L('bb-row', 'Barbell Row', 'Back', [E.BB, E.GYM], ['back']),
  L('seated-cable-row', 'Seated Cable Row', 'Back', [E.CABLE, E.GYM], []),
  L('band-row', 'Band Row', 'Back', [E.BAND], []),
  L('deadlift', 'Deadlift', 'Back', [E.BB, E.GYM], ['back']),
  L('db-shoulder-press', 'Dumbbell Shoulder Press', 'Shoulders', [E.DB, E.GYM], ['shoulder']),
  L('bb-overhead-press', 'Overhead Press', 'Shoulders', [E.BB, E.GYM], ['shoulder', 'back']),
  L('lateral-raise', 'Lateral Raise', 'Shoulders', [E.DB, E.BAND, E.GYM], ['shoulder'], 'isolation'),
  L('face-pull', 'Face Pull', 'Shoulders', [E.CABLE, E.BAND, E.GYM], [], 'isolation'),
  L('pike-push-up', 'Pike Push-up', 'Shoulders', [E.BW], ['shoulder', 'wrist']),
  L('bicep-curl', 'Dumbbell Biceps Curl', 'Arms', [E.DB, E.GYM], [], 'isolation'),
  L('hammer-curl', 'Hammer Curl', 'Arms', [E.DB, E.GYM], [], 'isolation'),
  L('tricep-pushdown', 'Triceps Pushdown', 'Arms', [E.CABLE, E.GYM], [], 'isolation'),
  L('bench-dip', 'Bench Dip', 'Arms', [E.BW], ['shoulder', 'wrist'], 'isolation'),
  L('band-curl', 'Band Biceps Curl', 'Arms', [E.BAND], [], 'isolation'),
  L('squat', 'Barbell Back Squat', 'Legs', [E.BB, E.GYM], ['knee', 'back']),
  L('goblet-squat', 'Goblet Squat', 'Legs', [E.DB, E.GYM], ['knee']),
  L('bodyweight-squat', 'Bodyweight Squat', 'Legs', [E.BW], ['knee']),
  L('lunge', 'Walking Lunge', 'Legs', [E.BW, E.DB], ['knee']),
  L('leg-press', 'Leg Press', 'Legs', [E.GYM], ['knee']),
  L('rdl', 'Romanian Deadlift', 'Legs', [E.BB, E.DB, E.GYM], ['back']),
  L('glute-bridge', 'Glute Bridge', 'Legs', [E.BW, E.BAND, E.DB], []),
  L('leg-curl', 'Leg Curl', 'Legs', [E.GYM], [], 'isolation'),
  L('calf-raise', 'Standing Calf Raise', 'Legs', [E.BW, E.DB, E.GYM], [], 'isolation'),
  L('plank', 'Plank', 'Core', [E.BW], ['shoulder'], 'core'),
  L('dead-bug', 'Dead Bug', 'Core', [E.BW], [], 'core'),
  L('crunch', 'Crunch', 'Core', [E.BW], ['neck'], 'core'),
  L('cable-crunch', 'Cable Crunch', 'Core', [E.CABLE, E.GYM], [], 'core'),
  L('russian-twist', 'Russian Twist', 'Core', [E.BW, E.DB], ['back'], 'core'),
  L('treadmill-run', 'Treadmill Run', 'Cardio', [E.GYM], ['knee'], 'cardio'),
  L('stationary-bike', 'Stationary Bike', 'Cardio', [E.GYM], [], 'cardio'),
  L('jumping-jacks', 'Jumping Jacks', 'Cardio', [E.BW], ['knee'], 'cardio'),
  L('mountain-climber', 'Mountain Climbers', 'Cardio', [E.BW], ['wrist', 'shoulder'], 'cardio'),
  L('brisk-walk', 'Brisk Walk', 'Cardio', [E.BW, E.GYM], [], 'cardio'),
];
export const EXERCISE_CATEGORIES = ['Chest', 'Back', 'Shoulders', 'Arms', 'Legs', 'Core', 'Cardio'];

// Reported condition -> joint-stress tag to avoid.
const CONDITION_STRESS = {
  'Knee Pain': 'knee', 'Shoulder Pain': 'shoulder', 'Back Pain': 'back', 'Neck Pain': 'neck', 'Hip Pain': 'knee', 'Joint Pain': 'knee',
  'Ankle Pain': 'knee', 'Muscle Injury': 'back', 'Weak Bones': 'back',
};
const CAUTION = ['High BP', 'Heart Problem', 'Chest pain', 'Dizziness / balance', 'Diabetes', 'Asthma', 'Breathing Problem', 'Stroke History', 'Blood pressure meds'];

const PRESCRIPTION = {
  'Build Muscle': { sets: 4, reps: '8-12', restSec: 75 }, 'Get Stronger': { sets: 5, reps: '4-6', restSec: 150 }, 'Lose Fat': { sets: 3, reps: '12-15', restSec: 45 },
  'General Fitness': { sets: 3, reps: '10-12', restSec: 60 }, Endurance: { sets: 3, reps: '15-20', restSec: 30 },
};
const LEVEL_SETS = { Beginner: -1, Intermediate: 0, Advanced: 1 };

const SPLITS = {
  2: [['Full Body A', ['Legs', 'Chest', 'Back', 'Core']], ['Full Body B', ['Legs', 'Shoulders', 'Back', 'Core']]],
  3: [['Full Body A', ['Legs', 'Chest', 'Back', 'Core']], ['Full Body B', ['Legs', 'Shoulders', 'Back', 'Arms']], ['Full Body C', ['Legs', 'Chest', 'Back', 'Core']]],
  4: [['Upper A', ['Chest', 'Back', 'Shoulders', 'Arms']], ['Lower A', ['Legs', 'Legs', 'Core']], ['Upper B', ['Back', 'Chest', 'Shoulders', 'Arms']], ['Lower B', ['Legs', 'Legs', 'Core']]],
  5: [['Push', ['Chest', 'Shoulders', 'Arms']], ['Pull', ['Back', 'Back', 'Arms']], ['Legs', ['Legs', 'Legs', 'Core']], ['Upper', ['Chest', 'Back', 'Shoulders', 'Arms']], ['Lower', ['Legs', 'Legs', 'Core']]],
  6: [['Push A', ['Chest', 'Shoulders', 'Arms']], ['Pull A', ['Back', 'Back', 'Arms']], ['Legs A', ['Legs', 'Legs', 'Core']], ['Push B', ['Shoulders', 'Chest', 'Arms']], ['Pull B', ['Back', 'Back', 'Arms']], ['Legs B', ['Legs', 'Legs', 'Core']]],
};

export function generateWorkout({ goal = 'General Fitness', level = 'Beginner', daysPerWeek = 3, equipment = [E.GYM], conditions = [], sessionMinutes = 60, memberName = null }) {
  const days = Math.min(6, Math.max(2, daysPerWeek));
  const avoid = new Set(conditions.map((c) => CONDITION_STRESS[c]).filter(Boolean));
  const cautions = conditions.filter((c) => CAUTION.includes(c));
  const equip = new Set(equipment.length ? equipment : [E.GYM]);
  if (equip.has(E.GYM)) { equip.add(E.DB); equip.add(E.BB); equip.add(E.CABLE); equip.add(E.BAND); }
  const fits = (x) => x.equipment.some((q) => equip.has(q)) && !x.stress.some((s) => avoid.has(s));
  const usable = EXERCISE_LIBRARY.filter((x) => x.kind !== 'cardio' && fits(x));
  const cardioPool = EXERCISE_LIBRARY.filter((x) => x.kind === 'cardio' && fits(x));
  const rx = PRESCRIPTION[goal] ?? PRESCRIPTION['General Fitness'];
  const sets = Math.max(2, rx.sets + (LEVEL_SETS[level] ?? 0));
  const perDay = sessionMinutes <= 40 ? 4 : sessionMinutes <= 55 ? 5 : sessionMinutes <= 70 ? 6 : 7;
  const used = new Map();
  const warnings = [];
  if (avoid.size) warnings.push(`Movements stressing ${[...avoid].join(', ')} were excluded because of the member's reported conditions.`);
  if (cautions.length) warnings.push(`Medical caution (${cautions.join(', ')}): keep intensity moderate and seek clearance before heavy lifting.`);

  const plan = SPLITS[days].map(([name, slots]) => {
    const picked = [];
    const slotList = [...slots];
    while (slotList.length < perDay) slotList.push(slots[slotList.length % slots.length]);
    for (const cat of slotList.slice(0, perDay)) {
      // Least-used first so the week rotates through the library; compounds before isolation.
      const pool = usable
        .filter((x) => x.category === cat && !picked.some((p) => p.exerciseId === x.id))
        .sort((a, b) => (used.get(a.id) ?? 0) - (used.get(b.id) ?? 0) || (a.kind === 'compound' ? -1 : 1) - (b.kind === 'compound' ? -1 : 1));
      const ex = pool[0];
      if (!ex) continue;
      used.set(ex.id, (used.get(ex.id) ?? 0) + 1);
      const iso = ex.kind === 'isolation';
      picked.push({
        id: randomUUID(), exerciseId: ex.id, name: ex.name, sets: ex.kind === 'core' ? 3 : iso ? Math.max(2, sets - 1) : sets,
        reps: ex.slug === 'plank' ? '30-60 sec' : iso ? '12-15' : rx.reps, restSec: iso ? Math.max(30, rx.restSec - 30) : rx.restSec, notes: null,
      });
    }
    return { id: randomUUID(), name, exercises: picked };
  });
  if ((goal === 'Lose Fat' || goal === 'Endurance') && cardioPool.length) {
    plan.forEach((d, i) => {
      const c = cardioPool[i % cardioPool.length];
      d.exercises.push({ id: randomUUID(), exerciseId: c.id, name: c.name, sets: 1, reps: '10-15 min', restSec: 0, notes: 'Finisher: keep a steady, conversational pace' });
    });
  }
  return {
    name: `${memberName ? `${memberName.split(' ')[0]}'s ` : ''}${days}-day ${goal}`, goal, level, daysPerWeek: days, equipment: [...equipment],
    description: `${days} training days per week, ${level.toLowerCase()} level, built for "${goal}".`, days: plan, warnings, generator: 'rule-based-dev',
  };
}

// ---- diet ----------------------------------------------------------------------------------------------------
// name, unit, kcal per unit, protein per unit, suitable diets (vg vegan, v vegetarian, e eggetarian, n non-veg), allergens, meal slots
const F = (name, unit, kcal, protein, diet, allergens = [], meals = ['lunch', 'dinner']) => ({ name, unit, kcal, protein, diet, allergens, meals });
const ALL = ['vg', 'v', 'e', 'n'];
const FOODS = [
  F('Oats porridge', 'bowl', 180, 6, ALL, ['gluten'], ['breakfast']), F('Poha', 'plate', 250, 5, ALL, [], ['breakfast']),
  F('Vegetable upma', 'plate', 230, 6, ['v', 'e', 'n'], ['gluten'], ['breakfast']), F('Idli', 'piece', 60, 2, ALL, [], ['breakfast']),
  F('Boiled egg', 'piece', 75, 6, ['e', 'n'], ['egg'], ['breakfast', 'snack']), F('Egg bhurji', 'serving', 190, 12, ['e', 'n'], ['egg'], ['breakfast']),
  F('Greek yogurt', 'cup', 130, 12, ['v', 'e', 'n'], ['dairy'], ['breakfast', 'snack']), F('Soy milk', 'glass', 110, 7, ALL, ['soy'], ['breakfast', 'snack']),
  F('Banana', 'piece', 100, 1, ALL, [], ['breakfast', 'snack']), F('Apple', 'piece', 80, 0, ALL, [], ['snack']),
  F('Peanuts (roasted)', 'handful', 160, 7, ALL, ['nuts'], ['snack']), F('Almonds', 'handful', 170, 6, ALL, ['nuts'], ['snack']),
  F('Sprouts salad', 'bowl', 140, 9, ALL, [], ['snack', 'lunch']), F('Whey protein shake', 'scoop', 120, 24, ['v', 'e', 'n'], ['dairy'], ['snack']),
  F('Roasted chana', 'handful', 130, 7, ALL, [], ['snack']), F('Steamed rice', 'cup', 205, 4, ALL, [], ['lunch', 'dinner']),
  F('Chapati', 'piece', 105, 3, ALL, ['gluten'], ['lunch', 'dinner']), F('Dal (cooked lentils)', 'bowl', 160, 10, ALL, [], ['lunch', 'dinner']),
  F('Paneer bhurji', 'serving', 260, 16, ['v', 'e', 'n'], ['dairy'], ['lunch', 'dinner']), F('Tofu stir-fry', 'serving', 190, 16, ALL, ['soy'], ['lunch', 'dinner']),
  F('Chickpea curry', 'bowl', 240, 12, ALL, [], ['lunch', 'dinner']), F('Mixed vegetable sabzi', 'bowl', 110, 3, ALL, [], ['lunch', 'dinner']),
  F('Curd', 'bowl', 100, 6, ['v', 'e', 'n'], ['dairy'], ['lunch', 'dinner']), F('Grilled chicken breast', 'serving', 220, 35, ['n'], [], ['lunch', 'dinner']),
  F('Fish curry', 'serving', 230, 24, ['n'], ['fish'], ['lunch', 'dinner']), F('Egg curry', 'serving', 210, 13, ['e', 'n'], ['egg'], ['lunch', 'dinner']),
  F('Green salad', 'bowl', 60, 2, ALL, [], ['lunch', 'dinner']), F('Quinoa', 'cup', 220, 8, ALL, [], ['lunch', 'dinner']),
];
const PREF_TAG = { Vegetarian: 'v', 'Non Vegetarian': 'n', Eggetarian: 'e', Vegan: 'vg' };
const DISTRIBUTION = {
  3: [['Breakfast', '08:00', 'breakfast', 0.3], ['Lunch', '13:00', 'lunch', 0.4], ['Dinner', '20:00', 'dinner', 0.3]],
  4: [['Breakfast', '08:00', 'breakfast', 0.27], ['Lunch', '13:00', 'lunch', 0.33], ['Evening Snack', '17:30', 'snack', 0.12], ['Dinner', '20:00', 'dinner', 0.28]],
  5: [['Breakfast', '07:30', 'breakfast', 0.25], ['Mid-morning Snack', '10:30', 'snack', 0.1], ['Lunch', '13:00', 'lunch', 0.3], ['Evening Snack', '17:00', 'snack', 0.1], ['Dinner', '20:00', 'dinner', 0.25]],
  6: [['Breakfast', '07:30', 'breakfast', 0.22], ['Mid-morning Snack', '10:30', 'snack', 0.1], ['Lunch', '13:00', 'lunch', 0.27], ['Evening Snack', '17:00', 'snack', 0.1], ['Dinner', '20:00', 'dinner', 0.23], ['Before Bed', '22:00', 'snack', 0.08]],
};

/** Mifflin-St Jeor with a moderate activity factor; returns null when stats are missing. */
export function estimateCalories({ weightKg, heightCm, age, gender, goal }) {
  if (!weightKg || !heightCm || !age) return null;
  const bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + (gender === 'female' ? -161 : 5);
  const tdee = bmr * 1.5;
  const adj = goal === 'Lose Fat' ? 0.8 : goal === 'Build Muscle' ? 1.1 : 1;
  return Math.max(1200, Math.round((tdee * adj) / 50) * 50);
}

export function generateDiet({ goal = 'General Fitness', dietaryPreference = 'Vegetarian', calorieTarget, mealsPerDay = 4, allergies = [], weightKg = null, memberName = null }) {
  const meals = Math.min(6, Math.max(3, mealsPerDay));
  const kcal = calorieTarget ?? 2000;
  const tag = PREF_TAG[dietaryPreference] ?? 'v';
  const avoid = new Set(allergies.map((a) => a.toLowerCase().trim()));
  const ok = (f) => f.diet.includes(tag) && !f.allergens.some((a) => avoid.has(a));
  const proteinG = Math.round(weightKg ? (goal === 'Build Muscle' || goal === 'Get Stronger' ? 1.9 : 1.6) * weightKg : (kcal * 0.25) / 4);
  const fatG = Math.round((kcal * 0.25) / 9);
  const carbG = Math.max(0, Math.round((kcal - proteinG * 4 - fatG * 9) / 4));
  const used = new Map();
  const warnings = [];
  const out = DISTRIBUTION[meals].map(([name, time, slot, share]) => {
    const target = kcal * share;
    const pool = FOODS.filter((f) => ok(f) && f.meals.includes(slot))
      .sort((a, b) => (used.get(a.name) ?? 0) - (used.get(b.name) ?? 0) || b.protein / b.kcal - a.protein / a.kcal);
    const chosen = pool.slice(0, slot === 'snack' ? 2 : 3);
    if (!chosen.length) warnings.push(`No suitable foods found for ${name}; please add items manually.`);
    for (const c of chosen) used.set(c.name, (used.get(c.name) ?? 0) + 1);
    const base = chosen.reduce((s, f) => s + f.kcal, 0) || 1;
    const mult = Math.min(3, Math.max(0.5, Math.round((target / base) * 2) / 2));
    return {
      id: randomUUID(), name, time,
      items: chosen.map((f) => ({
        id: randomUUID(), name: f.name, unit: f.unit, quantity: f.unit === 'piece' ? Math.max(1, Math.round(mult * 2)) : mult,
        kcal: Math.round(f.kcal * mult), protein: Math.round(f.protein * mult),
      })),
    };
  });
  return {
    name: `${memberName ? `${memberName.split(' ')[0]}'s ` : ''}${goal} diet`, goal, dietaryPreference, calorieTarget: kcal, mealsPerDay: meals, allergies,
    macros: { protein: proteinG, carbs: carbG, fat: fatG }, meals: out, warnings, notes: null, generator: 'rule-based-dev',
  };
}
