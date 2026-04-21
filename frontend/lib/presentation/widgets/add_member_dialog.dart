import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  final bool _retroactiveSplit =
      false; // Whether to include new member in past expenses

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

      final existsIndex = _selectedUsers
          .toList()
          .indexWhere((u) => u['id']?.toString() == userId);

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
    final syncService = ref.read(syncServiceProvider);
    int count = 0;

    try {
      for (var user in _selectedUsers) {
        try {
          // Send invitation; target user must accept from their profile.
          await syncService.addMemberToTour(widget.tourId, user['id']);
          count++;
        } catch (e) {
          debugPrint("Failed to add user ${user['name']}: $e");
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        
        // Trigger a sync so the Admin sees the pending records immediately
        final me = ref.read(currentUserProvider).value;
        if (me != null) {
          syncService.startSync(me.id).catchError((e) => debugPrint("Post-invite sync failed: $e"));
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Invitation sent to $count ${count == 1 ? 'member' : 'members'}. They must accept from profile.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addMemberManually() async {
    if (_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Manual add is disabled for approval flow. Search and select existing profiles to send requests.'),
        ),
      );
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
          Text('Add ${config.memberLabel}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Section
              const Text("SEARCH GLOBAL PROFILES",
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      color: Colors.grey,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              const Text(
                'Search existing profiles and send invitation requests. Users will join only after accepting from their profile.',
                style: TextStyle(
                    fontSize: 11, color: Colors.grey, letterSpacing: 0.2),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Name or Phone number...',
                  filled: true,
                  fillColor: Colors.grey.withValues(alpha: 0.05),
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20, color: config.color),
                  suffixIcon: _isSearching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: () =>
                              _searchUsers(_searchController.text)),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
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

                        final u = Map<String, dynamic>.from(item);
                        final uId = u['id']?.toString() ?? '';
                        if (uId.isEmpty) return const SizedBox.shrink();

                        final isSelected = _selectedUsers.any(
                            (selected) => selected['id']?.toString() == uId);
                        final rawName = u['name']?.toString() ?? 'Member';
                        final name =
                            rawName.trim().isEmpty ? 'Member' : rawName.trim();
                        final phone = u['phone']?.toString() ??
                            u['email']?.toString() ??
                            'No contact';

                        return ListTile(
                          onTap: () => _toggleUserSelection(u),
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
                                  fontWeight: FontWeight.bold, fontSize: 13)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: config.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text("${_selectedUsers.length} selected",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: config.color)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() => _selectedUsers.clear()),
                        child: const Text("Clear All",
                            style: TextStyle(color: Colors.red, fontSize: 12)),
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
                    label: Text(
                        "Send request to ${_selectedUsers.length} ${config.memberLabel}${_selectedUsers.length > 1 ? 's' : ''}"),
                    style: FilledButton.styleFrom(
                        backgroundColor: config.color,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                  ),
                ),
              ],

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text("OR",
                            style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.4),
                                fontWeight: FontWeight.bold))),
                    const Expanded(child: Divider()),
                  ],
                ),
              ),

              // Retroactive Split Toggle
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _retroactiveSplit
                      ? config.color.withValues(alpha: 0.08)
                      : Colors.grey.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _retroactiveSplit
                        ? config.color.withValues(alpha: 0.3)
                        : Colors.grey.withValues(alpha: 0.1),
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
                              color: _retroactiveSplit
                                  ? config.color
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Split all existing expenses equally with this member',
                            style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5)),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _retroactiveSplit,
                      onChanged: null,
                      activeColor: config.color,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ),

              // Manual Section
              const Text("ADD MANUALLY",
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      color: Colors.grey,
                      letterSpacing: 1)),
              const SizedBox(height: 12),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        hintText: 'Type names separated by commas',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                      ),
                      validator: (v) {
                        final names = v
                                ?.split(',')
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList() ??
                            [];
                        if (names.isEmpty) return 'Required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Approval flow works with existing profiles. Search above and send request instead of direct manual add.',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: 'Phone (Optional)',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Add Member(s)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tip: Open user search above, select profiles, then send request.',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55)),
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
