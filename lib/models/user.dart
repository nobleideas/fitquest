class User {
  final int id;
  final String name;
  final String email;

  const User({required this.id, required this.name, required this.email});

  // Convert a User into a Map. The keys must correspond to the names of the
  // columns in the database.
  Map<String, Object?> toMap() {
    return {'id': id, 'name': name, 'email': email};
  }

  // Implement toString to make it easier to see information about
  // each user when using the print statement.
  @override
  String toString() {
    return 'User{id: $id, name: $name, email: $email}';
  }

}