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
  bool _isLoading = false;
  bool _isSearching = false;

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
    final results = await syncService.searchUsers(query);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  Future<void> _addExistingUser(dynamic user) async {
    setState(() => _isLoading = true);
    try {
      final syncService = ref.read(syncServiceProvider);
      await syncService.addMemberToTour(widget.tourId, user['id']);
      
      // Also add found user locally to avoid broken relationships before sync
      final db = ref.read(databaseProvider);
      await db.createUser(User(
        id: user['id'],
        name: user['name'],
        phone: user['phone'],
        isMe: false,
        isSynced: true,
        updatedAt: DateTime.now(),
      ));
      
      await db.into(db.tourMembers).insert(TourMember(
        tourId: widget.tourId,
        userId: user['id'],
        status: 'active',
        mealCount: 0.0,
        isSynced: true,
      ), mode: InsertMode.insertOrReplace);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user['name']} added to tour!')),
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

  Future<void> _addMember() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        final tour = ref.read(singleTourProvider(widget.tourId)).value;
        final config = PurposeConfig.getConfig(tour?.purpose);
        final db = ref.read(databaseProvider);
        final userId = const Uuid().v4();

        await db.createUser(User(
          id: userId,
          name: _nameController.text.trim(),
          phone: _phoneController.text.isEmpty ? null : _phoneController.text.trim(),
          isMe: false,
          isSynced: false,
          updatedAt: DateTime.now(),
        ));

        await db.into(db.tourMembers).insert(TourMember(
          tourId: widget.tourId,
          userId: userId,
          status: 'active',
          mealCount: 0.0,
          isSynced: false,
        ));

        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${config.memberLabel} added manually!')),
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
    final config = PurposeConfig.getConfig(tourAsync.value?.purpose);

    return AlertDialog(
      title: Text('Add ${config.memberLabel}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Bar
              const Text("Search Global Users", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by Name or Phone...',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _isSearching 
                      ? const SizedBox(width: 16, height: 16, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => _searchUsers(_searchController.text)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onSubmitted: _searchUsers,
              ),
              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final u = _searchResults[index];
                      return ListTile(
                        dense: true,
                        title: Text(u['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(u['phone'] ?? u['email'] ?? 'No contact info'),
                        trailing: IconButton(
                          icon: Icon(Icons.person_add_alt_1, color: config.color),
                          onPressed: () => _addExistingUser(u),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // Option 1: Invite Code
              tourAsync.maybeWhen(
                data: (tour) => tour.inviteCode != null ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Share Invite Code", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: config.color)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: config.color.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: config.color.withOpacity(0.1)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(tour.inviteCode!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2)),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.copy, size: 20, color: config.color),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: tour.inviteCode!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Code copied to clipboard!'), duration: Duration(seconds: 2)),
                                  );
                                },
                                tooltip: 'Copy Code',
                              ),
                              IconButton(
                                icon: Icon(Icons.share, size: 20, color: config.color),
                                onPressed: () {
                                  final text = "Join my ${config.label.toLowerCase()} on Group Ledger! Code: ${tour.inviteCode}\n\nDownload the app to manage expenses together.";
                                  Share.share(text);
                                },
                                tooltip: 'Share Code',
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Center(child: Text("OR", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))),
                    const SizedBox(height: 12),
                  ],
                ) : const SizedBox.shrink(),
                orElse: () => const SizedBox.shrink(),
              ),

              // Option 2: Manual Form
              const Text("Add Manually", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        hintText: 'e.g. Abir Hossain',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.person, size: 20),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: 'Phone (Optional)',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.phone, size: 20),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _addMember,
          style: FilledButton.styleFrom(backgroundColor: config.color),
          child: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add Manually'),
        ),
      ],
    );
  }
}

