import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/equipment_service.dart';
import '../services/gym_service.dart';
import '../data/equipment_catalog.dart';
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
  final _gymService = GymService();

  List<Map<String, dynamic>> equipmentList = [];
  List<Map<String, dynamic>> gyms = [];
  List<Map<String, dynamic>> unassignedEquipment = [];
  Map<String, dynamic>? activeGym;
  final Set<String> _selectedEquipmentIds = <String>{};
  bool isLoading = true;
  bool _isChangingGym = false;

  String? get _activeGymId => activeGym?['id']?.toString();
  bool get _isSelectionMode => _selectedEquipmentIds.isNotEmpty;

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
    await _loadPageData();
  }

  @override
  void initState() {
    super.initState();
    _loadPageData();
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

  bool _isImportedRoutine(Map<String, dynamic> item) {
    if (_kindValue(item) != 'routine') return false;

    final sourceRoutineId = (item['source_routine_id'] ?? '').toString().trim();
    final sourceTrainerUserId = (item['source_trainer_user_id'] ?? '')
        .toString()
        .trim();

    return sourceRoutineId.isNotEmpty || sourceTrainerUserId.isNotEmpty;
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
    return _kindValue(item) == 'routine'
        ? Icons.view_list
        : Icons.fitness_center;
  }

  Future<void> _loadPageData() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final loadedGyms = await _gymService.getGyms();
      Map<String, dynamic>? loadedActiveGym = await _gymService.getActiveGym();

      if (loadedActiveGym == null && loadedGyms.isNotEmpty) {
        await _gymService.setActiveGym(loadedGyms.first['id'].toString());
        loadedActiveGym = loadedGyms.first;
      }

      final loadedUnassigned = await _equipmentService.getUnassignedEquipment();

      if (!mounted) return;
      setState(() {
        gyms = loadedGyms;
        activeGym = loadedActiveGym;
        unassignedEquipment = List<Map<String, dynamic>>.from(loadedUnassigned);
        _selectedEquipmentIds.clear();
      });

      await _loadEquipment();
    } catch (e, st) {
      debugPrint('Error loading gym/equipment data: $e');
      debugPrint('$st');

      if (!mounted) return;
      setState(() {
        gyms = [];
        activeGym = null;
        equipmentList = [];
        unassignedEquipment = [];
        equipmentWithSessionsToday = {};
        _equipmentMuscleGroups.clear();
        _selectedEquipmentIds.clear();
        isLoading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load equipment: $e')));
    }
  }

  Future<void> _loadEquipment() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final gymId = _activeGymId;

      final list = gymId == null
          ? await _equipmentService.getRoutines()
          : await _equipmentService.getEquipmentPageItems(gymId: gymId);

      final sorted = List<Map<String, dynamic>>.from(list)
        ..sort(
          (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
            (b['name'] ?? '').toString().toLowerCase(),
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load equipment: $e')));
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

  Future<void> _createGym({bool makeActive = true}) async {
    final controller = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create Gym'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Gym name',
            hintText: 'Example: Summit Athletic Club',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;

              try {
                await _gymService.createGym(name, makeActive: makeActive);

                if (!context.mounted) return;
                Navigator.pop(context, true);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to create gym: $e')),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (created == true && mounted) {
      await _loadPageData();
    }
  }

  Future<void> _changeActiveGym(String gymId) async {
    if (_isChangingGym || gymId == _activeGymId) return;

    setState(() => _isChangingGym = true);

    try {
      await _gymService.setActiveGym(gymId);
      final selected = gyms.firstWhere((gym) => gym['id']?.toString() == gymId);

      if (!mounted) return;
      setState(() {
        activeGym = selected;
        _selectedEquipmentIds.clear();
      });

      await _loadEquipment();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to switch gyms: $e')));
    } finally {
      if (mounted) {
        setState(() => _isChangingGym = false);
      }
    }
  }

  Future<void> _showGymMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_business),
              title: const Text('Create new gym'),
              onTap: () => Navigator.pop(context, 'create'),
            ),
            if (activeGym != null)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Rename active gym'),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
            if (unassignedEquipment.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(
                  'Assign unassigned equipment (${unassignedEquipment.length})',
                ),
                onTap: () => Navigator.pop(context, 'unassigned'),
              ),
          ],
        ),
      ),
    );

    switch (action) {
      case 'create':
        await _createGym();
        break;
      case 'rename':
        await _renameActiveGym();
        break;
      case 'unassigned':
        await _showUnassignedEquipment();
        break;
    }
  }

  Future<void> _renameActiveGym() async {
    final gym = activeGym;
    if (gym == null) return;

    final controller = TextEditingController(
      text: (gym['name'] ?? '').toString(),
    );

    final renamed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename Gym'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Gym name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;

              try {
                await _gymService.renameGym(
                  gymId: gym['id'].toString(),
                  name: name,
                );
                if (!context.mounted) return;
                Navigator.pop(context, true);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to rename gym: $e')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (renamed == true && mounted) {
      await _loadPageData();
    }
  }

  Future<void> _showUnassignedEquipment() async {
    if (unassignedEquipment.isEmpty) return;

    final selected = <String>{};

    final assigned = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final allSelected = selected.length == unassignedEquipment.length;

          return AlertDialog(
            title: const Text('Unassigned Equipment'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select equipment to add to ${activeGym?['name'] ?? 'the active gym'}.',
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allSelected,
                    title: const Text(
                      'Select all',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        selected.clear();
                        if (value == true) {
                          selected.addAll(
                            unassignedEquipment.map(
                              (item) => item['id'].toString(),
                            ),
                          );
                        }
                      });
                    },
                  ),
                  const Divider(),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: unassignedEquipment.length,
                      itemBuilder: (_, index) {
                        final item = unassignedEquipment[index];
                        final id = item['id'].toString();

                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: selected.contains(id),
                          title: Text((item['name'] ?? 'Equipment').toString()),
                          onChanged: (value) {
                            setDialogState(() {
                              if (value == true) {
                                selected.add(id);
                              } else {
                                selected.remove(id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selected.isEmpty || _activeGymId == null
                    ? null
                    : () async {
                        try {
                          await _equipmentService.bulkAssignEquipmentToGym(
                            equipmentIds: selected,
                            gymId: _activeGymId!,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to assign equipment: $e'),
                            ),
                          );
                        }
                      },
                child: const Text('Assign'),
              ),
            ],
          );
        },
      ),
    );

    if (assigned == true && mounted) {
      await _loadPageData();
    }
  }


  Future<void> _manageEquipmentGyms(
    Map<String, dynamic> equipment,
  ) async {
    if (_kindValue(equipment) == 'routine') return;

    final equipmentId = (equipment['id'] ?? '').toString().trim();
    final equipmentName = (equipment['name'] ?? 'Equipment').toString();
    if (equipmentId.isEmpty) return;

    if (gyms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a gym first.')),
      );
      return;
    }

    final currentGymIds = await _equipmentService.getGymIdsForEquipment(
      equipmentId,
    );
    final selectedGymIds = Set<String>.from(currentGymIds);
    var isSaving = false;

    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: !isSaving,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Gym availability'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Choose every gym where “$equipmentName” is available.',
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: gyms.length,
                      itemBuilder: (_, index) {
                        final gym = gyms[index];
                        final gymId = gym['id'].toString();

                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: selectedGymIds.contains(gymId),
                          title: Text((gym['name'] ?? 'Gym').toString()),
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    if (value == true) {
                                      selectedGymIds.add(gymId);
                                    } else {
                                      selectedGymIds.remove(gymId);
                                    }
                                  });
                                },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (selectedGymIds.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Equipment must be available at at least one gym.',
                              ),
                            ),
                          );
                          return;
                        }

                        setDialogState(() => isSaving = true);

                        try {
                          await _equipmentService.setGymsForEquipment(
                            equipmentId: equipmentId,
                            gymIds: selectedGymIds,
                          );

                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        } catch (e) {
                          if (!context.mounted) return;
                          setDialogState(() => isSaving = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Failed to update gym availability: $e',
                              ),
                            ),
                          );
                        }
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_business_outlined),
                label: Text(isSaving ? 'Saving...' : 'Save'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true && mounted) {
      await _loadPageData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated gym availability for $equipmentName.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _toggleEquipmentSelection(Map<String, dynamic> equipment) {
    if (_kindValue(equipment) == 'routine') return;

    final id = equipment['id']?.toString() ?? '';
    if (id.isEmpty) return;

    setState(() {
      if (_selectedEquipmentIds.contains(id)) {
        _selectedEquipmentIds.remove(id);
      } else {
        _selectedEquipmentIds.add(id);
      }
    });
  }

  Future<void> _addSelectedEquipmentToGym() async {
    if (_selectedEquipmentIds.isEmpty) return;

    if (gyms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a gym first.')),
      );
      return;
    }

    String selectedGymId =
        _activeGymId ?? gyms.first['id'].toString();

    final added = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              'Add ${_selectedEquipmentIds.length} item${_selectedEquipmentIds.length == 1 ? '' : 's'} to gym',
            ),
            content: DropdownButtonFormField<String>(
              initialValue: selectedGymId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Gym',
                border: OutlineInputBorder(),
              ),
              items: gyms
                  .map(
                    (gym) => DropdownMenuItem<String>(
                      value: gym['id'].toString(),
                      child: Text((gym['name'] ?? 'Gym').toString()),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setDialogState(() => selectedGymId = value);
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await _equipmentService.bulkAssignEquipmentToGym(
                      equipmentIds: Set<String>.from(
                        _selectedEquipmentIds,
                      ),
                      gymId: selectedGymId,
                    );

                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to add equipment to gym: $e'),
                      ),
                    );
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );

    if (added == true && mounted) {
      await _loadPageData();
    }
  }

  Widget _buildGymHeader() {
    if (gyms.isEmpty) {
      return Card(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.fitness_center, size: 36),
              const SizedBox(height: 8),
              Text(
                'Create your first gym',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Your equipment will be organized by gym so suggestions only use machines available at your active location.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _createGym,
                icon: const Icon(Icons.add),
                label: const Text('Create Gym'),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _activeGymId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Active Gym',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              items: gyms
                  .map(
                    (gym) => DropdownMenuItem<String>(
                      value: gym['id'].toString(),
                      child: Text((gym['name'] ?? 'Gym').toString()),
                    ),
                  )
                  .toList(),
              onChanged: _isChangingGym
                  ? null
                  : (value) {
                      if (value != null) {
                        _changeActiveGym(value);
                      }
                    },
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: _showGymMenu,
            tooltip: 'Manage gyms',
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar() {
    if (!_isSelectionMode) return const SizedBox.shrink();

    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${_selectedEquipmentIds.length} selected',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton.icon(
              onPressed: _addSelectedEquipmentToGym,
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Add to Gym'),
            ),
            IconButton(
              onPressed: () {
                setState(() => _selectedEquipmentIds.clear());
              },
              tooltip: 'Cancel selection',
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
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

    if (kind == 'equipment' && _activeGymId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create or select an active gym first.')),
      );
      return;
    }

    await _addNamedItem(kind: kind);
  }

  Future<void> _addNamedItem({required String kind}) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final kindTitle = kind == 'routine' ? 'Routine' : 'Equipment';
    var isSaving = false;

    Future<void> saveItem(
      BuildContext dialogContext,
      void Function(void Function()) setDialogState,
    ) async {
      final name = controller.text.trim();
      if (name.isEmpty || isSaving) return;

      if (kind == 'equipment') {
        final normalizedName = name.toLowerCase();
        final alreadyExists = equipmentList.any(
          (item) =>
              _kindValue(item) != 'routine' &&
              (item['name'] ?? '').toString().trim().toLowerCase() ==
                  normalizedName,
        );

        if (alreadyExists) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '“$name” is already in ${activeGym?['name'] ?? 'the active gym'}.',
              ),
            ),
          );
          return;
        }
      }

      setDialogState(() => isSaving = true);

      try {
        await _equipmentService.insertEquipment(
          name,
          kind: kind,
          gymId: kind == 'equipment' ? _activeGymId : null,
        );

        if (!dialogContext.mounted) return;
        Navigator.pop(dialogContext);

        await _loadPageData();
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $kindTitle: $name'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e) {
        if (!dialogContext.mounted) return;
        setDialogState(() => isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add $kindTitle: $e')),
        );
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: Text('Add New $kindTitle'),
            content: SizedBox(
              width: double.maxFinite,
              child: kind == 'routine'
                  ? TextField(
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Routine Name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      onSubmitted: (_) =>
                          saveItem(dialogContext, setDialogState),
                    )
                  : RawAutocomplete<String>(
                      textEditingController: controller,
                      focusNode: focusNode,
                      optionsBuilder: (TextEditingValue value) {
                        final query = value.text.trim().toLowerCase();

                        final matches = EquipmentCatalog.all.where((name) {
                          if (query.isEmpty) return true;
                          return name.toLowerCase().contains(query);
                        }).toList();

                        matches.sort((a, b) {
                          final aLower = a.toLowerCase();
                          final bLower = b.toLowerCase();
                          final aStarts = aLower.startsWith(query);
                          final bStarts = bLower.startsWith(query);

                          if (aStarts != bStarts) return aStarts ? -1 : 1;
                          return aLower.compareTo(bLower);
                        });

                        return matches.take(40);
                      },
                      displayStringForOption: (option) => option,
                      onSelected: (_) => setDialogState(() {}),
                      fieldViewBuilder: (
                        context,
                        textController,
                        fieldFocusNode,
                        onFieldSubmitted,
                      ) {
                        return TextField(
                          controller: textController,
                          focusNode: fieldFocusNode,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Equipment Name',
                            hintText: 'Start typing or enter a custom name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (_) => setDialogState(() {}),
                          onSubmitted: (_) =>
                              saveItem(dialogContext, setDialogState),
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        final optionList = options.toList();

                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 8,
                            borderRadius: BorderRadius.circular(8),
                            clipBehavior: Clip.antiAlias,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 300,
                                maxWidth: 520,
                              ),
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: optionList.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final option = optionList[index];
                                  return ListTile(
                                    dense: true,
                                    leading:
                                        const Icon(Icons.fitness_center_outlined),
                                    title: Text(option),
                                    onTap: () => onSelected(option),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed:
                    isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSaving || controller.text.trim().isEmpty
                    ? null
                    : () => saveItem(dialogContext, setDialogState),
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Add'),
              ),
            ],
          );
        },
      ),
    );

    controller.dispose();
    focusNode.dispose();
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

              await _loadPageData();
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

    final exerciseCount = await _equipmentService.getExerciseCountForEquipment(
      equipmentId,
    );

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
      await _loadPageData();
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
      await _loadPageData();
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
    final equipmentOptions =
        equipmentListDynamic
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
                (selectedEquipmentId != null &&
                    selectedEquipmentId!.isNotEmpty) ||
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
                            final created = await _equipmentService
                                .insertEquipment(typed, gymId: _activeGymId);
                            targetEquipmentId = created['id'].toString();
                            targetEquipmentName = created['name'].toString();
                          } else {
                            targetEquipmentId = selectedEquipmentId!;
                            targetEquipmentName = equipmentOptions
                                .firstWhere(
                                  (e) =>
                                      e['id'].toString() == selectedEquipmentId,
                                )['name']
                                .toString();
                          }

                          await _equipmentService.moveAllExercisesToEquipment(
                            fromEquipmentId: fromEquipmentId,
                            toEquipmentId: targetEquipmentId,
                          );

                          await _equipmentService.deleteEquipment(
                            fromEquipmentId,
                          );

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
    await _loadPageData();
  }

  Future<void> _assignRoutine(Map<String, dynamic> routine) async {
    final routineId = (routine['id'] ?? '').toString().trim();
    final routineName = (routine['name'] ?? 'Routine').toString().trim();

    if (routineId.isEmpty) return;

    // Imported trainer routines are personal copies. They cannot be
    // reassigned to anyone, including the trainer who originally shared them.
    if (_isImportedRoutine(routine)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Imported routines cannot be assigned to other users.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final results = await Future.wait<dynamic>([
        _equipmentService.getAcceptedFriends(),
        _equipmentService.getAssignedFriendIds(routineId),
      ]);

      final friends = List<Map<String, dynamic>>.from(results[0] as List);
      final originallyAssigned = Set<String>.from(results[1] as Set<String>);
      final selectedFriendIds = Set<String>.from(originallyAssigned);

      if (!mounted) return;

      if (friends.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You do not have any accepted friends to assign this routine to.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      var isSaving = false;

      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: !isSaving,
        builder: (_) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final allFriendIds = friends
                  .map(
                    (friend) => (friend['friend_id'] ?? '').toString().trim(),
                  )
                  .where((id) => id.isNotEmpty)
                  .toSet();

              final allSelected =
                  allFriendIds.isNotEmpty &&
                  allFriendIds.every(selectedFriendIds.contains);

              return AlertDialog(
                title: Text('Assign “$routineName”'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Choose which friends can view and import this routine.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: allSelected,
                        tristate: selectedFriendIds.isNotEmpty && !allSelected,
                        title: const Text(
                          'Select all friends',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onChanged: isSaving
                            ? null
                            : (value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selectedFriendIds
                                      ..clear()
                                      ..addAll(allFriendIds);
                                  } else {
                                    selectedFriendIds.clear();
                                  }
                                });
                              },
                      ),
                      const Divider(),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: friends.length,
                          itemBuilder: (context, index) {
                            final friend = friends[index];
                            final friendId = (friend['friend_id'] ?? '')
                                .toString()
                                .trim();
                            final username = (friend['username'] ?? 'Friend')
                                .toString()
                                .trim();
                            final selected = selectedFriendIds.contains(
                              friendId,
                            );

                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: selected,
                              title: Text(
                                username.isEmpty ? 'Friend' : '@$username',
                              ),
                              onChanged: isSaving || friendId.isEmpty
                                  ? null
                                  : (value) {
                                      setDialogState(() {
                                        if (value == true) {
                                          selectedFriendIds.add(friendId);
                                        } else {
                                          selectedFriendIds.remove(friendId);
                                        }
                                      });
                                    },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton.icon(
                    onPressed: isSaving
                        ? null
                        : () async {
                            setDialogState(() => isSaving = true);

                            try {
                              await _equipmentService.replaceRoutineAssignments(
                                routineId: routineId,
                                friendUserIds: selectedFriendIds,
                              );

                              if (!context.mounted) return;
                              Navigator.pop(context, true);
                            } catch (e) {
                              if (!context.mounted) return;
                              setDialogState(() => isSaving = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Failed to save assignments: $e',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                    icon: isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add_alt_1),
                    label: Text(isSaving ? 'Saving...' : 'Save'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (saved != true || !mounted) return;

      final assignedCount = selectedFriendIds.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            assignedCount == 0
                ? 'Routine is no longer assigned to any friends.'
                : 'Assigned “$routineName” to $assignedCount friend${assignedCount == 1 ? '' : 's'}.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load routine assignments: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onMenuSelected(
    String value,
    Map<String, dynamic> equipment,
  ) async {
    switch (value) {
      case 'edit':
        await _editEquipmentName(equipment);
        break;
      case 'assign':
        await _assignRoutine(equipment);
        break;
      case 'manage_gyms':
        await _manageEquipmentGyms(equipment);
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
                  _buildGymHeader(),
                  _buildSelectionBar(),
                  _buildKindFilterBar(), // ✅ NEW
                  _buildMuscleFilterBar(),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadEquipment,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _filteredEquipment.isEmpty
                            ? 1
                            : _filteredEquipment.length,
                        itemBuilder: (context, index) {
                          if (_filteredEquipment.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(
                                child: Text(
                                  gyms.isEmpty
                                      ? 'Create a gym to begin organizing equipment.'
                                      : 'No equipment or routines match these filters.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }
                          final equipment = _filteredEquipment[index];
                          final equipmentId = equipment['id']?.toString() ?? '';
                          final hasSessionToday = equipmentWithSessionsToday
                              .contains(equipmentId);
                          final isSelected = _selectedEquipmentIds.contains(
                            equipmentId,
                          );

                          final kindLabel = _kindLabel(equipment);
                          final kindValue = _kindValue(equipment);

                          return ListTile(
                            selected: isSelected,
                            selectedTileColor: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            leading: _isSelectionMode && kindValue != 'routine'
                                ? Checkbox(
                                    value: isSelected,
                                    onChanged: (_) =>
                                        _toggleEquipmentSelection(equipment),
                                  )
                                : Icon(
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
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    )
                                  : null,
                            ),
                            subtitle: Text(
                              _isImportedRoutine(equipment)
                                  ? 'Imported Routine • QR: ${equipment['qr_code'] ?? 'N/A'}'
                                  : '$kindLabel • QR: ${equipment['qr_code'] ?? 'N/A'}',
                            ),
                            trailing: _isSelectionMode
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                              children: [
                                if (kindValue != 'routine')
                                  IconButton(
                                    tooltip: 'Manage gym availability',
                                    icon: const Icon(
                                      Icons.add_business_outlined,
                                    ),
                                    onPressed: () =>
                                        _manageEquipmentGyms(equipment),
                                  ),
                                Icon(
                                  hasSessionToday
                                      ? Icons.check_circle
                                      : Icons.chevron_right,
                                ),
                                const SizedBox(width: 8),
                                PopupMenuButton<String>(
                                  onSelected: (value) =>
                                      _onMenuSelected(value, equipment),
                                  itemBuilder: (context) {
                                    final isRoutine = kindValue == 'routine';
                                    final isImportedRoutine =
                                        _isImportedRoutine(equipment);
                                    final canAssignRoutine =
                                        isRoutine && !isImportedRoutine;

                                    return [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit name'),
                                      ),
                                      if (canAssignRoutine)
                                        const PopupMenuItem(
                                          value: 'assign',
                                          child: Text('Assign routine'),
                                        ),
                                      if (!isRoutine)
                                        const PopupMenuItem(
                                          value: 'manage_gyms',
                                          child: Text('Manage gym availability'),
                                        ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete'),
                                      ),
                                    ];
                                  },
                                ),
                              ],
                            ),
                            onLongPress: kindValue == 'routine'
                                ? null
                                : () => _toggleEquipmentSelection(equipment),
                            onTap: () async {
                              if (_isSelectionMode &&
                                  kindValue != 'routine') {
                                _toggleEquipmentSelection(equipment);
                                return;
                              }

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

                              await _loadPageData();
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
