import 'package:flutter/material.dart';

import 'kotv_theme.dart';

class KotvNoticeBar extends StatelessWidget {
  const KotvNoticeBar({super.key, required this.message, this.onClose});

  final String message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(KotvTokens.cardRadius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
              child: Text(message, style: const TextStyle(fontSize: 14)),
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: '关闭',
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}
