import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../main.dart';
import '../../data/local/app_database.dart';
import '../../data/providers/app_providers.dart';

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

    return AlertDialog(
      title: const Text('Add Member'),
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
                  const Text("Share Invite Code", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.teal.shade100),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(tour.inviteCode!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2)),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () {
                            // Copy logic
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied!')));
                          },
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
          child: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add Now'),
        ),
      ],
    );
  }
}

