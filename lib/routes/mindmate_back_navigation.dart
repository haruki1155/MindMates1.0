import 'package:flutter/material.dart';
import 'route_names.dart';

/// Returns to the previous screen when possible. If a deep link or a
/// replaced route has no previous page, return to a safe in-app destination.
class MindMateBackNavigation {
  const MindMateBackNavigation._();

  static void backToHome(BuildContext context) =>
      _backOrReplace(context, RouteNames.home);

  static void backToMessages(BuildContext context) =>
      _backOrReplace(context, RouteNames.messages);

  static void _backOrReplace(BuildContext context, String fallback) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(fallback);
    }
  }
}
