import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/meal_service.dart';

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

  bool _isLoading = true;
  List<FoodItem> _foodItems = [];
  List<DailyMealSummary> _dailySummaries = [];

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

  Future<void> _openAddFoodDialog() async {
    final name = TextEditingController();
    final brand = TextEditingController();
    final calories = TextEditingController();
    final fat = TextEditingController();
    final carbs = TextEditingController();
    final protein = TextEditingController();

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

            if (name.text.trim().isEmpty ||
                brand.text.trim().isEmpty ||
                parsedCalories == null ||
                parsedFat == null ||
                parsedCarbs == null ||
                parsedProtein == null ||
                parsedCalories < 0 ||
                parsedFat < 0 ||
                parsedCarbs < 0 ||
                parsedProtein < 0) {
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Enter a name, brand, and valid nutrition values.',
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
            title: const Text('Add Food Item'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Food name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: brand,
                    decoration: const InputDecoration(
                      labelText: 'Brand',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: calories,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Calories per serving',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: fat,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Fat (g) per serving',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: carbs,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Carbs (g) per serving',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: protein,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Protein (g) per serving',
                      border: OutlineInputBorder(),
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
    brand.dispose();
    calories.dispose();
    fat.dispose();
    carbs.dispose();
    protein.dispose();
  }

  Future<void> _openConsumeFoodDialog() async {
    if (_foodItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a food item before logging consumption.'),
        ),
      );
      return;
    }

    FoodItem selected = _foodItems.first;
    final servings = TextEditingController(text: '1');
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          final preview = double.tryParse(servings.text.trim()) ?? 0;

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
            title: const Text('Consume Food'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<FoodItem>(
                    value: selected,
                    isExpanded: true,
                    itemHeight: null,
                    menuMaxHeight: 420,
                    decoration: const InputDecoration(
                      labelText: 'Food item',
                      border: OutlineInputBorder(),
                    ),
                    items: _foodItems
                        .map(
                          (food) => DropdownMenuItem(
                            value: food,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    food.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (food.brand.trim().isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      food.brand,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setLocal(() => selected = value);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: servings,
                    onChanged: (_) => setLocal(() {}),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Servings consumed',
                      hintText: 'Example: 1, 0.5, 1.5',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Per serving',
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

      buffer.writeln('DAILY TOTAL');
      buffer.writeln('Calories: ${_formatNumber(summary.calories)}');
      buffer.writeln('Protein: ${_formatNumber(summary.protein)}g');
      buffer.writeln('Carbs: ${_formatNumber(summary.carbs)}g');
      buffer.writeln('Fat: ${_formatNumber(summary.fat)}g');

      if (summaryIndex < ordered.length - 1) {
        buffer.writeln();
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
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _shareFoodLogs([summary]),
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  _macroHeaderCell('P'),
                  _macroHeaderCell('C'),
                  _macroHeaderCell('F'),
                ],
              ),
              const SizedBox(height: 10),
              ...summary.items.map(
                (item) => Dismissible(
                  key: ValueKey('consumed-${item.id}'),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => _confirmDeleteConsumedFood(item),
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    alignment: Alignment.centerRight,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            '${_foodDisplayName(item.food)} × '
                            '${_formatNumber(item.servings)}'
                            '  •  ${_formatNumber(item.calories)} cal',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _macroValueCell(item.protein),
                        _macroValueCell(item.carbs),
                        _macroValueCell(item.fat),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  Text('${_formatNumber(summary.calories)} calories'),
                  Text('${_formatNumber(summary.protein)}g protein'),
                  Text('${_formatNumber(summary.carbs)}g carbs'),
                  Text('${_formatNumber(summary.fat)}g fat'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
                        child: ElevatedButton.icon(
                          onPressed: _openConsumeFoodDialog,
                          icon: const Icon(Icons.restaurant),
                          label: const Text('Consume Food'),
                        ),
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
