import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/app_providers.dart';
import 'create_tour_screen.dart';
import 'tour_details_screen.dart';
import 'package:intl/intl.dart';
import 'user_profile_screen.dart';
import '../../domain/logic/purpose_config.dart';

class TourListScreen extends ConsumerWidget {
  const TourListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserAsync = ref.watch(currentUserProvider);

    return currentUserAsync.when(
      data: (user) {
        final config = PurposeConfig.getConfig(user?.purpose);
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text('${config.label} Manager', style: const TextStyle(fontWeight: FontWeight.bold)),
              bottom: TabBar(
                tabs: [
                  const Tab(icon: Icon(Icons.dashboard_outlined), text: 'Feed'),
                  Tab(icon: Icon(Icons.map_outlined), text: 'My ${config.pluralLabel}'),
                ],
              ),
              actions: [
                IconButton(
                  onPressed: () => _syncData(context, ref),
                  icon: const Icon(Icons.sync),
                  tooltip: 'Sync Now',
                ),
                IconButton(
                  onPressed: () => _showJoinDialog(context, ref, config),
                  icon: const Icon(Icons.group_add_outlined),
                  tooltip: 'Join ${config.label}',
                ),
                if (user != null) InkWell(
                  onTap: () {
                     Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(user: user, isMe: true)));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: config.color.withOpacity(0.8),
                      backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                      child: user.avatarUrl == null ? Text(user.name[0].toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.white)) : null,
                    ),
                  ),
                ),
              ],
            ),
            body: TabBarView(
              children: [
                _buildCentralFeed(context, ref, config),
                _buildTourList(context, ref, config),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateTourScreen()));
              },
              label: Text('New ${config.label}'),
              icon: const Icon(Icons.auto_awesome),
              backgroundColor: config.color,
              foregroundColor: Colors.white,
            ),
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, s) => Scaffold(body: Center(child: Text("Error: $e"))),
    );
  }

  Widget _buildCentralFeed(BuildContext context, WidgetRef ref, PurposeConfig config) {
    final recentExpensesAsync = ref.watch(globalRecentExpensesProvider);

    return recentExpensesAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_toggle_off, size: 80, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                const Text("No Recent Expenses", style: TextStyle(fontSize: 18, color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: CircleAvatar(
                  radius: 25,
                  backgroundColor: Colors.teal.shade50,
                  backgroundImage: item.payer.avatarUrl != null ? NetworkImage(item.payer.avatarUrl!) : null,
                  child: item.payer.avatarUrl == null ? Text(item.payer.name[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)) : null,
                ),
                title: Text(item.expense.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Paid by ${item.payer.name} • ${item.tour.name}", 
                      style: TextStyle(color: Colors.teal.shade600, fontSize: 12)),
                    Text(DateFormat('MMM dd, hh:mm a').format(item.expense.createdAt), 
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                trailing: Text("${item.expense.amount.toStringAsFixed(0)} ৳", 
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                onTap: () {
                   Navigator.push(context, MaterialPageRoute(builder: (_) => TourDetailsScreen(tourId: item.tour.id, tourName: item.tour.name)));
                },
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }

  Widget _buildTourList(BuildContext context, WidgetRef ref, PurposeConfig config) {
    final toursAsync = ref.watch(tourListProvider);

    return toursAsync.when(
      data: (tours) {
        if (tours.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.beach_access_rounded, size: 80, color: Colors.grey),
                const SizedBox(height: 16),
                Text("No tours yet!", style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text("Time to plan a new adventure!"),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: tours.length,
          itemBuilder: (context, index) {
            final tour = tours[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => TourDetailsScreen(tourId: tour.id, tourName: tour.name)));
                },
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.map_rounded, color: Colors.blue.shade700),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tour.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            Text(
                              tour.startDate == null 
                                ? "Active Adventure" 
                                : "${DateFormat('MMM dd').format(tour.startDate!)} - ${DateFormat('MMM dd, yyyy').format(tour.endDate ?? tour.startDate!)}",
                              style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }

  Future<void> _syncData(BuildContext context, WidgetRef ref) async {
    final user = await ref.read(currentUserProvider.future);
    if (user != null) {
      await ref.read(syncServiceProvider).startSync(user.id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Syncing...')));
    }
  }

  void _showJoinDialog(BuildContext context, WidgetRef ref, PurposeConfig config) {
    final controller = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Join ${config.label}'),
          content: TextField(
            controller: controller,
            enabled: !isLoading,
            decoration: InputDecoration(
              hintText: 'Enter 6-digit Invite Code',
              border: const OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context), 
              child: const Text('Cancel')
            ),
            FilledButton(
              onPressed: isLoading ? null : () async {
                final code = controller.text.trim().toUpperCase();
                if (code.isEmpty) return;

                setState(() => isLoading = true);
                try {
                  final user = await ref.read(currentUserProvider.future);
                  if (user != null) {
                    await ref.read(syncServiceProvider).joinByInvite(
                      code,
                      user.id,
                      user.name
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Successfully joined!')),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error joining: $e'), backgroundColor: Colors.red),
                    );
                  }
                } finally {
                  if (context.mounted) setState(() => isLoading = false);
                }
              },
              child: isLoading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Join Now'),
            ),
          ],
        ),
      ),
    );
  }
}



