import 'dart:math' as math;

class XPUtils {
  // Rank thresholds
  static const List<Map<String, dynamic>> ranks = [
    {'name': 'Bronze', 'xp': 0},
    {'name': 'Silver', 'xp': 2000},
    {'name': 'Gold', 'xp': 10000},
    {'name': 'Platinum', 'xp': 25000},
    {'name': 'Diamond', 'xp': 50000},
    {'name': 'Master', 'xp': 100000},
    {'name': 'Grandmaster', 'xp': 200000},
    {'name': 'Legend', 'xp': 400000},
  ];

  /// Calculate total XP from profile row
  static int totalXP(Map<String, dynamic> profile) {
    return (profile['xp_back'] ?? 0) +
        (profile['xp_chest'] ?? 0) +
        (profile['xp_shoulders'] ?? 0) +
        (profile['xp_arms'] ?? 0) +
        (profile['xp_legs'] ?? 0) +
        (profile['xp_core'] ?? 0);
  }

  /// Compute RPG Level using: XP(N) = 500 * N^2
  static int computeLevel(int xp) {
    return (xp / 500).sqrt().floor();
  }

  /// XP required for a given level
  static int xpForLevel(int level) {
    return 500 * level * level;
  }

  /// Progress toward next level (0.0 → 1.0)
  static double levelProgress(int xp) {
    final level = computeLevel(xp);
    final currentXP = xpForLevel(level);
    final nextXP = xpForLevel(level + 1);
    return (xp - currentXP) / (nextXP - currentXP);
  }

  /// Determine rank name based on XP thresholds
  static String computeRank(int xp) {
    for (int i = ranks.length - 1; i >= 0; i--) {
      if (xp >= ranks[i]['xp']) {
        return ranks[i]['name'];
      }
    }
    return "Bronze";
  }
}

extension NumSqrt on num {
  double sqrt() => math.sqrt(this);
}
