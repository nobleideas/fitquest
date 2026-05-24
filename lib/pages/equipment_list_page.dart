import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/equipment_service.dart';
import 'exercise_list_page.dart';

class EquipmentListPage extends StatefulWidget {
  const EquipmentListPage({super.key});

  @override
  State<EquipmentListPage> createState() => EquipmentListPageState();
}

// ✅ PUBLIC so MainShell can use GlobalKey<EquipmentListPageState>
class EquipmentListPageState extends State<EquipmentListPage> {
  final supabase = Supabase.instance.client;
  final _equipmentService = EquipmentService();

  List<Map<String, dynamic>> equipmentList = [];
  bool isLoading = true;

  /// Equipment IDs that have at least one exercise session today
  Set<String> equipmentWithSessionsToday = {};

  static const List<String?> _muscleFiltersGrid = [
    'All',
    'Chest',
    'Shoulders',
    'Back',
    'Arms',
    'Legs',
    null,
    'Core',
    null,
  ];

  String _selectedMuscle = 'All';

  // ✅ NEW: kind filter (all / equipment / routine)
  static const List<String> _kindFilters = ['All', 'Equipment', 'Routines'];
  String _selectedKind = 'All';

  /// Map equipmentId -> set of muscle group keys (lowercase normalized)
  final Map<String, Set<String>> _equipmentMuscleGroups = {};

  Future<void> refresh() async {
    await _loadEquipment();
  }

  @override
  void initState() {
    super.initState();
    _loadEquipment();
  }

  String _normalizeMuscle(dynamic value) {
    final v = (value ?? '').toString().trim().toLowerCase();
    switch (v) {
      case 'shoulder':
      case 'shoulders':
        return 'shoulders';
      case 'arm':
      case 'arms':
        return 'arms';
      case 'leg':
      case 'legs':
        return 'legs';
      case 'chest':
        return 'chest';
      case 'back':
        return 'back';
      case 'core':
      case 'abs':
      case 'abdominals':
        return 'core';
      default:
        return v;
    }
  }

  String _selectedMuscleKey() => _normalizeMuscle(_selectedMuscle);

  String _kindValue(Map<String, dynamic> item) {
    return (item['kind'] ?? 'equipment').toString().toLowerCase().trim();
  }

  bool _matchesKindFilter(Map<String, dynamic> item) {
    if (_selectedKind == 'All') return true;

    final k = _kindValue(item);
    if (_selectedKind == 'Equipment') return k != 'routine';
    if (_selectedKind == 'Routines') return k == 'routine';
    return true;
  }

  List<Map<String, dynamic>> get _filteredEquipment {
    // First filter by kind (All/Equipment/Routines)
    final byKind = equipmentList.where(_matchesKindFilter).toList();

    // Then filter by muscle group (only meaningful if exercises exist; routines with no exercises will drop out)
    if (_selectedMuscle == 'All') return byKind;

    final key = _selectedMuscleKey();
    return byKind.where((e) {
      final id = e['id']?.toString() ?? '';
      final groups = _equipmentMuscleGroups[id];
      return groups != null && groups.contains(key);
    }).toList();
  }

  String _kindLabel(Map<String, dynamic> item) {
    return _kindValue(item) == 'routine' ? 'Routine' : 'Equipment';
  }

  IconData _kindIcon(Map<String, dynamic> item) {
    return _kindValue(item) == 'routine' ? Icons.view_list : Icons.fitness_center;
  }

  Future<void> _loadEquipment() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final list = await _equipmentService.getAllEquipment();

      final sorted = List<Map<String, dynamic>>.from(list)
        ..sort(
          (a, b) => (a['name'] as String).toLowerCase().compareTo(
                (b['name'] as String).toLowerCase(),
              ),
        );

      final todaySet = await _loadEquipmentIdsWithSessionsToday();

      final usedToday = <Map<String, dynamic>>[];
      final notUsedToday = <Map<String, dynamic>>[];

