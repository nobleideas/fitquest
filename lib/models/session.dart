class Session {
  final int id;
  final int userId;
  final DateTime date;
  final int weight;
  final int reps;

  const Session({required this.id, required this.userId, required this.date, required this.weight, required this.reps});

  // Convert a Session into a Map. The keys must correspond to the names of the
  // columns in the database.
  Map<String, Object?> toMap() {
    return {'id': id, 'userId': userId, 'date': date, 'weight': weight, 'reps': reps};
  }

  // Implement toString to make it easier to see information about
  // each session when using the print statement.
  @override
  String toString() {
    return 'Session{id: $id, userId: $userId, date: $date, weight: $weight, reps: $reps}';
  }
}