import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (status.toLowerCase()) {
      case 'paid':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1E40AF);
        label = 'Paid · awaiting shipment';
        icon = Icons.receipt_long_outlined;
        break;
      case 'shipped':
        bg = const Color(0xFFFFEDD5);
        fg = const Color(0xFF9A3412);
        label = 'Shipped';
        icon = Icons.local_shipping_outlined;
        break;
      case 'delivered':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF166534);
        label = 'Delivered';
        icon = Icons.task_alt_rounded;
        break;
      case 'sold':
        bg = const Color(0xFFF3F4F6);
        fg = const Color(0xFF4B5563);
        label = 'Sold';
        icon = Icons.shopping_bag_outlined;
        break;
      case 'cancelled':
        bg = const Color(0xFFF3F4F6);
        fg = const Color(0xFF4B5563);
        label = 'Cancelled';
        icon = Icons.cancel_outlined;
        break;
      case 'rejected':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF991B1B);
        label = 'Declined';
        icon = Icons.block_rounded;
        break;
      default:
        bg = const Color(0xFFF3F4F6);
        fg = const Color(0xFF374151);
        label = status.toUpperCase();
        icon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              fontFamily: 'Trebuchet MS',
            ),
          ),
        ],
      ),
    );
  }
}
