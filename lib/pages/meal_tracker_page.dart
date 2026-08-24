import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/meal_service.dart';
import 'nutrition_label_scanner.dart';

class DailyMealSummary {
  final DateTime day;
  final List<ConsumedFood> items;

  const DailyMealSummary({
    required this.day,
    required this.items,
  });

  double get calories => items.fold(0, (sum, item) => sum + item.calories);
  double get fat => items.fold(0, (sum, item) => sum + item.fat);
  double get carbs => items.fold(0, (sum, item) => sum + item.carbs);
  double get protein => items.fold(0, (sum, item) => sum + item.protein);
}

class MealTrackerPage extends StatefulWidget {
  const MealTrackerPage({super.key});

  @override
  State<MealTrackerPage> createState() => _MealTrackerPageState();
}

class _MealTrackerPageState extends State<MealTrackerPage> {
  final MealService _mealService = MealService();
  final TextEditingController _consumeFoodSearchController = TextEditingController();
  final TextEditingController _consumeMealSearchController = TextEditingController();
  final FocusNode _consumeFoodSearchFocus = FocusNode();
  final FocusNode _consumeMealSearchFocus = FocusNode();

  bool _isLoading = true;
  List<FoodItem> _foodItems = [];
  List<SavedMeal> _meals = [];
  List<DailyMealSummary> _dailySummaries = [];
  final Set<DateTime> _expandedLogDays = <DateTime>{};

