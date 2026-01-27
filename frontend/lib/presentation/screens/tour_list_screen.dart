import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/app_providers.dart';
import 'create_tour_screen.dart';
import 'tour_details_screen.dart';
import 'package:intl/intl.dart';
import 'user_profile_screen.dart';
import '../../domain/logic/purpose_config.dart';
import '../../data/local/app_database.dart' as models;
import '../../main.dart';

class TourListScreen extends ConsumerStatefulWidget {
  const TourListScreen({super.key});

  @override
  ConsumerState<TourListScreen> createState() => _TourListScreenState();
}

class _TourListScreenState extends ConsumerState<TourListScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-sync on startup
    Future.microtask(() => _triggerInitialSync());
  }

  Future<void> _triggerInitialSync() async {
    final user = ref.read(currentUserProvider).value;
    if (user != null) {
      try {
        await ref.read(syncServiceProvider).startSync(user.id);
      } catch (e) {
        print("Initial auto-sync failed: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  onPressed: () => _syncData(context),
                  icon: const Icon(Icons.sync),
                  tooltip: 'Sync Now',
                ),
                IconButton(
                  onPressed: () => _showJoinDialog(context, config),
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
                _buildCentralFeed(context, config),
                _buildTourList(context, config, user),
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

  Widget _buildCentralFeed(BuildContext context, PurposeConfig config) {
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
                  backgroundImage: item.payer?.avatarUrl != null ? NetworkImage(item.payer!.avatarUrl!) : null,
                  child: item.payer?.avatarUrl == null 
                    ? Text(item.payer?.name[0].toUpperCase() ?? 'M', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)) 
                    : null,
                ),
                title: Text(item.expense.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Paid by ${item.payer?.name ?? 'Combined'} • ${item.tour.name}", 
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

  Widget _buildTourList(BuildContext context, PurposeConfig config, models.User? currentUser) {
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
            final isCreator = currentUser != null && tour.createdBy == currentUser.id;
            
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => TourDetailsScreen(tourId: tour.id, tourName: tour.name)));
                },
                leading: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.map_rounded, color: Colors.blue.shade700),
                ),
                title: Text(tour.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                subtitle: Text(
                  tour.startDate == null 
                    ? "Active Adventure" 
                    : "${DateFormat('MMM dd').format(tour.startDate!)} - ${DateFormat('MMM dd, yyyy').format(tour.endDate ?? tour.startDate!)}",
                  style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
                ),
                trailing: isCreator ? PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => CreateTourScreen(initialTour: tour)));
                    } else if (value == 'delete') {
                      _confirmDeleteTour(context, tour);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')]),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 18), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))]),
                    ),
                  ],
                ) : const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }

  void _confirmDeleteTour(BuildContext context, models.Tour tour) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Tour"),
        content: Text("Are you sure you want to delete '${tour.name}'? This will delete all expenses and records associated with it."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              final db = ref.read(databaseProvider);
              await db.deleteTourWithDetails(tour.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tour deleted")));
              }
            }, 
            child: const Text("Delete", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }

  Future<void> _syncData(BuildContext context) async {
    final user = await ref.read(currentUserProvider.future);
    if (user != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Syncing...'), duration: Duration(seconds: 1)));
      await ref.read(syncServiceProvider).startSync(user.id);
    }
  }

  void _showJoinDialog(BuildContext context, PurposeConfig config) {
    final controller = TextEditingController();
    bool isLoading = false;
    String? errorText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40, 
                      height: 4, 
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))
                    )
                  ),
                  Text(
                    'Join ${config.label}', 
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the 6-digit code shared with you',
                    style: TextStyle(color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: controller,
                    enabled: !isLoading,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    decoration: InputDecoration(
                        hintText: 'CODE',
                        hintStyle: TextStyle(color: Colors.grey.shade300, letterSpacing: 2),
                        fillColor: config.color.withOpacity(0.05),
                        filled: true,
                        counterText: "",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: config.color, width: 2),
                        ),
                        errorText: errorText,
                        suffixIcon: IconButton(
                          icon: Icon(Icons.paste, color: config.color),
                          onPressed: isLoading ? null : () async {
                            try {
                              final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
                              if (clipboardData != null && clipboardData.text != null) {
                                final pastedText = clipboardData.text!.trim().toUpperCase();
                                // Only paste if it looks like a valid code (6 alphanumeric characters)
                                if (pastedText.length == 6 && RegExp(r'^[A-Z0-9]+$').hasMatch(pastedText)) {
                                  controller.text = pastedText;
                                  setState(() => errorText = null);
                                } else {
                                  setState(() => errorText = "Invalid code format");
                                }
                              }
                            } catch (e) {
                              setState(() => errorText = "Failed to paste");
                            }
                          },
                        ) 
                    ),
                    onChanged: (val) {
                      if (errorText != null) setState(() => errorText = null);
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: isLoading ? null : () async {
                      final code = controller.text.trim().toUpperCase();
                      if (code.length != 6) {
                        setState(() => errorText = "Code must be 6 digits");
                        return;
                      }

                      setState(() {
                        isLoading = true; 
                        errorText = null;
                      });
                      
                      try {
                        final user = await ref.read(currentUserProvider.future);
                        if (user != null) {
                          await ref.read(syncServiceProvider).joinByInvite(
                            code,
                            user.id,
                            user.name,
                            email: user.email,
                            avatarUrl: user.avatarUrl,
                            purpose: user.purpose,
                          );
                          
                          // Force refresh
                          ref.invalidate(tourListProvider);
                          
                          if (context.mounted) {
                            Navigator.pop(context); // Close sheet
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.check_circle, color: Colors.white),
                                    const SizedBox(width: 12),
                                    Text('Joined ${config.label} successfully!'),
                                  ],
                                ),
                                backgroundColor: Colors.green.shade600,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          }
                        }
                      } catch (e) {
                         setState(() {
                           // Extract clean message
                           String msg = e.toString().replaceAll("Exception:", "").trim();
                           if (msg.contains("404")) msg = "Invalid Invite Code";
                           else if (msg.contains("Connection failed")) msg = "Network Error. Check connection.";
                           errorText = msg;
                         });
                      } finally {
                        setState(() => isLoading = false);
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: config.color,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: isLoading 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Join Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}



