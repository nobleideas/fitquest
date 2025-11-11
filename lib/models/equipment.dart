class Equipment {
  final int id;
  final String name;

  const Equipment({required this.id, required this.name});

  // Convert an Equipment into a Map. The keys must correspond to the names of the
  // columns in the database.
  Map<String, Object?> toMap() {
    return {'id': id, 'name': name};
  }

  // Implement toString to make it easier to see information about
  // each equipment when using the print statement.
  @override
  String toString() {
    return 'Equipment{id: $id, name: $name}';
  }

}