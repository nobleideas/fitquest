class NutritionLabelScanResult {
  final double? calories;
  final double? fat;
  final double? carbs;
  final double? protein;
  final double? servingAmount;
  final String? servingUnit;
  final bool cancelled;

  const NutritionLabelScanResult({
    this.calories,
    this.fat,
    this.carbs,
    this.protein,
    this.servingAmount,
    this.servingUnit,
    this.cancelled = false,
  });
}

bool get nutritionLabelScannerSupported => false;

Future<NutritionLabelScanResult?> scanNutritionFactsLabel() async => null;