  DateTime _dayOnly(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  String _formatDate(DateTime value) =>
      '${value.month}/${value.day}/${value.year}';

  String _formatNumber(double value) {
    if ((value - value.round()).abs() < 0.01) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }

  DailyMealSummary get _todaySummary {
    final today = _dayOnly(DateTime.now());
    for (final summary in _dailySummaries) {
      if (summary.day == today) return summary;
    }
    return DailyMealSummary(day: today, items: const []);
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final foods = await _mealService.getFoodItems();
      final meals = await _mealService.getMeals();
      final history = await _mealService.getConsumptionHistory();

      final grouped = <DateTime, List<ConsumedFood>>{};
      for (final item in history) {
        final day = _dayOnly(item.consumedAt);
        grouped.putIfAbsent(day, () => <ConsumedFood>[]).add(item);
      }

      final summaries = grouped.entries
          .map(
            (entry) => DailyMealSummary(
              day: entry.key,
              items: entry.value
                ..sort((a, b) => a.consumedAt.compareTo(b.consumedAt)),
            ),
          )
          .toList()
        ..sort((a, b) => b.day.compareTo(a.day));

      if (!mounted) return;
      foods.sort((a, b) {
        final nameCompare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (nameCompare != 0) return nameCompare;
        return a.brand.toLowerCase().compareTo(b.brand.toLowerCase());
      });

      setState(() {
        _foodItems = foods;
        _meals = meals;
        _dailySummaries = summaries;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load meal tracker: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  static const List<String> _servingUnits = [
    'serving',
    'g',
    'oz',
    'cup',
    'tbsp',
    'tsp',
    'piece',
    'slice',
    'bottle',
    'can',
    'package',
  ];

  String _servingSizeLabel(FoodItem food) {
    return '${_formatNumber(food.servingAmount)} ${food.servingUnit}';
  }

  Future<T?> _showSearchSelectDialog<T>({
    required String title,
    required List<T> items,
    required String Function(T item) titleFor,
    String Function(T item)? subtitleFor,
  }) async {
    final searchController = TextEditingController();
    String query = '';

    final result = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      requestFocus: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final normalized = query.trim().toLowerCase();
            final filtered = items.where((item) {
              if (normalized.isEmpty) return true;
              final itemTitle = titleFor(item).toLowerCase();
              final subtitle = subtitleFor?.call(item).toLowerCase() ?? '';
              return itemTitle.contains(normalized) ||
                  subtitle.contains(normalized);
            }).toList();

            final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
            final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

            return AnimatedPadding(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: keyboardBottom),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: searchController,
                          autofocus: true,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.search,
                          onChanged: (value) => setLocal(() => query = value),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            labelText: 'Search',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Flexible(
                          child: filtered.isEmpty
                              ? const Center(child: Text('No matches.'))
                              : ListView.separated(
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.manual,
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final item = filtered[index];
                                    final subtitle = subtitleFor?.call(item) ?? '';
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(titleFor(item)),
                                      subtitle: subtitle.isEmpty
                                          ? null
                                          : Text(subtitle),
                                      onTap: () =>
                                          Navigator.of(sheetContext).pop(item),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
    return result;
  }

  Widget _searchSelectionField({
    required String label,
    required String value,
    required VoidCallback? onTap,
    String? subtitle,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.search),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (subtitle != null && subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> get _knownBrands {
    final byLowerCase = <String, String>{};

    for (final food in _foodItems) {
      final brand = food.brand.trim();
      if (brand.isEmpty) continue;
      byLowerCase.putIfAbsent(brand.toLowerCase(), () => brand);
    }

    final brands = byLowerCase.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return brands;
  }

  Widget _brandAutocompleteField({
    required TextEditingController controller,
    required FocusNode focusNode,
    bool enabled = true,
  }) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: (option) => option,
      optionsBuilder: (textValue) {
        final query = textValue.text.trim().toLowerCase();
        if (query.isEmpty) return const Iterable<String>.empty();

        return _knownBrands.where((brand) {
          return brand.toLowerCase().contains(query);
        }).take(8);
      },
      onSelected: (brand) {
        controller.value = TextEditingValue(
          text: brand,
          selection: TextSelection.collapsed(offset: brand.length),
        );
      },
      fieldViewBuilder: (
        context,
        textController,
        fieldFocusNode,
        onFieldSubmitted,
      ) {
        return TextField(
          controller: textController,
          focusNode: fieldFocusNode,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          scrollPadding: const EdgeInsets.only(bottom: 220),
          decoration: const InputDecoration(
            labelText: 'Brand',
            hintText: 'Start typing a brand',
            border: OutlineInputBorder(),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final optionList = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 220,
                maxWidth: 360,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: optionList.length,
                itemBuilder: (context, index) {
                  final option = optionList[index];
                  return ListTile(
                    dense: true,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _keyboardAwareTextField({
    required TextEditingController controller,
    required String labelText,
    String? hintText,
    TextInputType? keyboardType,
    bool enabled = true,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction? textInputAction,
    TextAlign textAlign = TextAlign.start,
  }) {
    return Builder(
      builder: (fieldContext) {
        Future<void> revealField() async {
          // On the first keyboard opening, viewInsets is still 0 when the tap
          // callback fires. Wait until Flutter reports the keyboard inset (or
          // until a short fallback timeout) before scrolling the field.
          for (var attempt = 0; attempt < 10; attempt++) {
            if (!fieldContext.mounted) return;
            final keyboardOpen =
                MediaQuery.viewInsetsOf(fieldContext).bottom > 0;
            if (keyboardOpen) break;
            await Future<void>.delayed(const Duration(milliseconds: 60));
          }

          if (!fieldContext.mounted) return;
          await Scrollable.ensureVisible(
            fieldContext,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: 0.16,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );

          // One extra pass catches the final keyboard animation/layout frame.
          await Future<void>.delayed(const Duration(milliseconds: 120));
          if (!fieldContext.mounted) return;
          await Scrollable.ensureVisible(
            fieldContext,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: 0.16,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
        }

        return TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
          textAlign: textAlign,
          scrollPadding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(fieldContext).bottom + 140,
          ),
          onTap: revealField,
          onChanged: (_) {
            if (FocusScope.of(fieldContext).hasFocus) {
              revealField();
            }
          },
          decoration: InputDecoration(
            labelText: labelText,
            hintText: hintText,
            border: const OutlineInputBorder(),
          ),
        );
      },
    );
  }

  Widget _consumeFoodSearchField() {
    return RawAutocomplete<FoodItem>(
      textEditingController: _consumeFoodSearchController,
      focusNode: _consumeFoodSearchFocus,
      displayStringForOption: (food) => food.name,
      optionsBuilder: (textValue) {
        final query = textValue.text.trim().toLowerCase();
        if (query.isEmpty) return const Iterable<FoodItem>.empty();
        return _foodItems.where((food) {
          return food.name.toLowerCase().contains(query) ||
              food.brand.toLowerCase().contains(query);
        }).take(10);
      },
      onSelected: (food) async {
        _consumeFoodSearchController.clear();
        _consumeFoodSearchFocus.unfocus();
        await _consumeSelectedFood(food);
      },
      fieldViewBuilder: (
        context,
        controller,
        focusNode,
        onFieldSubmitted,
      ) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: _foodItems.isNotEmpty,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.restaurant),
            hintText: _foodItems.isEmpty ? 'Add food first' : 'Consume Food',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300, maxWidth: 420),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final food = list[index];
                  return ListTile(
                    dense: true,
                    title: Text(food.name),
                    subtitle: Text([
                      if (food.brand.trim().isNotEmpty) food.brand,
                      'Serving: ${_servingSizeLabel(food)}',
                      '${_formatNumber(food.calories)} cal',
                    ].join(' • ')),
                    onTap: () => onSelected(food),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _consumeMealSearchField() {
    return RawAutocomplete<SavedMeal>(
      textEditingController: _consumeMealSearchController,
      focusNode: _consumeMealSearchFocus,
      displayStringForOption: (meal) => meal.name,
      optionsBuilder: (textValue) {
        final query = textValue.text.trim().toLowerCase();
        if (query.isEmpty) return const Iterable<SavedMeal>.empty();
        return _meals.where((meal) {
          final componentText = meal.components
              .map((component) => _foodDisplayName(component.food))
              .join(' ')
              .toLowerCase();
          return meal.name.toLowerCase().contains(query) ||
              componentText.contains(query);
        }).take(10);
      },
      onSelected: (meal) async {
        _consumeMealSearchController.clear();
        _consumeMealSearchFocus.unfocus();
        await _consumeSelectedMeal(meal);
      },
      fieldViewBuilder: (
        context,
        controller,
        focusNode,
        onFieldSubmitted,
      ) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: _meals.isNotEmpty,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.restaurant_menu),
            hintText: _meals.isEmpty ? 'Add meal first' : 'Consume Meal',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300, maxWidth: 420),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final meal = list[index];
                  return ListTile(
                    dense: true,
                    title: Text(meal.name),
                    subtitle: Text(
                      '${_formatNumber(meal.calories)} cal • '
                      '${meal.components.length} item'
                      '${meal.components.length == 1 ? '' : 's'}',
                    ),
                    onTap: () => onSelected(meal),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAddFoodDialog() async {
    final name = TextEditingController();
    final brand = TextEditingController();
    final brandFocusNode = FocusNode();
    final calories = TextEditingController();
    final fat = TextEditingController();
    final carbs = TextEditingController();
    final protein = TextEditingController();
    final servingAmount = TextEditingController(text: '1');
    final quickNutrition = TextEditingController();
    final quickNutritionFocusNode = FocusNode();
    String servingUnit = 'serving';

    bool saving = false;
    bool scanningNutrition = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          List<MapEntry<String, TextEditingController>> missingNutritionFields() {
            return [
              MapEntry('Calories', calories),
              MapEntry('Fat', fat),
              MapEntry('Carbs', carbs),
              MapEntry('Protein', protein),
            ].where((entry) => entry.value.text.trim().isEmpty).toList();
          }

          void submitQuickNutritionValue() {
            final missing = missingNutritionFields();
            if (missing.isEmpty) return;

            final value = double.tryParse(quickNutrition.text.trim());
            if (value == null || value < 0) {
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text('Enter a valid nutrition value.'),
                ),
              );
              return;
            }

            missing.first.value.text = _formatNumber(value);
            quickNutrition.clear();
            setLocal(() {});

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!quickNutritionFocusNode.canRequestFocus) return;
              quickNutritionFocusNode.requestFocus();
            });
          }

          Future<void> scanNutritionLabel() async {
            if (!nutritionLabelScannerSupported || scanningNutrition || saving) {
              return;
            }

            setLocal(() => scanningNutrition = true);

            try {
              final result = await scanNutritionFactsLabel();
              if (result == null || result.cancelled) return;

              if (result.calories != null) {
                calories.text = _formatNumber(result.calories!);
              }
              if (result.fat != null) {
                fat.text = _formatNumber(result.fat!);
              }
              if (result.carbs != null) {
                carbs.text = _formatNumber(result.carbs!);
              }
              if (result.protein != null) {
                protein.text = _formatNumber(result.protein!);
              }
              if (result.servingAmount != null) {
                servingAmount.text = _formatNumber(result.servingAmount!);
              }

              final scannedUnit = result.servingUnit?.trim().toLowerCase();
              if (scannedUnit != null && _servingUnits.contains(scannedUnit)) {
                servingUnit = scannedUnit;
              }

              setLocal(() {});

              final foundCount = [
                result.calories,
                result.fat,
                result.carbs,
                result.protein,
                result.servingAmount,
              ].where((value) => value != null).length;

              if (!mounted) return;
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Text(
                    foundCount >= 5
                        ? 'Nutrition label scanned. Review the values, then save.'
                        : 'Label scanned, but some values were unclear. Review the fields.',
                  ),
                ),
              );
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(content: Text('Could not scan nutrition label: $e')),
              );
            } finally {
              if (mounted) {
                setLocal(() => scanningNutrition = false);
              }
            }
          }

          Future<void> save() async {
            final parsedCalories = double.tryParse(calories.text.trim());
            final parsedFat = double.tryParse(fat.text.trim());
            final parsedCarbs = double.tryParse(carbs.text.trim());
            final parsedProtein = double.tryParse(protein.text.trim());
            final parsedServingAmount =
                double.tryParse(servingAmount.text.trim());

            if (name.text.trim().isEmpty ||
                brand.text.trim().isEmpty ||
                parsedCalories == null ||
                parsedFat == null ||
                parsedCarbs == null ||
                parsedProtein == null ||
                parsedServingAmount == null ||
                parsedServingAmount <= 0 ||
                parsedCalories < 0 ||
                parsedFat < 0 ||
                parsedCarbs < 0 ||
                parsedProtein < 0) {
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Enter a name, brand, serving size, and valid nutrition values.',
                  ),
                ),
              );
              return;
            }

            setLocal(() => saving = true);

            try {
              await _mealService.addFoodItem(
                name: name.text,
                brand: brand.text,
                calories: parsedCalories,
                fat: parsedFat,
                carbs: parsedCarbs,
                protein: parsedProtein,
                servingAmount: parsedServingAmount,
                servingUnit: servingUnit,
              );

              if (!mounted) return;
              Navigator.of(dialogContext).pop();
              await _loadData();
            } catch (e) {
              if (!mounted) return;
              setLocal(() => saving = false);
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(content: Text('Could not add food: $e')),
              );
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('Add Food Item')),
                if (nutritionLabelScannerSupported)
                  IconButton(
                    tooltip: 'Scan nutrition label',
                    onPressed: saving || scanningNutrition
                        ? null
                        : scanNutritionLabel,
                    icon: scanningNutrition
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt_outlined),
                  ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _keyboardAwareTextField(
                    controller: name,
                    labelText: 'Food name',
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _brandAutocompleteField(
                    controller: brand,
                    focusNode: brandFocusNode,
                    enabled: !saving,
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final missing = missingNutritionFields();
                      if (missing.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      final nextLabel = missing.first.key;
                      final remainingLabels =
                          missing.map((entry) => entry.key).join(' • ');

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Quick fill missing: $remainingLabels',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: quickNutrition,
                            focusNode: quickNutritionFocusNode,
                            enabled: !saving && !scanningNutrition,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => submitQuickNutritionValue(),
                            decoration: InputDecoration(
                              labelText: 'Enter $nextLabel',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: 'Apply and continue',
                                onPressed: saving || scanningNutrition
                                    ? null
                                    : submitQuickNutritionValue,
                                icon: const Icon(Icons.arrow_forward),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _keyboardAwareTextField(
                          controller: servingAmount,
                          labelText: 'Serving size',
                          hintText: 'Example: 28',
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: servingUnit,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Unit',
                            border: OutlineInputBorder(),
                          ),
                          items: _servingUnits
                              .map(
                                (unit) => DropdownMenuItem(
                                  value: unit,
                                  child: Text(unit),
                                ),
                              )
                              .toList(),
                          onChanged: saving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setLocal(() => servingUnit = value);
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _keyboardAwareTextField(
                    controller: calories,
                    labelText: 'Calories per serving',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _keyboardAwareTextField(
                    controller: fat,
                    labelText: 'Fat (g) per serving',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _keyboardAwareTextField(
                    controller: carbs,
                    labelText: 'Carbs (g) per serving',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _keyboardAwareTextField(
                    controller: protein,
                    labelText: 'Protein (g) per serving',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    saving ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: saving ? null : save,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save Food'),
              ),
            ],
          );
        },
      ),
    );

    name.dispose();
    brandFocusNode.dispose();
    brand.dispose();
    calories.dispose();
    fat.dispose();
    carbs.dispose();
    protein.dispose();
    servingAmount.dispose();
    quickNutrition.dispose();
    quickNutritionFocusNode.dispose();
  }

  Future<void> _openEditFoodDialog(FoodItem food) async {
    final name = TextEditingController(text: food.name);
    final brand = TextEditingController(text: food.brand);
    final brandFocusNode = FocusNode();
    final calories = TextEditingController(text: _formatNumber(food.calories));
    final fat = TextEditingController(text: _formatNumber(food.fat));
    final carbs = TextEditingController(text: _formatNumber(food.carbs));
    final protein = TextEditingController(text: _formatNumber(food.protein));
    final servingAmount =
        TextEditingController(text: _formatNumber(food.servingAmount));
    String servingUnit = food.servingUnit;

    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> save() async {
            final parsedCalories = double.tryParse(calories.text.trim());
            final parsedFat = double.tryParse(fat.text.trim());
            final parsedCarbs = double.tryParse(carbs.text.trim());
            final parsedProtein = double.tryParse(protein.text.trim());
            final parsedServingAmount =
                double.tryParse(servingAmount.text.trim());

            if (name.text.trim().isEmpty ||
                brand.text.trim().isEmpty ||
                parsedCalories == null ||
                parsedFat == null ||
                parsedCarbs == null ||
                parsedProtein == null ||
                parsedServingAmount == null ||
                parsedServingAmount <= 0 ||
                parsedCalories < 0 ||
                parsedFat < 0 ||
                parsedCarbs < 0 ||
                parsedProtein < 0) {
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Enter a name, brand, serving size, and valid nutrition values.',
                  ),
                ),
              );
              return;
            }

            setLocal(() => saving = true);

            try {
              await _mealService.updateFoodItem(
                foodItemId: food.id,
                name: name.text,
                brand: brand.text,
                calories: parsedCalories,
                fat: parsedFat,
                carbs: parsedCarbs,
                protein: parsedProtein,
                servingAmount: parsedServingAmount,
                servingUnit: servingUnit,
              );

              if (!mounted) return;
              Navigator.of(dialogContext).pop();
              await _loadData();

              if (!mounted) return;
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(content: Text('Food item updated.')),
              );
            } catch (e) {
              if (!mounted) return;
              setLocal(() => saving = false);
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(content: Text('Could not update food: $e')),
              );
            }
          }

          return AlertDialog(
            title: const Text('Edit Food Item'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Changes to nutrition values will also update past food-log '
                    'entries that used this saved food item.',
                  ),
                  const SizedBox(height: 14),
                  _keyboardAwareTextField(
                    controller: name,
                    labelText: 'Food name',
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _brandAutocompleteField(
                    controller: brand,
                    focusNode: brandFocusNode,
                    enabled: !saving,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _keyboardAwareTextField(
                          controller: servingAmount,
                          labelText: 'Serving size',
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _servingUnits.contains(servingUnit)
                              ? servingUnit
                              : 'serving',
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Unit',
                            border: OutlineInputBorder(),
                          ),
                          items: _servingUnits
                              .map(
                                (unit) => DropdownMenuItem(
                                  value: unit,
                                  child: Text(unit),
                                ),
                              )
                              .toList(),
                          onChanged: saving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setLocal(() => servingUnit = value);
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _keyboardAwareTextField(
                    controller: calories,
                    labelText: 'Calories per serving',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _keyboardAwareTextField(
                    controller: fat,
                    labelText: 'Fat (g) per serving',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _keyboardAwareTextField(
                    controller: carbs,
                    labelText: 'Carbs (g) per serving',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  _keyboardAwareTextField(
                    controller: protein,
                    labelText: 'Protein (g) per serving',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    saving ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: saving ? null : save,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );

    name.dispose();
    brandFocusNode.dispose();
    brand.dispose();
    calories.dispose();
    fat.dispose();
    carbs.dispose();
    protein.dispose();
    servingAmount.dispose();
  }

  Future<void> _openEditMealDialog(SavedMeal meal) async {
    final mealName = TextEditingController(text: meal.name);

    final selectedIds = meal.components
        .map((component) => component.foodItemId)
        .toSet();

    final servingControllers = <String, TextEditingController>{
      for (final food in _foodItems)
        food.id: TextEditingController(
          text: _formatNumber(
            meal.components
                .where((component) => component.foodItemId == food.id)
                .map((component) => component.servings)
                .fold<double>(0, (sum, value) => sum + value),
          ),
        ),
    };

    for (final food in _foodItems) {
      if (!selectedIds.contains(food.id)) {
        servingControllers[food.id]!.text = '1';
      }
    }

    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> saveMeal() async {
            final name = mealName.text.trim();

            if (name.isEmpty || selectedIds.isEmpty) {
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Enter a meal name and select at least one food item.',
                  ),
                ),
              );
              return;
            }

            final components = <String, double>{};

            for (final foodId in selectedIds) {
              final quantity = double.tryParse(
                servingControllers[foodId]!.text.trim(),
              );

              if (quantity == null || quantity <= 0) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Every selected food needs a serving quantity greater than zero.',
                    ),
                  ),
                );
                return;
              }

              components[foodId] = quantity;
            }

            setLocal(() => saving = true);

            try {
              await _mealService.updateMeal(
                mealId: meal.id,
                name: name,
                foodServings: components,
              );

              if (!mounted) return;
              Navigator.of(dialogContext).pop();
              await _loadData();

              if (!mounted) return;
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(content: Text('Meal updated.')),
              );
            } catch (e) {
              if (!mounted) return;
              setLocal(() => saving = false);
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(content: Text('Could not update meal: $e')),
              );
            }
          }

          return AlertDialog(
            title: const Text('Edit Meal'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: mealName,
                    decoration: const InputDecoration(
                      labelText: 'Meal name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _foodItems.length,
                      separatorBuilder: (_, __) => const Divider(height: 18),
                      itemBuilder: (context, index) {
                        final food = _foodItems[index];
                        final selected = selectedIds.contains(food.id);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Checkbox(
                              value: selected,
                              onChanged: saving
                                  ? null
                                  : (value) {
                                      setLocal(() {
                                        if (value == true) {
                                          selectedIds.add(food.id);
                                        } else {
                                          selectedIds.remove(food.id);
                                        }
                                      });
                                    },
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    food.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (food.brand.trim().isNotEmpty)
                                    Text(
                                      food.brand,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  Text(
                                    'Serving: ${_servingSizeLabel(food)}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 18),
                            SizedBox(
                              width: 88,
                              child: _keyboardAwareTextField(
                                controller: servingControllers[food.id]!,
                                labelText: 'Qty',
                                enabled: selected && !saving,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                textAlign: TextAlign.center,
                                textInputAction: TextInputAction.done,
                              ),
                            ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    saving ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: saving ? null : saveMeal,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );

    mealName.dispose();
    for (final controller in servingControllers.values) {
      controller.dispose();
    }
  }

  Future<void> _openManageMealsDialog() async {
    if (_meals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved meals to manage.')),
      );
      return;
    }

    final searchController = TextEditingController();
    String query = '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          final normalized = query.trim().toLowerCase();
          final filteredMeals = _meals.where((meal) {
            if (normalized.isEmpty) return true;
            final components = meal.components
                .map((component) => _foodDisplayName(component.food))
                .join(' ')
                .toLowerCase();
            return meal.name.toLowerCase().contains(normalized) ||
                components.contains(normalized);
          }).toList();

          return AlertDialog(
            title: const Text('Manage Meals'),
            content: SizedBox(
              width: double.maxFinite,
              height: 520,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    onChanged: (value) {
                      setLocal(() => query = value);
                    },
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search meals',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredMeals.isEmpty
                        ? const Center(child: Text('No matching meals.'))
                        : ListView.separated(
                            itemCount: filteredMeals.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final meal = filteredMeals[index];

                              final componentText = meal.components
                                  .map(
                                    (component) =>
                                        '${component.food.name} × ${_formatNumber(component.servings)}',
                                  )
                                  .join(' • ');

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  meal.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  componentText,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Wrap(
                                  spacing: 0,
                                  children: [
                                    IconButton(
                                      tooltip: 'Edit meal',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () async {
                                        await _openEditMealDialog(meal);
                                        if (mounted) setLocal(() {});
                                      },
                                    ),
                                    IconButton(
                                      tooltip: 'Delete meal',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        final confirmed =
                                            await showDialog<bool>(
                                          context: this.context,
                                          builder: (confirmContext) =>
                                              AlertDialog(
                                            title:
                                                const Text('Delete meal?'),
                                            content: Text(
                                              'Delete ${meal.name} from your saved meals?\n\n'
                                              'This only deletes the reusable meal template. '
                                              'Food-log entries you already consumed will remain.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(confirmContext)
                                                        .pop(false),
                                                child: const Text('Cancel'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.of(confirmContext)
                                                        .pop(true),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirmed != true) return;

                                        try {
                                          await _mealService
                                              .deleteMeal(meal.id);
                                          await _loadData();

                                          if (!mounted) return;
                                          setLocal(() {});

                                          ScaffoldMessenger.of(this.context)
                                              .showSnackBar(
                                            SnackBar(
                                              content:
                                                  Text('${meal.name} deleted.'),
                                            ),
                                          );

                                          if (_meals.isEmpty &&
                                              Navigator.of(dialogContext)
                                                  .canPop()) {
                                            Navigator.of(dialogContext).pop();
                                          }
                                        } catch (e) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(this.context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Could not delete meal: $e',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );

    searchController.dispose();
  }

  Future<void> _openManageFoodItemsDialog() async {
    if (_foodItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved food items to manage.')),
      );
      return;
    }

    final searchController = TextEditingController();
    String query = '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          final normalized = query.trim().toLowerCase();
          final filteredFoods = _foodItems.where((food) {
            if (normalized.isEmpty) return true;
            return food.name.toLowerCase().contains(normalized) ||
                food.brand.toLowerCase().contains(normalized);
          }).toList();

          return AlertDialog(
            title: const Text('Manage Food Items'),
            content: SizedBox(
              width: double.maxFinite,
              height: 520,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    onChanged: (value) {
                      setLocal(() => query = value);
                    },
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search foods',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredFoods.isEmpty
                        ? const Center(child: Text('No matching foods.'))
                        : ListView.separated(
                            itemCount: filteredFoods.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final food = filteredFoods[index];

                              final details = <String>[
                                if (food.brand.trim().isNotEmpty) food.brand,
                                'Serving: ${_servingSizeLabel(food)}',
                              ].join(' • ');

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  food.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(details),
                                trailing: Wrap(
                                  spacing: 0,
                                  children: [
                                    IconButton(
                                      tooltip: 'Edit food item',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () async {
                                        await _openEditFoodDialog(food);
                                        if (mounted) setLocal(() {});
                                      },
                                    ),
                                    IconButton(
                                      tooltip: 'Delete food item',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        final displayName =
                                            _foodDisplayName(food);

                                        final confirmed =
                                            await showDialog<bool>(
                                          context: this.context,
                                          builder: (confirmContext) =>
                                              AlertDialog(
                                            title: const Text(
                                              'Delete food item?',
                                            ),
                                            content: Text(
                                              'Delete $displayName from your saved foods?\n\n'
                                              'If this food has already been used in a food log, '
                                              'Fit Quest will keep it until those consumed entries '
                                              'are removed first.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(confirmContext)
                                                        .pop(false),
                                                child: const Text('Cancel'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.of(confirmContext)
                                                        .pop(true),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirmed != true) return;

                                        try {
                                          await _mealService
                                              .deleteFoodItem(food.id);
                                          await _loadData();

                                          if (!mounted) return;
                                          setLocal(() {});

                                          ScaffoldMessenger.of(this.context)
                                              .showSnackBar(
                                            SnackBar(
                                              content:
                                                  Text('$displayName deleted.'),
                                            ),
                                          );

                                          if (_foodItems.isEmpty &&
                                              Navigator.of(dialogContext)
                                                  .canPop()) {
                                            Navigator.of(dialogContext).pop();
                                          }
                                        } catch (e) {
                                          if (!mounted) return;

                                          final message = e
                                              .toString()
                                              .replaceFirst(
                                                'Bad state: ',
                                                '',
                                              );

                                          ScaffoldMessenger.of(this.context)
                                              .showSnackBar(
                                            SnackBar(content: Text(message)),
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );

    searchController.dispose();
  }

  Future<void> _openAddMealDialog() async {
    if (_foodItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add food items before creating a meal.'),
        ),
      );
      return;
    }

    final mealName = TextEditingController();
    final selectedIds = <String>{};
    final servingControllers = <String, TextEditingController>{
      for (final food in _foodItems)
        food.id: TextEditingController(text: '1'),
    };

    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> saveMeal() async {
            final name = mealName.text.trim();

            if (name.isEmpty || selectedIds.isEmpty) {
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Enter a meal name and select at least one food item.',
                  ),
                ),
              );
              return;
            }

            final components = <String, double>{};

            for (final foodId in selectedIds) {
              final quantity = double.tryParse(
                servingControllers[foodId]!.text.trim(),
              );

              if (quantity == null || quantity <= 0) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Every selected food needs a serving quantity greater than zero.',
                    ),
                  ),
                );
                return;
              }

              components[foodId] = quantity;
            }

            setLocal(() => saving = true);

            try {
              await _mealService.addMeal(
                name: name,
                foodServings: components,
              );

              if (!mounted) return;
              Navigator.of(dialogContext).pop();
              await _loadData();

              if (!mounted) return;
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(content: Text('Meal saved.')),
              );
            } catch (e) {
              if (!mounted) return;
              setLocal(() => saving = false);
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(content: Text('Could not save meal: $e')),
              );
            }
          }

          return AlertDialog(
            title: const Text('Add Meal'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: mealName,
                    decoration: const InputDecoration(
                      labelText: 'Meal name',
                      hintText: 'Quart Tupperware Of Ground Beef Alfredo Pasta',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _foodItems.length,
                      separatorBuilder: (_, __) => const Divider(height: 18),
                      itemBuilder: (context, index) {
                        final food = _foodItems[index];
                        final selected = selectedIds.contains(food.id);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Checkbox(
                              value: selected,
                              onChanged: saving
                                  ? null
                                  : (value) {
                                      setLocal(() {
                                        if (value == true) {
                                          selectedIds.add(food.id);
                                        } else {
                                          selectedIds.remove(food.id);
                                        }
                                      });
                                    },
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    food.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (food.brand.trim().isNotEmpty)
                                    Text(
                                      food.brand,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  Text(
                                    'Serving: ${_servingSizeLabel(food)}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 18),
                            SizedBox(
                              width: 88,
                              child: _keyboardAwareTextField(
                                controller: servingControllers[food.id]!,
                                labelText: 'Qty',
                                enabled: selected && !saving,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                textAlign: TextAlign.center,
                                textInputAction: TextInputAction.done,
                              ),
                            ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    saving ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: saving ? null : saveMeal,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save Meal'),
              ),
            ],
          );
        },
      ),
    );

    mealName.dispose();
    for (final controller in servingControllers.values) {
      controller.dispose();
    }
  }

  Future<void> _consumeSelectedMeal(SavedMeal selected) async {
    final quantity = TextEditingController(text: '1');
    DateTime selectedDate = _dayOnly(DateTime.now());
    bool saving = false;

    DateTime consumptionTimestamp() {
      final now = DateTime.now();
      final today = _dayOnly(now);

      // Normal logging keeps the real current time.
      if (selectedDate == today) {
        return now;
      }

      // A backfilled entry should appear after everything that was already
      // logged on that prior day. Put it at the very end of the selected day
      // rather than transplanting today's clock time onto the old date.
      return DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        23,
        59,
        59,
        999,
        999,
      );
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          final multiplier = double.tryParse(quantity.text.trim()) ?? 0;
          final today = _dayOnly(DateTime.now());
          final dateLabel = selectedDate == today
              ? 'Today · ${_formatDate(selectedDate)}'
              : _formatDate(selectedDate);

          Future<void> chooseDate() async {
            final picked = await showDatePicker(
              context: dialogContext,
              initialDate: selectedDate,
              firstDate: DateTime(2000),
              lastDate: today,
              helpText: 'Select log date',
            );

            if (picked != null) {
              setLocal(() => selectedDate = _dayOnly(picked));
            }
          }

          Future<void> consume() async {
            final count = double.tryParse(quantity.text.trim());

            if (count == null || count <= 0) {
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text('Enter a meal quantity greater than zero.'),
                ),
              );
              return;
            }

            setLocal(() => saving = true);

            try {
              await _mealService.consumeMeal(
                meal: selected,
                mealQuantity: count,
                consumedAt: consumptionTimestamp(),
              );

              if (!mounted) return;
              Navigator.of(dialogContext).pop();
              await _loadData();
            } catch (e) {
              if (!mounted) return;
              setLocal(() => saving = false);
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(content: Text('Could not consume meal: $e')),
              );
            }
          }

          return AlertDialog(
            title: Text('Consume ${selected.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: quantity,
                    autofocus: true,
                    onChanged: (_) => setLocal(() {}),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Meal quantity',
                      hintText: 'Example: 1, 0.5, 2',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: saving ? null : chooseDate,
                    borderRadius: BorderRadius.circular(4),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Log date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      child: Text(
                        dateLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '1 meal',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_formatNumber(selected.calories)} cal • '
                    '${_formatNumber(selected.protein)}g protein • '
                    '${_formatNumber(selected.carbs)}g carbs • '
                    '${_formatNumber(selected.fat)}g fat',
                  ),
                  const SizedBox(height: 10),
                  ...selected.components.map(
                    (component) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• ${_foodDisplayName(component.food)} × '
                        '${_formatNumber(component.servings)} '
                        '(${_servingSizeLabel(component.food)} each)',
                      ),
                    ),
                  ),
                  if (multiplier > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      'This entry',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_formatNumber(selected.calories * multiplier)} cal • '
                      '${_formatNumber(selected.protein * multiplier)}g protein • '
                      '${_formatNumber(selected.carbs * multiplier)}g carbs • '
                      '${_formatNumber(selected.fat * multiplier)}g fat',
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    saving ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: saving ? null : consume,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restaurant_menu),
                label: const Text('Consume Meal'),
              ),
            ],
          );
        },
      ),
    );

    quantity.dispose();
  }

  Future<void> _consumeSelectedFood(FoodItem selected) async {
    final servings = TextEditingController(text: '1');
    DateTime selectedDate = _dayOnly(DateTime.now());
    bool saving = false;

    DateTime consumptionTimestamp() {
      final now = DateTime.now();
      final today = _dayOnly(now);

      // Normal logging keeps the real current time.
      if (selectedDate == today) {
        return now;
      }

      // A backfilled entry should appear after everything that was already
      // logged on that prior day. Put it at the very end of the selected day
      // rather than transplanting today's clock time onto the old date.
      return DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        23,
        59,
        59,
        999,
        999,
      );
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          final preview = double.tryParse(servings.text.trim()) ?? 0;
          final today = _dayOnly(DateTime.now());
          final dateLabel = selectedDate == today
              ? 'Today · ${_formatDate(selectedDate)}'
              : _formatDate(selectedDate);

          Future<void> chooseDate() async {
            final picked = await showDatePicker(
              context: dialogContext,
              initialDate: selectedDate,
              firstDate: DateTime(2000),
              lastDate: today,
              helpText: 'Select log date',
            );

            if (picked != null) {
              setLocal(() => selectedDate = _dayOnly(picked));
            }
          }

          Future<void> consume() async {
            final count = double.tryParse(servings.text.trim());
            if (count == null || count <= 0) {
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text('Enter a serving quantity greater than zero.'),
                ),
              );
              return;
            }

            setLocal(() => saving = true);

            try {
              await _mealService.consumeFood(
                foodItemId: selected.id,
                servings: count,
                consumedAt: consumptionTimestamp(),
              );

              if (!mounted) return;
              Navigator.of(dialogContext).pop();
              await _loadData();
            } catch (e) {
              if (!mounted) return;
              setLocal(() => saving = false);
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(content: Text('Could not log food: $e')),
              );
            }
          }

          return AlertDialog(
            title: Text('Consume ${selected.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selected.brand.trim().isNotEmpty) ...[
                    Text(
                      selected.brand,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: servings,
                    autofocus: true,
                    onChanged: (_) => setLocal(() {}),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Servings consumed',
                      hintText: 'Example: 1, 0.5, 1.5',
                      helperText:
                          '1 serving = ${_servingSizeLabel(selected)}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: saving ? null : chooseDate,
                    borderRadius: BorderRadius.circular(4),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Log date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      child: Text(
                        dateLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Per serving (${_servingSizeLabel(selected)})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_formatNumber(selected.calories)} cal • '
                    '${_formatNumber(selected.carbs)}g carbs • '
                    '${_formatNumber(selected.protein)}g protein • '
                    '${_formatNumber(selected.fat)}g fat',
                  ),
                  if (preview > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      'This entry',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_formatNumber(selected.calories * preview)} cal • '
                      '${_formatNumber(selected.carbs * preview)}g carbs • '
                      '${_formatNumber(selected.protein * preview)}g protein • '
                      '${_formatNumber(selected.fat * preview)}g fat',
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    saving ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: saving ? null : consume,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restaurant),
                label: const Text('Consume'),
              ),
            ],
          );
        },
      ),
    );

    servings.dispose();
  }

  String _foodDisplayName(FoodItem food) {
    final name = food.name.trim();
    final brand = food.brand.trim();
    if (brand.isEmpty) return name;
    return '$name • $brand';
  }

  String _buildFoodLogShareText(List<DailyMealSummary> summaries) {
    final buffer = StringBuffer();
    buffer.writeln('Fit Quest — Food Log');
    buffer.writeln();

    final ordered = [...summaries]..sort((a, b) => b.day.compareTo(a.day));

    for (var summaryIndex = 0;
        summaryIndex < ordered.length;
        summaryIndex++) {
      final summary = ordered[summaryIndex];

      buffer.writeln(_formatDate(summary.day));
      buffer.writeln('DAILY TOTAL');
      buffer.writeln('Calories: ${_formatNumber(summary.calories)}');
      buffer.writeln('Protein: ${_formatNumber(summary.protein)}g');
      buffer.writeln('Carbs: ${_formatNumber(summary.carbs)}g');
      buffer.writeln('Fat: ${_formatNumber(summary.fat)}g');
      buffer.writeln();
      buffer.writeln('FOODS');
      buffer.writeln();

      for (final item in summary.items) {
        buffer.writeln(_foodDisplayName(item.food));
        buffer.writeln(
          '${_formatNumber(item.servings)} serving'
          '${item.servings == 1 ? '' : 's'}',
        );
        buffer.writeln('Calories: ${_formatNumber(item.calories)}');
        buffer.writeln(
          'Protein: ${_formatNumber(item.protein)}g   '
          'Carbs: ${_formatNumber(item.carbs)}g   '
          'Fat: ${_formatNumber(item.fat)}g',
        );
        buffer.writeln();
      }

      if (summaryIndex < ordered.length - 1) {
        buffer.writeln('--------------------');
        buffer.writeln();
      }
    }

    return buffer.toString().trim();
  }

  Future<void> _shareFoodLogs(List<DailyMealSummary> summaries) async {
    if (summaries.isEmpty) return;
    await Share.share(
      _buildFoodLogShareText(summaries),
      subject: 'Fit Quest Food Log',
    );
  }

  Future<void> _openShareFoodLogPicker() async {
    if (_dailySummaries.isEmpty) return;

    final selectedDays = <DateTime>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          void toggleAll(bool select) {
            setLocal(() {
              selectedDays.clear();
              if (select) {
                selectedDays.addAll(_dailySummaries.map((summary) => summary.day));
              }
            });
          }

          return AlertDialog(
            title: const Text('Share food logs'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => toggleAll(true),
                        child: const Text('Select all'),
                      ),
                      TextButton(
                        onPressed: () => toggleAll(false),
                        child: const Text('Clear'),
                      ),
                      const Spacer(),
                      Text(
                        '${selectedDays.length}/${_dailySummaries.length}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const Divider(),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _dailySummaries.length,
                      itemBuilder: (context, index) {
                        final summary = _dailySummaries[index];
                        final checked = selectedDays.contains(summary.day);

                        return CheckboxListTile(
                          value: checked,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(_formatDate(summary.day)),
                          subtitle: Text(
                            '${_formatNumber(summary.calories)} cal • '
                            'P ${_formatNumber(summary.protein)}g • '
                            'C ${_formatNumber(summary.carbs)}g • '
                            'F ${_formatNumber(summary.fat)}g',
                          ),
                          onChanged: (value) {
                            setLocal(() {
                              if (value == true) {
                                selectedDays.add(summary.day);
                              } else {
                                selectedDays.remove(summary.day);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: selectedDays.isEmpty
                    ? null
                    : () async {
                        final picked = _dailySummaries
                            .where((summary) => selectedDays.contains(summary.day))
                            .toList();
                        Navigator.of(dialogContext).pop();
                        await _shareFoodLogs(picked);
                      },
                icon: const Icon(Icons.share),
                label: const Text('Share selected'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _confirmDeleteConsumedFood(ConsumedFood item) async {
    final foodName = item.food.brand.trim().isEmpty
        ? item.food.name
        : '${item.food.name} • ${item.food.brand}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove consumed item?'),
        content: Text(
          "Remove $foodName from this day's food log? "
          'This will not delete the saved food item itself.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      await _mealService.deleteConsumption(item.id);
      await _loadData();

      if (!mounted) return true;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Consumed item removed.')),
      );

      return true;
    } catch (e) {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove consumed item: $e')),
      );

      return false;
    }
  }

  Widget _metricBox(String label, double value, {String suffix = 'g'}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              _formatNumber(value),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              suffix.isEmpty ? label : '$label ($suffix)',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _macroHeaderCell(String label) {
    return SizedBox(
      width: 44,
      child: Text(
        label,
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _macroValueCell(double value) {
    return SizedBox(
      width: 44,
      child: Text(
        _formatNumber(value),
        textAlign: TextAlign.right,
      ),
    );
  }

  Widget _dailySummaryCard(DailyMealSummary summary) {
    final expanded = _expandedLogDays.contains(summary.day);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (expanded) {
                  _expandedLogDays.remove(summary.day);
                } else {
                  _expandedLogDays.add(summary.day);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatDate(summary.day),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Share this day',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _shareFoodLogs([summary]),
                        icon: const Icon(Icons.share_outlined, size: 20),
                      ),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      Text(
                        '${_formatNumber(summary.calories)} cal',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text('P ${_formatNumber(summary.protein)}g'),
                      Text('C ${_formatNumber(summary.carbs)}g'),
                      Text('F ${_formatNumber(summary.fat)}g'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Foods',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  _macroHeaderCell('P'),
                  _macroHeaderCell('C'),
                  _macroHeaderCell('F'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Column(
                children: summary.items
                    .map(
                      (item) => Dismissible(
                        key: ValueKey('consumed-${item.id}'),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) =>
                            _confirmDeleteConsumedFood(item),
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _foodDisplayName(item.food),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_formatNumber(item.servings)} serving'
                                      '${item.servings == 1 ? '' : 's'} '
                                      '(${_servingSizeLabel(item.food)} each)'
                                      ' • ${_formatNumber(item.calories)} cal',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              _macroValueCell(item.protein),
                              _macroValueCell(item.carbs),
                              _macroValueCell(item.fat),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _consumeFoodSearchController.dispose();
    _consumeMealSearchController.dispose();
    _consumeFoodSearchFocus.dispose();
    _consumeMealSearchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = _todaySummary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal Tracker'),
        actions: [
          IconButton(
            tooltip: 'Share food log',
            onPressed: _dailySummaries.isEmpty ? null : _openShareFoodLogPicker,
            icon: const Icon(Icons.share),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    "Today's Nutrition",
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _metricBox('Calories', today.calories, suffix: ''),
                      const SizedBox(width: 8),
                      _metricBox('Carbs', today.carbs),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _metricBox('Protein', today.protein),
                      const SizedBox(width: 8),
                      _metricBox('Fat', today.fat),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _consumeFoodSearchField(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openAddFoodDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Food Item'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _consumeMealSearchField(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _foodItems.isEmpty ? null : _openAddMealDialog,
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Add Meal'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _foodItems.isEmpty
                          ? null
                          : _openManageFoodItemsDialog,
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Manage Food Items'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          _meals.isEmpty ? null : _openManageMealsDialog,
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('Manage Meals'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Food Log',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (_dailySummaries.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No food has been logged yet. Add a food item, then consume it to begin tracking.',
                        ),
                      ),
                    )
                  else
                    ..._dailySummaries.map(_dailySummaryCard),
                ],
              ),
            ),
    );
  }
}
