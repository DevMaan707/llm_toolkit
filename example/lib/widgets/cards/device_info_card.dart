import 'package:flutter/material.dart';
import '../../models/app_models.dart';

class DeviceInfoCard extends StatelessWidget {
  final DeviceInfo deviceInfo;

  const DeviceInfoCard({Key? key, required this.deviceInfo}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.blue.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade600, Colors.blue.shade700],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.phone_android_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Device Information',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      Text(
                        'System specifications and recommendations',
                        style: TextStyle(
                          color: Colors.blue.shade600,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow(
                        'Device',
                        '${deviceInfo.brand} ${deviceInfo.model}',
                        Icons.smartphone_rounded,
                      ),
                      const SizedBox(height: 6),
                      _buildInfoRow(
                        'Android',
                        '${deviceInfo.version} (API ${deviceInfo.sdkInt})',
                        Icons.android_rounded,
                      ),
                      const SizedBox(height: 6),
                      _buildInfoRow(
                        'Memory',
                        '${deviceInfo.availableMemoryMB}MB / ${deviceInfo.totalMemoryMB}MB',
                        Icons.memory_rounded,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: Colors.green.shade600,
                        size: 16,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        deviceInfo.memoryStatus,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                          fontSize: 8,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Recommended:\n${deviceInfo.recommendedQuantization}',
                        style: TextStyle(
                          color: Colors.green.shade600,
                          fontSize: 7,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 12, color: Colors.blue.shade600),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 11),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.blue.shade700,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: TextStyle(color: Colors.blue.shade600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
