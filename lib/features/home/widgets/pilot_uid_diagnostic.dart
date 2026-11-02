import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_environment.dart';

bool pilotDiagnosticEnabled({
  required bool debugBuild,
  required AppEnvironment environment,
}) => debugBuild && environment == AppEnvironment.staging;

String checkPilotUid(String? Function() readUid) {
  try {
    final uid = readUid();
    if (uid == null) return 'NOT_SIGNED_IN';
    return uid == 'mood-v2-pilot-student-001'
        ? 'PILOT_MATCH'
        : 'PILOT_MISMATCH';
  } catch (_) {
    return 'CHECK_FAILED';
  }
}

/// Local staging acceptance aid. No UID or credential is rendered or logged.
class PilotUidDiagnostic extends StatefulWidget {
  const PilotUidDiagnostic({super.key, this.readUid});

  @visibleForTesting
  final String? Function()? readUid;

  @override
  State<PilotUidDiagnostic> createState() => _PilotUidDiagnosticState();
}

class _PilotUidDiagnosticState extends State<PilotUidDiagnostic> {
  String? _outcome;

  @override
  Widget build(BuildContext context) {
    if (!pilotDiagnosticEnabled(
      debugBuild: kDebugMode,
      environment: AppEnvironmentConfig.current,
    )) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        OutlinedButton(
          onPressed: () => setState(() {
            _outcome = checkPilotUid(
              widget.readUid ?? () => FirebaseAuth.instance.currentUser?.uid,
            );
          }),
          child: const Text('Verify pilot session'),
        ),
        if (_outcome != null)
          Text(_outcome!, key: const ValueKey('pilot-uid-outcome')),
      ],
    );
  }
}
