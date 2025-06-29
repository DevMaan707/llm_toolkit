import 'package:flutter/material.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback onDebugToggle;
  final bool showDebugPanel;
  final TabController tabController;

  const CustomAppBar({
    Key? key,
    required this.title,
    required this.onDebugToggle,
    required this.showDebugPanel,
    required this.tabController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).primaryColor,
            Theme.of(context).primaryColor.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.psychology_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: onDebugToggle,
            icon: Icon(
              showDebugPanel ? Icons.bug_report : Icons.bug_report_outlined,
              color: showDebugPanel ? Colors.orange.shade300 : Colors.white70,
            ),
            tooltip: showDebugPanel ? 'Hide Debug Panel' : 'Show Debug Panel',
          ),
          IconButton(
            onPressed: () {
              // Add settings functionality
            },
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            tooltip: 'Settings',
          ),
        ],
        bottom: TabBar(
          controller: tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w400,
            fontSize: 14,
          ),
          tabs: const [
            Tab(icon: Icon(Icons.search_rounded, size: 20), text: 'Search'),
            Tab(icon: Icon(Icons.star_rounded, size: 20), text: 'Recommended'),
            Tab(
              icon: Icon(Icons.storage_rounded, size: 20),
              text: 'Downloaded',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(120);
}
