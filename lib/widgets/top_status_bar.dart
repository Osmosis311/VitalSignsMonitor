import 'package:flutter/material.dart';

class TopStatusBar extends StatelessWidget {
  const TopStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeString = "${now.year}-${_2(now.month)}-${_2(now.day)} ${_2(now.hour)}:${_2(now.minute)}:${_2(now.second)}";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: const Color(0xFF3B7A6C), // Pale green/teal from the monitor image
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "BED 1  Adult  NO NAME",
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'EuroStyle',
              letterSpacing: 1,
            ),
          ),
          Row(
            children: [
              Text(
                timeString,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'EuroStyle',
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.battery_full, size: 20, color: Colors.white),
            ],
          ),
        ],
      ),
    );
  }

  String _2(int n) => n.toString().padLeft(2, '0');
}
