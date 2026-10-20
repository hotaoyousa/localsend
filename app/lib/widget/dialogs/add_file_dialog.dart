import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/big_button.dart';
import 'package:localsend_app/widget/dialogs/custom_bottom_sheet.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class AddFileDialog extends StatelessWidget {
  final List<FilePickerOption> options;

  const AddFileDialog({required this.options});

  static Future<void> open({required BuildContext context, required List<FilePickerOption> options}) async {
    if (checkPlatformIsDesktop()) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(t.dialogs.addFile.title),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.dialogs.addFile.content),
                  const SizedBox(height: 20),
                  AddFileDialog(options: options),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                context.pop();
              },
              child: Text(t.general.close),
            ),
          ],
        ),
      );
    } else {
      await context.pushBottomSheet(
        () => CustomBottomSheet(
          title: t.dialogs.addFile.title,
          description: t.dialogs.addFile.content,
          child: AddFileDialog(options: options),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget button(FilePickerOption option, {double? width}) => BigButton(
      icon: option.icon,
      label: option.label,
      width: width,
      filled: true,
      onTap: () async {
        final ref = context.ref;
        await ref.global.dispatchAsync(PickFileAction(option: option, context: context));
        ref.global.dispatch(NavigateAction.popUntilRoot());
      },
    );
    if (checkPlatformIsDesktop()) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 15),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: button(options[i], width: double.infinity)),
                const SizedBox(width: 15),
                Expanded(child: i + 1 < options.length ? button(options[i + 1], width: double.infinity) : const SizedBox.shrink()),
              ],
            ),
          ],
        ],
      );
    }
    return Wrap(spacing: 15, runSpacing: 15, children: options.map((option) => button(option)).toList());
  }
}
