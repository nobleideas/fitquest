class Exercise {
  final int id;
  final int equipmentId;
  final String name;
  final String motion;
  final String muscle;

  const Exercise({required this.id, required this.equipmentId, required this.name, required this.motion, required this.muscle});

  // Convert an Exercise into a Map. The keys must correspond to the names of the
  // columns in the database.
  Map<String, Object?> toMap() {
    return {'id': id, 'equipmentId': name, 'name': name, 'motion': motion, 'muscle': muscle};
  }

  // Implement toString to make it easier to see information about
  // each exercise when using the print statement.
  @override
  String toString() {
    return 'Exercise{id: $id, equipmentId: $equipmentId, name: $name, motion: $motion, muscle: $muscle}';
  }
}