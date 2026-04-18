import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../data/providers/app_providers.dart';

class AiCoachScreen extends ConsumerStatefulWidget {
  final String tourId;
  final String tourName;

  const AiCoachScreen({
    super.key,
    required this.tourId,
    required this.tourName,
  });

  @override
  ConsumerState<AiCoachScreen> createState() => _AiCoachScreenState();
}

class _AiCoachScreenState extends ConsumerState<AiCoachScreen> {
  bool _isLoading = true;
  String? _reportText;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchInsights();
  }

  Future<void> _fetchInsights() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _reportText = null;
    });

    try {
      final aiService = ref.read(aiServiceProvider);
      // We pass an empty message, backend handles the specific RAG instructions
      final reply = await aiService.getTourInsights(widget.tourId, "");
      
      if (mounted) {
        setState(() {
          _reportText = reply;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Failed to generate AI insights.\n\nDetails: $e";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 20, color: Colors.amberAccent),
            SizedBox(width: 8),
            Text("AI Expense Analysis"),
          ],
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.amberAccent),
            const SizedBox(height: 24),
            Text(
              "Analyzing expenses for ${widget.tourName}...\nFinding optimizations & wasteful costs",
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.bold),
            )
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text("Error", style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _fetchInsights, 
                icon: const Icon(Icons.refresh), 
                label: const Text("Try Again")
              )
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.insights, color: Colors.amber, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    "AI insight is generated dynamically based on real-time data of your expenses.",
                    style: TextStyle(fontSize: 12, color: Colors.amber.shade700, fontWeight: FontWeight.w600),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_reportText != null)
            MarkdownBody(
              data: _reportText!,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(fontSize: 14, height: 1.5, color: Theme.of(context).textTheme.bodyMedium?.color),
                h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber),
                h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                listBullet: TextStyle(color: Theme.of(context).colorScheme.primary),
                code: TextStyle(backgroundColor: Colors.grey.withValues(alpha: 0.1), fontFamily: 'monospace'),
                blockquoteDecoration: BoxDecoration(
                  border: Border(left: BorderSide(color: Colors.amber.withValues(alpha: 0.5), width: 4)),
                  color: Colors.amber.withValues(alpha: 0.05),
                ),
                tableBorder: TableBorder.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
                tableHead: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}

