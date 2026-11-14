import 'package:flutter/material.dart';

/// Confirmation shown before copying share URIs or subscription URLs that may
/// contain credentials, UUIDs, passwords, or access tokens.
Future<bool> confirmSensitiveCopy(
  BuildContext context, {
  required String subject,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('لینک شامل اطلاعات دسترسی است'),
      content: Text(
        '$subject ممکن است حاوی UUID، رمز یا توکن دسترسی باشد. '
        'فقط در برنامه یا دستگاه مطمئن استفاده کن و آن را عمومی منتشر نکن.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('ادامه و کپی'),
        ),
      ],
    ),
  );
  return result == true;
}
