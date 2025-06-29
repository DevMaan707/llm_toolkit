import 'package:flutter/material.dart';

class ChatSettingsDialog extends StatefulWidget {
  final double temperature;
  final int maxTokens;
  final double topP;
  final Function(double, int, double) onSettingsChanged;

  const ChatSettingsDialog({
    Key? key,
    required this.temperature,
    required this.maxTokens,
    required this.topP,
    required this.onSettingsChanged,
  }) : super(key: key);

  @override
  _ChatSettingsDialogState createState() => _ChatSettingsDialogState();
}

class _ChatSettingsDialogState extends State<ChatSettingsDialog> {
  late double _temperature;
  late int _maxTokens;
  late double _topP;

  @override
  void initState() {
    super.initState();
    _temperature = widget.temperature;
    _maxTokens = widget.maxTokens;
    _topP = widget.topP;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Generation Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Temperature
            Text('Temperature: ${_temperature.toStringAsFixed(1)}'),
            Slider(
              value: _temperature,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              onChanged: (value) => setState(() => _temperature = value),
            ),
            const SizedBox(height: 12),

            // Max Tokens
            Text('Max Tokens: $_maxTokens'),
            Slider(
              value: _maxTokens.toDouble(),
              min: 50,
              max: 2048,
              divisions: 40,
              onChanged: (value) => setState(() => _maxTokens = value.round()),
            ),
            const SizedBox(height: 12),

            // Top P
            Text('Top P: ${_topP.toStringAsFixed(2)}'),
            Slider(
              value: _topP,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (value) => setState(() => _topP = value),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    widget.onSettingsChanged(_temperature, _maxTokens, _topP);
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
