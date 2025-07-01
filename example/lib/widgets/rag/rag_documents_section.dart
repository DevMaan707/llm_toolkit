import 'package:flutter/material.dart';
import '../../services/rag_service.dart';
import '../../utils/formatters.dart';

class RagDocumentsSection extends StatelessWidget {
  final RagService ragService;

  const RagDocumentsSection({Key? key, required this.ragService})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          if (ragService.documents.isNotEmpty)
            _buildDocumentsList()
          else
            _buildEmptyState(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.blue.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_rounded, color: Colors.blue.shade600, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Documents (${ragService.documents.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'Upload TXT, MD, or PDF files',
                  style: TextStyle(color: Colors.blue.shade600, fontSize: 11),
                ),
              ],
            ),
          ),
          // Add dropdown for different file picker methods
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'normal') {
                await _addDocument(context);
              } else if (value == 'alternative') {
                await _addDocumentAlternative(context);
              }
            },
            itemBuilder:
                (context) => [
                  PopupMenuItem(
                    value: 'normal',
                    child: Row(
                      children: [
                        Icon(Icons.add_rounded, size: 16),
                        SizedBox(width: 8),
                        Text('Add Documents', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'alternative',
                    child: Row(
                      children: [
                        Icon(Icons.file_upload_rounded, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Alternative Picker',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ragService.isProcessing)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  else
                    Icon(Icons.add_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    ragService.isProcessing ? 'Processing...' : 'Add',
                    style: TextStyle(fontSize: 11, color: Colors.white),
                  ),
                  SizedBox(width: 2),
                  Icon(Icons.arrow_drop_down, size: 14, color: Colors.white),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addDocumentAlternative(BuildContext context) async {
    try {
      await ragService.addDocumentFromFileAlternative();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('Document added successfully!'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding document: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Widget _buildDocumentsList() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: ragService.documents.length,
        itemBuilder: (context, index) {
          final doc = ragService.documents[index];
          return _buildDocumentTile(doc, context);
        },
      ),
    );
  }

  Widget _buildDocumentTile(RagDocument doc, BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(
            doc.fileIcon, // Use the dynamic icon
            color: Colors.blue.shade600,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        doc.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        doc.fileTypeDisplay, // Show file type
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${doc.chunkCount} chunks',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      doc.formattedSize,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      Formatters.formatDate(doc.addedAt),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _removeDocument(doc, context),
            icon: Icon(
              Icons.delete_outline_rounded,
              color: Colors.red.shade600,
              size: 16,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No documents added yet',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add documents to build your knowledge base',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _addDocument(BuildContext context) async {
    try {
      await ragService.addDocumentFromFile();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('Document added successfully!'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        String errorMessage = 'Error adding document: $e';

        // Provide more user-friendly error messages
        if (e.toString().contains('UTF-8')) {
          errorMessage =
              'File encoding not supported. Please save as UTF-8 or try a different file.';
        } else if (e.toString().contains('PDF')) {
          errorMessage =
              'Could not extract text from PDF. Try converting to a text file.';
        } else if (e.toString().contains('empty')) {
          errorMessage =
              'The selected file appears to be empty or contains no readable text.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _removeDocument(RagDocument doc, BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text(
              'Remove Document',
              style: TextStyle(fontSize: 16),
            ),
            content: Text(
              'Are you sure you want to remove "${doc.name}"?',
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    await ragService.removeDocument(doc.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Document removed successfully'),
                          backgroundColor: Colors.green.shade600,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error removing document: $e'),
                          backgroundColor: Colors.red.shade600,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Remove', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
    );
  }
}
