import 'package:flutter/material.dart';
import 'screens/model_browser_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(LLMToolkitApp());
}

class LLMToolkitApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LLM Toolkit Pro',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: ModelBrowserScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
