import 'package:flutter/material.dart';

class SnackUtils {
  /// Shows a unified SnackBar with consistent design and behavior:
  /// - [success] = true: Green background (representing success/info)
  /// - [success] = false: Red background (representing error/failure)
  static void show(
    BuildContext context,
    String message, {
    bool success = true,
    String? actionLabel,
    VoidCallback? onActionPressed,
  }) {
    if (!context.mounted) return;

    // Instantly dismiss any current SnackBars so the new one appears immediately
    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: success ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        action: actionLabel != null && onActionPressed != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onActionPressed,
              )
            : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
