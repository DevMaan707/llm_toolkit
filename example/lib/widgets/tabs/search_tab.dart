import 'package:flutter/material.dart';
import '../../services/llm_service.dart';
import '../common/search_bar_widget.dart';
import '../common/browse_button.dart';
import '../cards/model_card.dart';
import '../common/empty_state.dart';

class SearchTab extends StatefulWidget {
  final LLMService llmService;

  const SearchTab({Key? key, required this.llmService}) : super(key: key);

  @override
  _SearchTabState createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SearchBarWidget(
                controller: _searchController,
                onSearch: (query) => widget.llmService.searchModelsFN(query),
                onClear: () => widget.llmService.searchModelsFN(''),
              ),
              const SizedBox(height: 16),
              BrowseButton(
                onPressed: () => _browseAndLoadModel(context),
                isLoading: widget.llmService.isLoading,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: widget.llmService,
            builder: (context, _) {
              if (widget.llmService.isSearching) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Searching models...'),
                    ],
                  ),
                );
              }

              if (widget.llmService.searchModels.isEmpty) {
                return const EmptyState(
                  icon: Icons.search_off,
                  title: 'No models found',
                  subtitle: 'Try searching for different terms',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.llmService.searchModels.length,
                itemBuilder: (context, index) {
                  return ModelCard(
                    model: widget.llmService.searchModels[index],
                    llmService: widget.llmService,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _browseAndLoadModel(BuildContext context) async {
    try {
      final result = await widget.llmService.browseAndLoadModel();
      if (result != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Model loaded successfully!'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }
}
