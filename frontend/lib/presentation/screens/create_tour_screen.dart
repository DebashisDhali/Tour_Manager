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
import '../widgets/action_help_text.dart';
import '../widgets/premium_card.dart';

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
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _searchUsers(query);
    });
  }

  void _toggleProfileSelection(Map<String, dynamic> user) {
    final userId = user['id']?.toString() ?? '';
    if (userId.isEmpty) return;

    setState(() {
      final existingIndex = _selectedProfiles.indexWhere(
        (selected) => selected['id']?.toString() == userId,
      );
      if (existingIndex != -1) {
        _selectedProfiles.removeAt(existingIndex);
      } else {
        _selectedProfiles.add(user);
      }
    });
  }

  Future<void> _inviteSelectedProfiles(String tourId) async {
    if (_selectedProfiles.isEmpty) return;

    debugPrint(
        '🔄 Inviting ${_selectedProfiles.length} selected profiles to tour $tourId');
    final syncService = ref.read(syncServiceProvider);
    int successCount = 0;
    final failedUsers = <String>[];

    for (final user in _selectedProfiles) {
      final userId = user['id']?.toString() ?? '';
      if (userId.isEmpty) continue;

      try {
        await syncService.addMemberToTour(tourId, userId);
        debugPrint('✅ Invited user ${user['name']} ($userId)');
        successCount++;
      } catch (e) {
        final userName = user['name']?.toString() ?? 'Unknown';
        debugPrint('❌ Failed to invite user $userName: $e');
        failedUsers.add(userName);
      }
    }

    if (mounted) {
      if (successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Invitation sent to $successCount ${successCount == 1 ? 'profile' : 'profiles'}.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      if (failedUsers.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Failed to invite: ${failedUsers.join(", ")}'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      if (successCount == 0 && _selectedProfiles.isNotEmpty) {
        debugPrint('⚠️ No profiles were invited');
      }
    }

    debugPrint(
        '📊 Invitation summary: $successCount/${_selectedProfiles.length} succeeded');
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      initialDateRange: _selectedDateRange,
    );
    if (picked != null && picked != _selectedDateRange) {
      setState(() => _selectedDateRange = picked);
    }
  }

  void _addMember() {
    final raw = _memberController.text.trim();
    if (raw.isEmpty) return;

    // Supports: Rahim, Karim, Selim (single click add for multiple names)
    final parsedNames =
        raw.split(',').map((n) => n.trim()).where((n) => n.isNotEmpty).toList();

    if (parsedNames.isEmpty) return;

    final existingLower =
        _additionalMembers.map((e) => e.toLowerCase()).toSet();
    final namesToAdd = <String>[];
    for (final name in parsedNames) {
      final normalized = name.toLowerCase();
      if (!existingLower.contains(normalized)) {
        namesToAdd.add(name);
        existingLower.add(normalized);
      }
    }

    if (namesToAdd.isEmpty) {
      _memberController.clear();
      return;
    }

    setState(() {
      _additionalMembers.addAll(namesToAdd);
      _memberController.clear();
    });
  }

  Future<void> _createTour() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        final db = ref.read(databaseProvider);
        User? currentUser = await ref.read(currentUserProvider.future);

        if (currentUser == null) throw Exception("Profile not found.");

        debugPrint(
            '🎬 Creating tour in ${_isLocalOnly ? 'LOCAL' : 'GLOBAL'} mode');
        debugPrint(
            '📋 Selected profiles: ${_selectedProfiles.length}, Additional members: ${_additionalMembers.length}');

        final String finalTourId;

        if (widget.initialTour == null) {
          finalTourId = const Uuid().v4();
          const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
          final inviteCode =
              List.generate(6, (index) => chars[Random().nextInt(chars.length)])
                  .join();

          await db.createTour(Tour(
              id: finalTourId,
              name: _nameController.text.trim(),
              startDate: _selectedDateRange?.start,
              endDate: _selectedDateRange?.end,
              inviteCode: inviteCode,
              createdBy: currentUser.id,
              purpose: _selectedPurpose,
              isSynced: false,
              isDeleted: false,
              updatedAt: DateTime.now()));

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
                updatedAt: DateTime.now(),
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
            startDate: drift.Value(_selectedDateRange?.start),
            endDate: drift.Value(_selectedDateRange?.end),
            isSynced: false,
            isDeleted: false,
            updatedAt: DateTime.now(),
          ));

          await db.setTourLocalOnly(finalTourId, _isLocalOnly);

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
                updatedAt: DateTime.now(),
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
        }

        if (mounted) {
          if (_isLocalOnly) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Saved as local-only. This event will stay on this device.'),
                backgroundColor: Colors.blueGrey,
                duration: Duration(seconds: 4),
              ),
            );
          } else {
            bool synced = false;
            for (int attempt = 1; attempt <= 3; attempt++) {
              try {
                await ref.read(syncServiceProvider).startSync(currentUser.id);
                synced = true;
                debugPrint("✅ Tour synced on attempt $attempt");
                break;
              } catch (syncErr) {
                debugPrint("⚠️ Sync attempt $attempt failed: $syncErr");
                if (attempt < 3) {
                  await Future.delayed(const Duration(seconds: 2));
                }
              }
            }
            debugPrint(
                '🔍 After sync: synced=$synced, selectedProfiles=${_selectedProfiles.length}');
            if (synced && _selectedProfiles.isNotEmpty) {
              debugPrint(
                  '⏳ Waiting 1 second for server state to settle after sync...');
              await Future.delayed(const Duration(seconds: 1));
              await _inviteSelectedProfiles(finalTourId);
            } else if (!synced) {
              debugPrint('⚠️ Skipping invites - sync failed');
            } else if (_selectedProfiles.isEmpty) {
              debugPrint('ℹ️ No profiles selected for invitation');
            }
            if (!synced && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      "Saved locally. Sync pending — share code when online."),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 4),
                ),
              );
            }
          }
          if (mounted) Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = PurposeConfig.getConfig(_selectedPurpose);
    final timelineText = _selectedDateRange == null
        ? 'Set date range (optional)'
        : '${DateFormat('dd MMM yyyy').format(_selectedDateRange!.start)} - ${DateFormat('dd MMM yyyy').format(_selectedDateRange!.end)}';

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.initialTour == null
                ? 'Create ${config.label}'
                : 'Edit ${config.label}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        backgroundColor: config.color,
        flexibleSpace:
            Container(decoration: BoxDecoration(gradient: config.gradient)),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PremiumCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInputLabel("Category", config.color),
                    DropdownButtonFormField<String>(
                      value: _selectedPurpose,
                      decoration: _getInputDecoration(
                          hint: "Category",
                          icon: config.icon,
                          color: config.color),
                      items: ['project', 'tour', 'event', 'party', 'mess']
                          .map((p) {
                        final pConfig = PurposeConfig.getConfig(p);
                        return DropdownMenuItem(
                            value: p, child: Text(pConfig.label));
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedPurpose = value);
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildInputLabel("Title", config.color),
                    TextFormField(
                      controller: _nameController,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      decoration: _getInputDecoration(
                          hint: 'e.g. Weekend Cox\'s Bazar ${config.label}',
                          icon: Icons.edit_note_rounded,
                          color: config.color),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) return 'Please enter a title';
                        if (value.length < 3) {
                          return 'Title should be at least 3 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildInputLabel("Dates", config.color),
                    InkWell(
                      onTap: _selectDateRange,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                            color: config.color.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month_rounded,
                                color: config.color, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(
                              timelineText,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedDateRange == null
                                      ? Colors.black38
                                      : Colors.black87),
                            )),
                            if (_selectedDateRange != null)
                              Icon(Icons.check_circle_rounded,
                                  color: config.color, size: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildInputLabel("Storage", config.color),
                    Container(
                      decoration: BoxDecoration(
                        color: config.color.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SwitchListTile.adaptive(
                        value: _isLocalOnly,
                        onChanged: (value) {
                          setState(() {
                            _isLocalOnly = value;
                            // Clear search state when toggling mode
                            _searchController.clear();
                            _searchResults.clear();
                            _selectedProfiles.clear();
                            _memberController.clear();
                            _additionalMembers.clear();
                          });
                        },
                        activeColor: config.color,
                        title: Text(
                          _isLocalOnly
                              ? 'Local Only (No Cloud Sync)'
                              : 'Global (Sync to Cloud)',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Text(
                          _isLocalOnly
                              ? 'This event stays only on this device.'
                              : 'This event syncs and can be shared with others.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const ActionHelpText(
                  'Choose category and title, set dates, then add members. Local-only accepts any name. Global mode searches real profiles to invite.'),
              _buildInputLabel("Add Members", config.color),
              PremiumCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isLocalOnly) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _memberController,
                              decoration: _getInputDecoration(
                                  hint: 'Any name allowed, comma separated',
                                  icon: Icons.person_add_rounded,
                                  color: config.color,
                                  dense: true),
                              onFieldSubmitted: (_) => _addMember(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton.filled(
                            onPressed: _addMember,
                            icon: const Icon(Icons.add),
                            style: IconButton.styleFrom(
                              backgroundColor: config.color,
                              minimumSize: const Size(48, 48),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Local-only mode lets you add custom names that stay on this device.',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                      if (_additionalMembers.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              _additionalMembers.asMap().entries.map((entry) {
                            return Chip(
                              label: Text(entry.value,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                              onDeleted: () => setState(
                                  () => _additionalMembers.removeAt(entry.key)),
                              backgroundColor:
                                  config.color.withValues(alpha: 0.1),
                              side: BorderSide(
                                  color: config.color.withValues(alpha: 0.1)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            );
                          }).toList(),
                        ),
                      ],
                    ] else ...[
                      TextField(
                        controller: _searchController,
                        decoration: _getInputDecoration(
                            hint: 'Search real profiles by name or phone',
                            icon: Icons.search_rounded,
                            color: config.color,
                            dense: true),
                        onChanged: _scheduleUserSearch,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isSearching
                            ? 'Searching profiles...'
                            : 'Select existing profiles to send invitation requests after save.',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54),
                      ),
                      if (_searchResults.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Theme.of(context)
                                    .dividerColor
                                    .withValues(alpha: 0.1)),
                          ),
                          child: Column(
                            children: _searchResults.map((item) {
                              try {
                                if (item == null || item is! Map) {
                                  return const SizedBox.shrink();
                                }

                                final profile = Map<String, dynamic>.from(item);
                                final profileId =
                                    profile['id']?.toString() ?? '';
                                if (profileId.isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                final isSelected = _selectedProfiles.any(
                                  (selected) =>
                                      selected['id']?.toString() == profileId,
                                );
                                final rawName =
                                    profile['name']?.toString() ?? 'Member';
                                final name = rawName.trim().isEmpty
                                    ? 'Member'
                                    : rawName.trim();
                                final phone = profile['phone']?.toString() ??
                                    profile['email']?.toString() ??
                                    'No contact';

                                return ListTile(
                                  onTap: () => _toggleProfileSelection(profile),
                                  dense: true,
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected
                                        ? config.color
                                        : config.color.withValues(alpha: 0.1),
                                    child: isSelected
                                        ? const Icon(Icons.check,
                                            color: Colors.white, size: 16)
                                        : Text(name[0].toUpperCase(),
                                            style: TextStyle(
                                                color: config.color,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold)),
                                  ),
                                  title: Text(name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                  subtitle: Text(phone,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.6))),
                                  trailing: Checkbox(
                                    value: isSelected,
                                    activeColor: config.color,
                                    shape: const CircleBorder(),
                                    onChanged: (_) =>
                                        _toggleProfileSelection(profile),
                                  ),
                                );
                              } catch (e) {
                                return const SizedBox.shrink();
                              }
                            }).toList(),
                          ),
                        ),
                      ],
                      if (_selectedProfiles.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              _selectedProfiles.asMap().entries.map((entry) {
                            final profile = entry.value;
                            final name =
                                (profile['name']?.toString() ?? 'Member')
                                    .trim();
                            return Chip(
                              label: Text(
                                name.isEmpty ? 'Member' : name,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              onDeleted: () => setState(
                                () => _selectedProfiles.removeAt(entry.key),
                              ),
                              backgroundColor:
                                  config.color.withValues(alpha: 0.1),
                              side: BorderSide(
                                  color: config.color.withValues(alpha: 0.1)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                height: 64,
                child: FilledButton(
                    onPressed: _isLoading ? null : _createTour,
                    style: FilledButton.styleFrom(
                        backgroundColor: config.color,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                        shadowColor: config.color.withValues(alpha: 0.5)),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            widget.initialTour == null
                                ? 'Create ${config.label}'
                                : 'Save ${config.label}',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputLabel(String label, Color color) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 4),
        child: Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: 1.2)));
  }

  InputDecoration _getInputDecoration(
      {required String hint,
      required IconData icon,
      required Color color,
      bool dense = false}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: color, size: 20),
      filled: true,
      fillColor: color.withValues(alpha: 0.05),
      contentPadding: dense
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
          : const EdgeInsets.all(20),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: 2)),
    );
  }
}