      for (final e in sorted) {
        final id = e['id']?.toString() ?? '';
        if (todaySet.contains(id)) {
          usedToday.add(e);
        } else {
          notUsedToday.add(e);
        }
      }

      final ordered = [...usedToday, ...notUsedToday];

      final ids = ordered
          .map((e) => e['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      final muscleMap = await _loadEquipmentMuscleGroups(ids);

      if (!mounted) return;
      setState(() {
        equipmentList = ordered;
        equipmentWithSessionsToday = todaySet;
        _equipmentMuscleGroups
          ..clear()
          ..addAll(muscleMap);
        isLoading = false;
      });
    } catch (e, st) {
      debugPrint('Error loading equipment: $e');
      debugPrint('$st');

      if (!mounted) return;
      setState(() {
        equipmentList = [];
        equipmentWithSessionsToday = {};
        _equipmentMuscleGroups.clear();
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load equipment: $e')),
      );
    }
  }

  Future<Map<String, Set<String>>> _loadEquipmentMuscleGroups(
    List<String> equipmentIds,
  ) async {
    if (equipmentIds.isEmpty) return {};

    final rowsRaw = await supabase
        .from('exercises')
        .select('equipment_id, primary_muscle_group')
        .inFilter('equipment_id', equipmentIds);

    final rows = rowsRaw.whereType<Map<String, dynamic>>().toList();
    final map = <String, Set<String>>{};

    for (final row in rows) {
      final eqId = row['equipment_id']?.toString();
      if (eqId == null || eqId.isEmpty) continue;

      final muscle = _normalizeMuscle(row['primary_muscle_group']);
      if (muscle.isEmpty) continue;

      map.putIfAbsent(eqId, () => <String>{}).add(muscle);
    }

    return map;
  }

  Future<Set<String>> _loadEquipmentIdsWithSessionsToday() async {
    final user = supabase.auth.currentUser;
    if (user == null) return {};

    final nowLocal = DateTime.now();
    final startLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final endLocal = startLocal.add(const Duration(days: 1));

    final startUtc = startLocal.toUtc().toIso8601String();
    final endUtc = endLocal.toUtc().toIso8601String();

    final rows = await supabase
        .from('exercise_sessions')
        .select('created_at, exercises!inner(equipment_id)')
        .eq('user_id', user.id)
        .gte('created_at', startUtc)
        .lt('created_at', endUtc);

    final ids = <String>{};

    for (final row in rows) {
      final exJoined = row['exercises'];

      if (exJoined is Map<String, dynamic>) {
        final eqId = exJoined['equipment_id'];
        if (eqId != null) ids.add(eqId.toString());
      } else if (exJoined is List) {
        for (final item in exJoined) {
          if (item is Map) {
            final eqId = item['equipment_id'];
            if (eqId != null) ids.add(eqId.toString());
          }
        }
      }
    }

    return ids;
  }

  Future<void> _addEquipmentOrRoutine() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.fitness_center),
                title: const Text('Add Equipment'),
                onTap: () => Navigator.pop(context, 'equipment'),
              ),
              ListTile(
                leading: const Icon(Icons.view_list),
                title: const Text('Create Routine'),
                onTap: () => Navigator.pop(context, 'routine'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (kind == null) return;
    await _addNamedItem(kind: kind);
  }

  Future<void> _addNamedItem({required String kind}) async {
    final controller = TextEditingController();
    final kindTitle = kind == 'routine' ? 'Routine' : 'Equipment';

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Add New $kindTitle'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: '$kindTitle Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;

              await _equipmentService.insertEquipment(name, kind: kind);

              if (!mounted) return;
              Navigator.pop(context);

              await _loadEquipment();
              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added $kindTitle: $name'),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  Future<void> _editEquipmentName(Map<String, dynamic> equipment) async {
    final equipmentId = equipment['id']?.toString() ?? '';
    final currentName = (equipment['name'] ?? '').toString();
    final controller = TextEditingController(text: currentName);

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Name"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: "Name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;

              await _equipmentService.updateEquipmentName(
                equipmentId: equipmentId,
                name: newName,
              );

              if (!mounted) return;
              Navigator.pop(context);

              await _loadEquipment();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Renamed to: $newName'),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEquipmentFlow(Map<String, dynamic> equipment) async {
    final equipmentId = equipment['id']?.toString() ?? '';
    final equipmentName = (equipment['name'] ?? 'this item').toString();

    final exerciseCount =
        await _equipmentService.getExerciseCountForEquipment(equipmentId);

    if (exerciseCount == 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Delete?"),
          content: Text('Are you sure you want to delete “$equipmentName”?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text("Delete"),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      await _equipmentService.deleteEquipment(equipmentId);

      if (!mounted) return;
      await _loadEquipment();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted: $equipmentName'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Exercises Attached"),
        content: Text(
          '“$equipmentName” has $exerciseCount exercise${exerciseCount == 1 ? '' : 's'} attached.\n\n'
          'You can move those exercise${exerciseCount == 1 ? '' : 's'} to another equipment/routine, or delete everything anyway.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete_anyway'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text("Delete anyway"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'move'),
            child: const Text("Move exercises…"),
          ),
        ],
      ),
    );

    if (action == null || action == 'cancel') return;

    if (action == 'move') {
      await _moveAllExercisesThenDeleteEquipment(
        fromEquipmentId: equipmentId,
        fromEquipmentName: equipmentName,
        exerciseCount: exerciseCount,
      );
      return;
    }

    if (action == 'delete_anyway') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Delete Everything?"),
          content: Text(
            'This will delete:\n'
            '• $exerciseCount exercise${exerciseCount == 1 ? '' : 's'}\n'
            '• All recorded sessions for those exercise${exerciseCount == 1 ? '' : 's'}\n\n'
            'This cannot be undone. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text("Delete"),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      await _equipmentService.deleteEquipmentCascade(equipmentId);

      if (!mounted) return;
      await _loadEquipment();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted “$equipmentName” and its exercises/sessions.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _moveAllExercisesThenDeleteEquipment({
    required String fromEquipmentId,
    required String fromEquipmentName,
    required int exerciseCount,
  }) async {
    final equipmentListDynamic = await _equipmentService.getAllEquipment();
    final equipmentOptions = equipmentListDynamic
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) => e['id'].toString() != fromEquipmentId)
        .toList()
      ..sort(
        (a, b) => (a['name'] as String).toLowerCase().compareTo(
              (b['name'] as String).toLowerCase(),
            ),
      );

    String? selectedEquipmentId;
    String? targetEquipmentName;
    final newEquipmentController = TextEditingController();

    final moved = await showDialog<bool>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final typedName = newEquipmentController.text.trim();

            final canMove =
                (selectedEquipmentId != null && selectedEquipmentId!.isNotEmpty) ||
                    typedName.isNotEmpty;

            return AlertDialog(
              title: Text(
                'Move $exerciseCount exercise${exerciseCount == 1 ? '' : 's'}',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Move to existing equipment/routine:'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedEquipmentId,
                    isExpanded: true,
                    items: [
                      for (final e in equipmentOptions)
                        DropdownMenuItem(
                          value: e['id'].toString(),
                          child: Text(e['name'].toString()),
                        ),
                    ],
                    onChanged: newEquipmentController.text.isNotEmpty
                        ? null
                        : (val) {
                            setDialogState(() {
                              selectedEquipmentId = val;
                              if (val != null) newEquipmentController.text = '';
                            });
                          },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Select equipment/routine',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Or create a new equipment/routine:'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: newEquipmentController,
                    enabled: selectedEquipmentId == null,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'New equipment/routine name',
                    ),
                    onChanged: (_) {
                      setDialogState(() {
                        if (newEquipmentController.text.isNotEmpty) {
                          selectedEquipmentId = null;
                        }
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: canMove
                      ? () async {
                          String targetEquipmentId;
                          final typed = newEquipmentController.text.trim();

                          if (typed.isNotEmpty) {
                            final created =
                                await _equipmentService.insertEquipment(typed);
                            targetEquipmentId = created['id'].toString();
                            targetEquipmentName = created['name'].toString();
                          } else {
                            targetEquipmentId = selectedEquipmentId!;
                            targetEquipmentName = equipmentOptions
                                .firstWhere((e) =>
                                    e['id'].toString() == selectedEquipmentId)['name']
                                .toString();
                          }

                          await _equipmentService.moveAllExercisesToEquipment(
                            fromEquipmentId: fromEquipmentId,
                            toEquipmentId: targetEquipmentId,
                          );

                          await _equipmentService.deleteEquipment(fromEquipmentId);

                          if (!mounted) return;
                          Navigator.pop(context, true);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Moved $exerciseCount exercise${exerciseCount == 1 ? '' : 's'} to $targetEquipmentName, then deleted “$fromEquipmentName”.',
                              ),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      : null,
                  child: const Text('Move & Delete'),
                ),
              ],
            );
          },
        );
      },
    );

    if (moved != true) return;
    if (!mounted) return;
    await _loadEquipment();
  }

  Future<void> _onMenuSelected(String value, Map<String, dynamic> equipment) async {
    switch (value) {
      case 'edit':
        await _editEquipmentName(equipment);
        break;
      case 'delete':
        await _deleteEquipmentFlow(equipment);
        break;
    }
  }

  // ✅ NEW: kind filter bar (All / Equipment / Routines)
  Widget _buildKindFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Wrap(
        spacing: 8,
        children: _kindFilters.map((label) {
          final selected = _selectedKind == label;
          return ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) {
              setState(() {
                _selectedKind = label;
              });
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMuscleFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const cols = 3;
          const gap = 8.0;

          final totalGap = gap * (cols - 1);
          final cellWidth = (constraints.maxWidth - totalGap) / cols;

          const cellHeight = 36.0;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: _muscleFiltersGrid.map((label) {
              if (label == null) {
                return SizedBox(width: cellWidth, height: cellHeight);
              }

              final selected = _selectedMuscle == label;

              return SizedBox(
                width: cellWidth,
                height: cellHeight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ChoiceChip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                    label: SizedBox(
                      width: cellWidth,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedMuscle = label),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildKindFilterBar(), // ✅ NEW
                  _buildMuscleFilterBar(),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadEquipment,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _filteredEquipment.length,
                        itemBuilder: (context, index) {
                          final equipment = _filteredEquipment[index];
                          final equipmentId = equipment['id']?.toString() ?? '';
                          final hasSessionToday =
                              equipmentWithSessionsToday.contains(equipmentId);

                          final kindLabel = _kindLabel(equipment);
                          final kindValue = _kindValue(equipment);

                          return ListTile(
                            leading: Icon(
                              _kindIcon(equipment),
                              color: hasSessionToday
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            title: Text(
                              equipment['name'],
                              style: hasSessionToday
                                  ? TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.primary,
                                    )
                                  : null,
                            ),
                            subtitle: Text(
                              '$kindLabel • QR: ${equipment['qr_code'] ?? 'N/A'}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  hasSessionToday
                                      ? Icons.check_circle
                                      : Icons.chevron_right,
                                ),
                                const SizedBox(width: 8),
                                PopupMenuButton<String>(
                                  onSelected: (value) =>
                                      _onMenuSelected(value, equipment),
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit name'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ExerciseListPage(
                                    equipmentId: equipment['id'],
                                    equipmentName: equipment['name'],
                                    equipmentKind: kindValue,
                                  ),
                                ),
                              );

                              await _loadEquipment();
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: _addEquipmentOrRoutine,
            tooltip: 'Add Equipment or Routine',
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}