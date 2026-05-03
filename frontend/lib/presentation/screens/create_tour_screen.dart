import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import 'package:intl/intl.dart';
import '../../data/local/app_database.dart';
import 'package:frontend/data/providers/app_providers.dart';
import '../../domain/logic/purpose_config.dart';

class CreateTourScreen extends ConsumerStatefulWidget {
  final Tour? initialTour;
  const CreateTourScreen({super.key, this.initialTour});

  @override
  ConsumerState<CreateTourScreen> createState() => _CreateTourScreenState();
}

class _CreateTourScreenState extends ConsumerState<CreateTourScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _memberController = TextEditingController();
  final _searchController = TextEditingController();

  DateTimeRange? _selectedDateRange;
  final List<String> _additionalMembers = [];
  final List<Map<String, dynamic>> _selectedProfiles = [];
  bool _isLoading = false;
  bool _isSearching = false;
  String _selectedPurpose = 'project';
  bool _isLocalOnly = false;
  bool _isManagerLed = false;
  String? _selectedManagerId;
  List<dynamic> _searchResults = [];
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialTour != null) {
      _nameController.text = widget.initialTour!.name;
      _selectedPurpose = widget.initialTour!.purpose;
      if (widget.initialTour!.startDate != null &&
          widget.initialTour!.endDate != null) {
        _selectedDateRange = DateTimeRange(
          start: widget.initialTour!.startDate!,
          end: widget.initialTour!.endDate!,
        );
      }
      _isManagerLed = widget.initialTour!.isManagerLed;
      _selectedManagerId = widget.initialTour!.managerId;
      Future.microtask(_loadStorageScope);
    }
  }

  Future<void> _loadStorageScope() async {
    if (widget.initialTour == null) return;
    final db = ref.read(databaseProvider);
    final isLocalOnly = await db.isTourLocalOnly(widget.initialTour!.id);
    if (!mounted) return;
    setState(() => _isLocalOnly = isLocalOnly);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameController.dispose();
    _memberController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results =
          await ref.read(syncServiceProvider).searchUsers(normalized);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _scheduleUserSearch(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _searchUsers(query);
    });
  }

  void _toggleProfileSelection(Map<String, dynamic> profile) {
    final id = profile['id']?.toString();
    if (id == null) return;

    setState(() {
      final index = _selectedProfiles.indexWhere((p) => p['id'] == id);
      if (index >= 0) {
        _selectedProfiles.removeAt(index);
      } else {
        _selectedProfiles.add(profile);
      }
    });
  }

  Future<void> _selectDateRange() async {
    final DateTime now = DateTime.now();
    final DateTime firstDate = now.subtract(const Duration(days: 365));
    final DateTime lastDate = now.add(const Duration(days: 365 * 2));

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedDateRange,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: PurposeConfig.getConfig(_selectedPurpose).color,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDateRange = picked);
    }
  }

  void _addMember() {
    final name = _memberController.text.trim();
    if (name.isEmpty) return;
    
    // Split by comma for bulk add
    final names = name.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
    setState(() {
      _additionalMembers.addAll(names);
      _memberController.clear();
    });
  }

  Future<void> _inviteSelectedProfiles(String tourId) async {
    final syncService = ref.read(syncServiceProvider);
    for (final profile in _selectedProfiles) {
      try {
        final profileId = profile['id']?.toString();
        if (profileId != null) {
          await syncService.inviteMember(tourId, profileId);
        }
      } catch (e) {
        debugPrint('Failed to invite : ');
      }
    }
  }

  void _handleCreatePressed() {
    if (_formKey.currentState?.validate() ?? false) {
      _createTour();
    }
  }

  Future<void> _createTour() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      User? currentUser = await ref.read(currentUserProvider.future);
      if (currentUser == null) throw Exception(\"Profile not found.\");

      final String finalTourId;
      if (widget.initialTour == null) {
        finalTourId = const Uuid().v4();
        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        final inviteCode = List.generate(6, (index) => chars[Random().nextInt(chars.length)]).join();

        await db.createTour(Tour(
            id: finalTourId,
            name: _nameController.text.trim(),
            startDate: _selectedDateRange?.start,
            endDate: _selectedDateRange?.end,
            inviteCode: inviteCode,
            createdBy: currentUser.id,
            purpose: _selectedPurpose,
            isManagerLed: _isManagerLed,
            managerId: _isManagerLed ? (_selectedManagerId ?? currentUser.id) : null,
            isSynced: false,
            isDeleted: false));

        await db.setTourLocalOnly(finalTourId, _isLocalOnly);
        await db.into(db.tourMembers).insert(TourMember(
            tourId: finalTourId,
            userId: currentUser.id,
            status: 'active',
            role: 'admin',
            mealCount: 0.0,
            isSynced: false,
            isDeleted: false));

        if (_isLocalOnly) {
          for (final memberName in _additionalMembers) {
            final memberId = const Uuid().v4();
            await db.createUser(User(
              id: memberId,
              name: memberName,
              phone: null,
              isMe: false,
              isSynced: false,
              isDeleted: false,
              createdAt: DateTime.now(),
            ));
            await db.into(db.tourMembers).insert(TourMember(
                  tourId: finalTourId,
                  userId: memberId,
                  status: 'active',
                  role: 'viewer',
                  mealCount: 0.0,
                  isSynced: false,
                  isDeleted: false,
                ));
          }
        }
      } else {
        finalTourId = widget.initialTour!.id;
        await db.createTour(widget.initialTour!.copyWith(
          name: _nameController.text.trim(),
          purpose: _selectedPurpose,
          isManagerLed: _isManagerLed,
          managerId: drift.Value(_isManagerLed ? (_selectedManagerId ?? currentUser.id) : null),
          startDate: drift.Value(_selectedDateRange?.start),
          endDate: drift.Value(_selectedDateRange?.end),
          isSynced: false,
          isDeleted: false,
        ));
        await db.setTourLocalOnly(finalTourId, _isLocalOnly);
      }

      if (!_isLocalOnly) {
        try {
          await ref.read(syncServiceProvider).startSync(currentUser.id);
          if (_selectedProfiles.isNotEmpty) {
            await _inviteSelectedProfiles(finalTourId);
          }
        } catch (e) {
          debugPrint('Sync failed: ');
        }
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(\"Error: \")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = PurposeConfig.getConfig(_selectedPurpose);
    final timelineText = _selectedDateRange == null
        ? 'Set date range (optional)'
        : ' - ';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialTour == null ? 'Create ' : 'Edit '),
        backgroundColor: config.color,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedPurpose,
                        decoration: InputDecoration(labelText: 'Category', icon: Icon(config.icon, color: config.color)),
                        items: ['project', 'tour', 'event', 'party', 'mess'].map((p) {
                          final pConfig = PurposeConfig.getConfig(p);
                          return DropdownMenuItem(value: p, child: Text(pConfig.label));
                        }).toList(),
                        onChanged: (value) => setState(() => _selectedPurpose = value!),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Title', icon: Icon(Icons.title)),
                        validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        leading: const Icon(Icons.calendar_today),
                        title: Text(timelineText),
                        onTap: _selectDateRange,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      value: !_isLocalOnly,
                      onChanged: (v) => setState(() => _isLocalOnly = !v),
                      title: const Text('Global Cloud Sync'),
                      subtitle: const Text('Sync with other devices'),
                    ),
                    if (_selectedPurpose == 'mess')
                      SwitchListTile.adaptive(
                        value: _isManagerLed,
                        onChanged: (v) => setState(() => _isManagerLed = v),
                        title: const Text('Mess Manager (Treasurer)'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Add Members', style: TextStyle(fontWeight: FontWeight.bold)),
                      if (_isLocalOnly) ...[
                        Row(
                          children: [
                            Expanded(child: TextField(controller: _memberController, decoration: const InputDecoration(hintText: 'Name'))),
                            IconButton(onPressed: _addMember, icon: const Icon(Icons.add)),
                          ],
                        ),
                        Wrap(spacing: 8, children: _additionalMembers.map((m) => Chip(label: Text(m), onDeleted: () => setState(() => _additionalMembers.remove(m)))).toList()),
                      ] else ...[
                        TextField(controller: _searchController, decoration: const InputDecoration(hintText: 'Search profiles...'), onChanged: _scheduleUserSearch),
                        ..._searchResults.map((p) {
                          final profile = Map<String, dynamic>.from(p);
                          final isSelected = _selectedProfiles.any((s) => s['id'] == profile['id']);
                          return ListTile(
                            title: Text(profile['name'] ?? 'Unknown'),
                            trailing: Icon(isSelected ? Icons.check_circle : Icons.add_circle_outline),
                            onTap: () => _toggleProfileSelection(profile),
                          );
                        }),
                        Wrap(spacing: 8, children: _selectedProfiles.map((p) => Chip(label: Text(p['name'] ?? 'Member'), onDeleted: () => setState(() => _selectedProfiles.remove(p)))).toList()),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleCreatePressed,
                style: ElevatedButton.styleFrom(backgroundColor: config.color, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}