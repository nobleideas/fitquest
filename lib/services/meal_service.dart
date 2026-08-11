import 'package:supabase_flutter/supabase_flutter.dart';

class FoodItem {
  final String id;
  final String name;
  final String brand;
  final double calories;
  final double fat;
  final double carbs;
  final double protein;

  const FoodItem({
    required this.id,
    required this.name,
    required this.brand,
    required this.calories,
    required this.fat,
    required this.carbs,
    required this.protein,
  });

  factory FoodItem.fromMap(Map<String, dynamic> map) {
    double toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse((value ?? '').toString()) ?? 0;
    }

    return FoodItem(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      brand: (map['brand'] ?? '').toString(),
      calories: toDouble(map['calories']),
      fat: toDouble(map['fat']),
      carbs: toDouble(map['carbs']),
      protein: toDouble(map['protein']),
    );
  }
}


class MealComponent {
  final String foodItemId;
  final FoodItem food;
  final double servings;

  const MealComponent({
    required this.foodItemId,
    required this.food,
    required this.servings,
  });
}

class SavedMeal {
  final String id;
  final String name;
  final List<MealComponent> components;

  const SavedMeal({
    required this.id,
    required this.name,
    required this.components,
  });

  double get calories =>
      components.fold(0, (sum, item) => sum + item.food.calories * item.servings);
  double get fat =>
      components.fold(0, (sum, item) => sum + item.food.fat * item.servings);
  double get carbs =>
      components.fold(0, (sum, item) => sum + item.food.carbs * item.servings);
  double get protein =>
      components.fold(0, (sum, item) => sum + item.food.protein * item.servings);
}

class ConsumedFood {
  final String id;
  final DateTime consumedAt;
  final double servings;
  final FoodItem food;

  const ConsumedFood({
    required this.id,
    required this.consumedAt,
    required this.servings,
    required this.food,
  });

  double get calories => food.calories * servings;
  double get fat => food.fat * servings;
  double get carbs => food.carbs * servings;
  double get protein => food.protein * servings;
}

class MealService {
  final SupabaseClient supabase;

  MealService([SupabaseClient? client])
      : supabase = client ?? Supabase.instance.client;

  String _sanitizeDisplayText(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    if (cleaned.isEmpty) return '';

    return cleaned
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) {
          if (word.length == 1) return word.toUpperCase();
          return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  String get _userId {
    final user = supabase.auth.currentUser;
    if (user == null) throw StateError('User must be logged in.');
    return user.id;
  }

  Future<List<FoodItem>> getFoodItems() async {
    final rows = await supabase
        .from('food_items')
        .select('id, name, brand, calories, fat, carbs, protein')
        .eq('user_id', _userId)
        .order('name', ascending: true);

    final foods = (rows as List)
        .whereType<Map>()
        .map((row) => FoodItem.fromMap(Map<String, dynamic>.from(row)))
        .toList();

    foods.sort((a, b) {
      final nameCompare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (nameCompare != 0) return nameCompare;
      return a.brand.toLowerCase().compareTo(b.brand.toLowerCase());
    });

    return foods;
  }

  Future<FoodItem> addFoodItem({
    required String name,
    required String brand,
    required double calories,
    required double fat,
    required double carbs,
    required double protein,
  }) async {
    final row = await supabase
        .from('food_items')
        .insert({
          'user_id': _userId,
          'name': _sanitizeDisplayText(name),
          'brand': _sanitizeDisplayText(brand),
          'calories': calories,
          'fat': fat,
          'carbs': carbs,
          'protein': protein,
        })
        .select('id, name, brand, calories, fat, carbs, protein')
        .single();

    return FoodItem.fromMap(Map<String, dynamic>.from(row));
  }

  Future<FoodItem> updateFoodItem({
    required String foodItemId,
    required String name,
    required String brand,
    required double calories,
    required double fat,
    required double carbs,
    required double protein,
  }) async {
    final row = await supabase
        .from('food_items')
        .update({
          'name': _sanitizeDisplayText(name),
          'brand': _sanitizeDisplayText(brand),
          'calories': calories,
          'fat': fat,
          'carbs': carbs,
          'protein': protein,
        })
        .eq('id', foodItemId)
        .eq('user_id', _userId)
        .select('id, name, brand, calories, fat, carbs, protein')
        .single();

    return FoodItem.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> deleteFoodItem(String foodItemId) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw StateError('User must be logged in.');
    }

    final usageRows = await supabase
        .from('food_consumptions')
        .select('id')
        .eq('user_id', user.id)
        .eq('food_item_id', foodItemId)
        .limit(1);

    if ((usageRows as List).isNotEmpty) {
      throw StateError(
        'This food has already been used in your food log. '
        'Remove its consumed entries from the food log first, then delete the saved food item.',
      );
    }

    await supabase
        .from('food_items')
        .delete()
        .eq('id', foodItemId)
        .eq('user_id', user.id);
  }

