import 'dart:convert';
import 'dart:js_interop';

@JS('fitQuestScanNutritionLabel')
external JSPromise<JSString> _fitQuestScanNutritionLabel();

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

  factory NutritionLabelScanResult.fromJson(Map<String, dynamic> json) {
    double? number(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    return NutritionLabelScanResult(
      calories: number(json['calories']),
      fat: number(json['fat']),
      carbs: number(json['carbs']),
      protein: number(json['protein']),
      servingAmount: number(json['servingAmount']),
      servingUnit: json['servingUnit']?.toString(),
      cancelled: json['cancelled'] == true,
    );
  }
}

bool get nutritionLabelScannerSupported => true;

Future<NutritionLabelScanResult?> scanNutritionFactsLabel() async {
  final jsonText = (await _fitQuestScanNutritionLabel().toDart).toDart;
  if (jsonText.trim().isEmpty) return null;

  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) return null;

  return NutritionLabelScanResult.fromJson(
    Map<String, dynamic>.from(decoded),
  );
}
