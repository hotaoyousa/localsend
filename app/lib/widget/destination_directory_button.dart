import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/destination_directory_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Shows the same system directory used by the receiver, without persisting a
/// default path as a custom choice (which would stop following OS changes).
class DestinationDirectoryButton extends StatelessWidget {
  final String? destination;
  final VoidCallback onPressed;

  const DestinationDirectoryButton({required this.destination, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    Widget label(String value) => Text(
      checkPlatform([TargetPlatform.windows]) ? value.replaceAll('/', r'\') : value,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    );
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor: Theme.of(context).inputDecorationTheme.fillColor,
        shape: RoundedRectangleBorder(borderRadius: Theme.of(context).inputDecorationTheme.borderRadius),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: destination != null
            ? label(destination!)
            : context
                  .watch(defaultDestinationDirectoryProvider)
                  .when(
                    data: label,
                    loading: () => const Text('…'),
                    error: (_, _) => Text(t.general.error),
                  ),
      ),
    );
  }
}
