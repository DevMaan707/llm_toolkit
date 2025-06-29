import 'package:flutter/material.dart';
import 'package:llm_toolkit/llm_toolkit.dart';
import '../../services/llm_service.dart';
import '../../utils/formatters.dart';
import 'file_card.dart';

class ModelCard extends StatefulWidget {
  final ModelInfo model;
  final LLMService llmService;

  const ModelCard({Key? key, required this.model, required this.llmService})
    : super(key: key);

  @override
  State<ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends State<ModelCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final predictedEngine = ModelDetector.instance.detectEngine(
      widget.model.compatibleFiles.isNotEmpty
          ? widget.model.compatibleFiles.first.filename
          : widget.model.name,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.1), width: 1),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          expansionTileTheme: const ExpansionTileThemeData(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
          ),
        ),
        child: ExpansionTile(
          onExpansionChanged: (expanded) {
            setState(() => _isExpanded = expanded);
            if (expanded) {
              _animationController.forward();
            } else {
              _animationController.reverse();
            }
          },
          tilePadding: const EdgeInsets.all(16),
          childrenPadding: EdgeInsets.zero,
          leading: _buildModelIcon(predictedEngine),
          title: Text(
            widget.model.name,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Color(0xFF0F172A),
              letterSpacing: -0.1,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _buildStats(),
              const SizedBox(height: 10),
              _buildBadges(predictedEngine),
            ],
          ),
          trailing: AnimatedRotation(
            turns: _isExpanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 250),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF3B82F6),
                size: 16,
              ),
            ),
          ),
          children: [
            FadeTransition(
              opacity: _fadeAnimation,
              child: _buildExpandedContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelIcon(InferenceEngineType engine) {
    final isGemma = engine == InferenceEngineType.gemma;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors:
              isGemma
                  ? [const Color(0xFF3B82F6), const Color(0xFF1E40AF)]
                  : [const Color(0xFF059669), const Color(0xFF047857)],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: (isGemma ? const Color(0xFF3B82F6) : const Color(0xFF059669))
                .withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        isGemma ? Icons.psychology_rounded : Icons.memory_rounded,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        _buildStatItem(
          Icons.download_rounded,
          Formatters.formatNumber(widget.model.downloads),
          'downloads',
        ),
        const SizedBox(width: 16),
        _buildStatItem(
          Icons.folder_rounded,
          '${widget.model.compatibleFiles.length}',
          'files',
        ),
      ],
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: const Color(0xFF64748B)),
        const SizedBox(width: 4),
        RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 11),
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
              TextSpan(
                text: ' $label',
                style: const TextStyle(
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBadges(InferenceEngineType predictedEngine) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _buildEngineBadge(predictedEngine),
        if (widget.model.ggufFiles.isNotEmpty)
          _buildFormatBadge('GGUF', const Color(0xFF059669)),
        if (widget.model.tfliteFiles.isNotEmpty)
          _buildFormatBadge('TFLite', const Color(0xFF3B82F6)),
      ],
    );
  }

  Widget _buildEngineBadge(InferenceEngineType engine) {
    final isGemma = engine == InferenceEngineType.gemma;
    final color = isGemma ? const Color(0xFF3B82F6) : const Color(0xFF059669);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isGemma ? Icons.psychology_rounded : Icons.memory_rounded,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${engine.name.toUpperCase()}',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatBadge(String format, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Text(
        format,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildExpandedContent() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDescription(),
          const SizedBox(height: 12),
          _buildFilesSection(),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFFF8FAFC), const Color(0xFFF1F5F9)],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.description_rounded,
              color: Color(0xFF3B82F6),
              size: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.model.description.isNotEmpty
                  ? widget.model.description
                  : 'No description available for this model.',
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 11,
                height: 1.4,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF3B82F6).withOpacity(0.1),
                const Color(0xFF3B82F6).withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF3B82F6).withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.folder_rounded,
                color: Color(0xFF3B82F6),
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                'Available Files (${widget.model.compatibleFiles.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: Color(0xFF1E40AF),
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (widget.model.compatibleFiles.isEmpty)
          _buildNoFilesState()
        else
          ...widget.model.compatibleFiles
              .take(5)
              .map(
                (file) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FileCard(
                    model: widget.model,
                    file: file,
                    llmService: widget.llmService,
                  ),
                ),
              )
              .toList(),
      ],
    );
  }

  Widget _buildNoFilesState() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFF59E0B).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFF59E0B),
              size: 14,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'No compatible files available for this model',
              style: TextStyle(
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
