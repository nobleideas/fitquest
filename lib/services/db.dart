import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/gym.dart';
import '../models/user.dart';
import '../models/equipment.dart';
import '../models/exercise.dart';
import '../models/session.dart';

class DBHelper {
  static Database? _database;

  // Get or initialize the database
  static Future<Database> getDatabase() async {
    if (_database != null) return _database!;

    WidgetsFlutterBinding.ensureInitialized();
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'gym.db');

    _database = await openDatabase(
      path,
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE equipment(id INTEGER PRIMARY KEY, name TEXT)',
        );
      },
      version: 1,
    );
    return _database!;
  }

  static Future<void> insertExercise(Exercise exercise) async {
    final db = await getDatabase();
    await db.insert('exercises', exercise.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> insertEquipment(Equipment equipment) async {
    final db = await getDatabase();
    await db.insert('equipment', equipment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> insertUser(User user) async {
    final db = await getDatabase();
    await db.insert('users', user.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> insertGym(Gym gym) async {
    final db = await getDatabase();
    await db.insert('gyms', gym.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> insertSession(Session session) async {
    final db = await getDatabase();
    await db.insert('sessions', session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getWorkouts() async {
    final db = await getDatabase();
    return db.query('workouts');
  }
}
