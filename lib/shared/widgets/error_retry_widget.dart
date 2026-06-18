import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'package:riskradar/shared/theme/app_colors.dart';

class ErrorRetryWidget extends StatelessWidget {
  const ErrorRetryWidget({super.key, required this.message, this.onRetry});

  static const String defaultMessage = 'Something went wrong.';
  static const String retryLabel = 'Retry';

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    R.init(context);
    final Color textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.shade200
        : Colors.grey.shade700;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(R.blockH * 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Colors.red.shade700,
              size: 56,
            ),
            SizedBox(height: R.blockV * 2),
            Text(
              message.isEmpty ? defaultMessage : message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: R.blockH * 3.75,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: R.blockV * 2.5),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: Icon(Icons.refresh_rounded),
                label: Text(retryLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandTeal,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
