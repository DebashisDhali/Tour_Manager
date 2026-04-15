import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../main.dart';
import 'package:share_plus/share_plus.dart';
import 'package:drift/drift.dart' hide Column;
import '../../data/local/app_database.dart';
import '../../data/providers/app_providers.dart';
import '../../domain/logic/purpose_config.dart';

class AddMemberDialog extends ConsumerStatefulWidget {
  final String tourId;
  const AddMemberDialog({super.key, required this.tourId});

  @override
  ConsumerState<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends ConsumerState<AddMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  final Set<Map<String, dynamic>> _selectedUsers = {};
  bool _isLoading = false;
  bool _isSearching = false;
  bool _retroactiveSplit = false; // Whether to include new member in past expenses

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    final syncService = ref.read(syncServiceProvider);
    try {
      final results = await syncService.searchUsers(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _toggleUserSelection(dynamic user) {
    setState(() {
      final userData = Map<String, dynamic>.from(user);
      final userId = userData['id']?.toString() ?? '';
      if (userId.isEmpty) return;

      final existsIndex = _selectedUsers.toList().indexWhere((u) => u['id']?.toString() == userId);
      
      if (existsIndex != -1) {
        _selectedUsers.removeWhere((u) => u['id']?.toString() == userId);
      } else {
        _selectedUsers.add(userData);
      }
    });
  }

  Future<void> _addSelectedUsers() async {
    if (_selectedUsers.isEmpty) return;
    
    setState(() => _isLoading = true);
    final db = ref.read(databaseProvider);
    final syncService = ref.read(syncServiceProvider);
    int count = 0;

    try {
      for (var user in _selectedUsers) {
        try {
          // 1. Add locally
          await db.createUser(User(
            id: user['id'],
            name: user['name'],
            phone: user['phone'],
            isMe: false,
            isSynced: true,
            isDeleted: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ));
          
          await db.into(db.tourMembers).insert(TourMember(
            tourId: widget.tourId,
            userId: user['id'],
            status: 'active',
            role: 'viewer',
            mealCount: 0.0,
            isSynced: true,
            isDeleted: false,
          ), mode: InsertMode.insertOrReplace);

          // 2. Add to server
          await syncService.addMemberToTour(widget.tourId, user['id']);

          // 3. Retroactive split if requested
          if (_retroactiveSplit) {
            final currentUserId = ref.read(currentUserProvider).value?.id;
            await syncService.applyRetroactiveSplitLocally(widget.tourId, user['id']);
            if (currentUserId != null) {
              await syncService.retroactiveSplit(widget.tourId, user['id'], currentUserId);
            }
          }
          count++;
        } catch (e) {
          debugPrint("Failed to add user ${user['name']}: $e");
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $count ${count == 1 ? 'member' : 'members'} successfully!${_retroactiveSplit ? ' Past expenses redistributed.' : ''}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addMemberManually() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        final tour = ref.read(singleTourProvider(widget.tourId)).value;
        final config = PurposeConfig.getConfig(tour?.purpose);
        final db = ref.read(databaseProvider);
        final syncService = ref.read(syncServiceProvider);
        final userId = const Uuid().v4();

        await db.createUser(User(
          id: userId,
          name: _nameController.text.trim(),
          phone: _phoneController.text.isEmpty ? null : _phoneController.text.trim(),
          isMe: false,
          isSynced: false,
          isDeleted: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));

        await db.into(db.tourMembers).insert(TourMember(
          tourId: widget.tourId,
          userId: userId,
          status: 'active',
          role: 'viewer',
          mealCount: 0.0,
          isSynced: false,
          isDeleted: false,
        ));

        // Apply retroactive split locally before navigating away
        if (_retroactiveSplit) {
          await syncService.applyRetroactiveSplitLocally(widget.tourId, userId);
          // Server sync will push redistributed splits on next connectivity
          final currentUserId = ref.read(currentUserProvider).value?.id;
          if (currentUserId != null) {
            syncService.retroactiveSplit(widget.tourId, userId, currentUserId)
              .catchError((e) => debugPrint('Retroactive server sync failed: $e'));
          }
        }

        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
              '${config.memberLabel} added!${_retroactiveSplit ? ' Included in all past expenses.' : ''}'
            )),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tourAsync = ref.watch(singleTourProvider(widget.tourId));
    final tour = tourAsync.value;
    final config = PurposeConfig.getConfig(tour?.purpose);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Row(
        children: [
          Icon(Icons.person_add_rounded, color: config.color),
          const SizedBox(width: 12),
          Text('Add ${config.memberLabel}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Section
              const Text("SEARCH GLOBAL PROFILES", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.grey, letterSpacing: 1)),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Name or Phone number...',
                  filled: true,
                  fillColor: Colors.grey.withOpacity(0.05),
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20, color: config.color),
                  suffixIcon: _isSearching 
                      ? const SizedBox(width: 16, height: 16, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => _searchUsers(_searchController.text)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onSubmitted: _searchUsers,
              ),

              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
                  ),
                  child: Column(
                    children: _searchResults.map((item) {
                      try {
                        if (item == null || item is! Map) return const SizedBox.shrink();
                        
                        final u = Map<String, dynamic>.from(item);
                        final uId = u['id']?.toString() ?? '';
                        if (uId.isEmpty) return const SizedBox.shrink();

                        final isSelected = _selectedUsers.any((selected) => selected['id']?.toString() == uId);
                        final rawName = u['name']?.toString() ?? 'Member';
                        final name = rawName.trim().isEmpty ? 'Member' : rawName.trim();
                        final phone = u['phone']?.toString() ?? u['email']?.toString() ?? 'No contact';
                        
                        return ListTile(
                          onTap: () => _toggleUserSelection(u),
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: isSelected ? config.color : config.color.withOpacity(0.1),
                            child: isSelected 
                              ? const Icon(Icons.check, color: Colors.white, size: 16)
                              : Text(
                                  name[0].toUpperCase(), 
                                  style: TextStyle(color: config.color, fontSize: 12, fontWeight: FontWeight.bold)
                                ),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text(phone, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                          trailing: Checkbox(
                            value: isSelected,
                            activeColor: config.color,
                            shape: const CircleBorder(),
                            onChanged: (_) => _toggleUserSelection(u),
                          ),
                        );
                      } catch (e) {
                         return const SizedBox.shrink();
                      }
                    }).toList(),
                  ),
                ),
              ],

              if (_selectedUsers.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: config.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text("${_selectedUsers.length} selected", style: TextStyle(fontWeight: FontWeight.bold, color: config.color)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() => _selectedUsers.clear()),
                        child: const Text("Clear All", style: TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _addSelectedUsers,
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: Text("Add ${_selectedUsers.length} ${config.memberLabel}s"),
                    style: FilledButton.styleFrom(backgroundColor: config.color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
              ],

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text("OR", style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4), fontWeight: FontWeight.bold))),
                    const Expanded(child: Divider()),
                  ],
                ),
              ),

              // Invite Code Section
              tourAsync.maybeWhen(
                data: (tour) {
                   if (tour == null || tour.inviteCode == null) return const SizedBox.shrink();
                   return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("SHARE INVITE CODE", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.grey, letterSpacing: 1)),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: tour.inviteCode!));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied!')));
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: config.color.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: config.color.withOpacity(0.1)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(tour.inviteCode!, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4)),
                              Icon(Icons.copy_all_rounded, color: config.color, size: 20),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),

              // Retroactive Split Toggle
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _retroactiveSplit ? config.color.withOpacity(0.08) : Colors.grey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _retroactiveSplit ? config.color.withOpacity(0.3) : Colors.grey.withOpacity(0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 18,
                      color: _retroactiveSplit ? config.color : Colors.grey,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Include in past expenses',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _retroactiveSplit ? config.color : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Split all existing expenses equally with this member',
                            style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _retroactiveSplit,
                      onChanged: (v) => setState(() => _retroactiveSplit = v),
                      activeColor: config.color,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ),

              // Manual Section
              const Text("ADD MANUALLY", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.grey, letterSpacing: 1)),
              const SizedBox(height: 12),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: 'Phone (Optional)',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _addMemberManually,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: config.color,
                    side: BorderSide(color: config.color),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Add Manually', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

