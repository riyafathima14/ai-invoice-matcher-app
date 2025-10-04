import 'package:flutter/material.dart';
import 'package:invoice_matcher/api_services/api_service.dart'; 

class ResultsCard extends StatelessWidget {
  final MatchResult? result;
  final GlobalKey resultsKey;

  const ResultsCard({
    super.key,
    required this.result,
    required this.resultsKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (result == null) {
      return const SizedBox.shrink(); 
    }

    final isLight = theme.brightness == Brightness.light;
    final isOverloadError = result!.status == 'TRY AGAIN';
    
    final resultColor = isOverloadError ? Colors.orange.shade700 : (result!.isMatch ? Colors.green.shade700 : Colors.red.shade700);
    final icon = isOverloadError ? Icons.refresh_rounded : (result!.isMatch ? Icons.check_circle_outline : Icons.warning_amber);
    
    final cardBackgroundColor = isLight 
        ? theme.colorScheme.surface 
        : resultColor.withOpacity(0.1); 
    
    final borderSideColor = resultColor;
    
    return Card(
      key: resultsKey,
      elevation: 8,
      color: cardBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderSideColor, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 36, color: resultColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'STATUS: ${result!.status}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: resultColor,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24, thickness: 1.5),
            Text(
              isOverloadError ? 'Service Interruption Summary:' : 'Comparison Summary:',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              result!.summary,
              style: theme.textTheme.bodyLarge,
            ),
            if (result!.details.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                isOverloadError ? 'Recommended Action:' : 'Verification Details:',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 8),
              ...result!.details.map((detail) => Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text('• $detail', style: theme.textTheme.bodyMedium),
              )),
            ]
          ],
        ),
      ),
    );
  }
}
