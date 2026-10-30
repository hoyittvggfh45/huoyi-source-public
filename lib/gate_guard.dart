import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gate_service.dart';

const authConsoleDefine = bool.fromEnvironment('AUTH_CONSOLE');

bool get gateConsoleVisible =>
    Platform.isAndroid && authConsoleDefine && appFlavor == 'auth';

class GateGuard extends StatelessWidget {
  const GateGuard({
    super.key,
    this.feature,
    this.module,
    this.regionSensitive = false,
    this.fallback = const SizedBox.shrink(),
    required this.child,
  });

  final String? feature;
  final String? module;
  final bool regionSensitive;
  final Widget fallback;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: GateService.instance,
    builder: (context, _) {
      final service = GateService.instance;
      if (feature != null && !service.isFeatureEnabled(feature!)) {
        return fallback;
      }
      if (module != null && !service.isModuleEnabled(module!)) {
        return fallback;
      }
      if (regionSensitive && !service.regionAllowed) {
        return fallback;
      }
      return child;
    },
  );
}