  Future<List<SavedMeal>> getMeals() async {
    final rows = await supabase
        .from('meals')
        .select(
          'id, name, meal_items(servings, food_item_id, food_items(id, name, brand, calories, fat, carbs, protein))',
        )
        .eq('user_id', _userId)
        .order('name', ascending: true);

    final meals = <SavedMeal>[];

    for (final raw in (rows as List)) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);

      final components = <MealComponent>[];
      final itemRows = row['meal_items'];

      if (itemRows is List) {
        for (final itemRaw in itemRows) {
          if (itemRaw is! Map) continue;
          final item = Map<String, dynamic>.from(itemRaw);

          final joinedFood = item['food_items'];
          if (joinedFood is! Map) continue;

          final servingsRaw = item['servings'];
          final servings = servingsRaw is num
              ? servingsRaw.toDouble()
              : double.tryParse((servingsRaw ?? '').toString()) ?? 0;

          final food = FoodItem.fromMap(
            Map<String, dynamic>.from(joinedFood),
          );

          components.add(
            MealComponent(
              foodItemId: (item['food_item_id'] ?? food.id).toString(),
              food: food,
              servings: servings,
            ),
          );
        }
      }

      meals.add(
        SavedMeal(
          id: (row['id'] ?? '').toString(),
          name: (row['name'] ?? '').toString(),
          components: components,
        ),
      );
    }

    meals.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    return meals;
  }

  Future<SavedMeal> addMeal({
    required String name,
    required Map<String, double> foodServings,
  }) async {
    final cleanName = _sanitizeDisplayText(name);

    if (cleanName.isEmpty) {
      throw StateError('Enter a meal name.');
    }

    final validItems = foodServings.entries
        .where((entry) => entry.value > 0)
        .toList();

    if (validItems.isEmpty) {
      throw StateError('Select at least one food item for the meal.');
    }

    final mealRow = await supabase
        .from('meals')
        .insert({
          'user_id': _userId,
          'name': cleanName,
        })
        .select('id, name')
        .single();

    final mealId = (mealRow['id'] ?? '').toString();

    try {
      await supabase.from('meal_items').insert(
        validItems
            .map(
              (entry) => {
                'meal_id': mealId,
                'food_item_id': entry.key,
                'servings': entry.value,
              },
            )
            .toList(),
      );
    } catch (_) {
      await supabase
          .from('meals')
          .delete()
          .eq('id', mealId)
          .eq('user_id', _userId);
      rethrow;
    }

    final meals = await getMeals();
    return meals.firstWhere((meal) => meal.id == mealId);
  }

  Future<void> consumeMeal({
    required SavedMeal meal,
    double mealQuantity = 1,
    DateTime? consumedAt,
  }) async {
    if (mealQuantity <= 0) {
      throw StateError('Meal quantity must be greater than zero.');
    }

    if (meal.components.isEmpty) {
      throw StateError('This meal does not contain any food items.');
    }

    final timestamp =
        (consumedAt ?? DateTime.now()).toUtc().toIso8601String();

    await supabase.from('food_consumptions').insert(
      meal.components
          .map(
            (component) => {
              'user_id': _userId,
              'food_item_id': component.foodItemId,
              'servings': component.servings * mealQuantity,
              'consumed_at': timestamp,
            },
          )
          .toList(),
    );
  }

  Future<void> consumeFood({
    required String foodItemId,
    required double servings,
    DateTime? consumedAt,
  }) async {
    await supabase.from('food_consumptions').insert({
      'user_id': _userId,
      'food_item_id': foodItemId,
      'servings': servings,
      'consumed_at': (consumedAt ?? DateTime.now()).toUtc().toIso8601String(),
    });
  }

  Future<void> deleteConsumption(String consumptionId) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw StateError('User must be logged in.');
    }

    await supabase
        .from('food_consumptions')
        .delete()
        .eq('id', consumptionId)
        .eq('user_id', user.id);
  }

  Future<List<ConsumedFood>> getConsumptionHistory({int limit = 1000}) async {
    final rows = await supabase
        .from('food_consumptions')
        .select(
          'id, consumed_at, servings, food_items!inner(id, name, brand, calories, fat, carbs, protein)',
        )
        .eq('user_id', _userId)
        .order('consumed_at', ascending: false)
        .limit(limit);

    final result = <ConsumedFood>[];

    for (final raw in (rows as List)) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);

      final joined = row['food_items'];
      Map<String, dynamic>? foodMap;
      if (joined is Map) {
        foodMap = Map<String, dynamic>.from(joined);
      } else if (joined is List && joined.isNotEmpty && joined.first is Map) {
        foodMap = Map<String, dynamic>.from(joined.first as Map);
      }
      if (foodMap == null) continue;

      final parsed = DateTime.tryParse((row['consumed_at'] ?? '').toString());
      if (parsed == null) continue;

      final servingsRaw = row['servings'];
      final servings = servingsRaw is num
          ? servingsRaw.toDouble()
          : double.tryParse((servingsRaw ?? '').toString()) ?? 0;

      result.add(
        ConsumedFood(
          id: (row['id'] ?? '').toString(),
          consumedAt: parsed.toLocal(),
          servings: servings,
          food: FoodItem.fromMap(foodMap),
        ),
      );
    }

    return result;
  }
}
