class Gym {
  final int id;
  final String name;

  const Gym({required this.id, required this.name});

  // Convert a Gym into a Map. The keys must correspond to the names of the
  // columns in the database.
  Map<String, Object?> toMap() {
    return {'id': id, 'name': name};
  }

  // Implement toString to make it easier to see information about
  // each gym when using the print statement.
  @override
  String toString() {
    return 'Gym{id: $id, name: $name}';
  }
}