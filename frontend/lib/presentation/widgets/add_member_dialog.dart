import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../main.dart';
import 'package:share_plus/share_plus.dart';
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
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _addMember() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
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
          isSynced: false,
        ));

        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Member added manually!')),
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
    final currentUserAsync = ref.watch(currentUserProvider);
    final config = PurposeConfig.getConfig(currentUserAsync.value?.purpose);

    return AlertDialog(
      title: Text('Add ${config.label} Member'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                                final text = "Join my ${config.label.toLowerCase()} on Manager App! Code: ${tour.inviteCode}\n\nDownload the app to manage expenses together.";
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
              : const Text('Add Now'),
        ),
      ],
    );
  }
}

