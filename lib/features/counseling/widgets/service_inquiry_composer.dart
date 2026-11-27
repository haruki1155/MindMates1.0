import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../models/student_inquiry_model.dart';
import '../../../repositories/inquiry_repository.dart';
import '../screens/services_screen.dart';
import '../screens/testing_service_inquiry_screen.dart';

/// Inquiry topics describe questions, never official availability or promises.
const serviceInquiryTopics = <String, List<String>>{
  'Information Service': [
    'Personal Field',
    'Psychological Field',
    'Social Field',
    'Educational Field',
    'Vocational Field',
  ],
  'Individual Inventory Service': [
    'Student Records',
    'Interview Requirements',
    'Required Forms',
    'Consent to Release Information',
  ],
  'Testing Service': [
    'Testing Process',
    'Testing Schedule',
    'Requirements',
    'Test Report',
  ],
  'Counseling Service': ['Counseling Process', 'Appointment Inquiry'],
  'Follow-up Service': [
    'Follow-up Process',
    'Adding, Changing & Dropping Subjects',
    'Shifting of Course',
  ],
  'Career Guidance and Placement Service': [
    'Career Planning',
    'Placement Assistance',
    'Signing of Clearance for Graduation',
  ],
  'Referral Service': ['Referral Process'],
};

String serviceInquiryDraft(String service, String topic) {
  if (service == 'Information Service') {
    final question = switch (topic) {
      'Personal Field' =>
        'what information and assistance PACC provides regarding personal concerns',
      'Psychological Field' =>
        'what information and guidance PACC provides in this area',
      'Social Field' =>
        'what information and support PACC provides regarding social adjustment and relationships',
      'Educational Field' =>
        'what educational information and guidance are available to students',
      'Vocational Field' =>
        'what vocational information and guidance PACC provides',
      _ => null,
    };
    if (question != null) {
      return 'Good day! I would like to inquire about Information Service, specifically the $topic. May I ask $question? Thank you!';
    }
  }
  return 'Good day! I would like to inquire about $service, specifically $topic. May I ask PACC for information and guidance about this topic? Thank you!';
}

/// Lets the user pick a PACC service and topic; returns that topic's fixed
/// inquiry text ([serviceInquiryDraft]), or null when dismissed.
Future<String?> showServiceInquiryPicker(
  BuildContext context, {
  String? initialService,
  Stream<List<StudentInquiryRecord>>? myInquiriesStream,
}) async {
  String? selectedService = initialService;
  final resolvedInquiriesStream = myInquiriesStream ??
      (Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser != null
          ? InquiryRepository().watchMyInquiries(
              FirebaseAuth.instance.currentUser!.uid,
            )
          : null);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, update) {
        final service = selectedService;
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  service == null
                      ? 'Select a PACC service'
                      : 'What do you want to know about $service?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: ListView(
                  key: ValueKey(service),
                  primary: false,
                  children: service == null
                      ? [
                          for (final item in ServicesScreen.services)
                            ListTile(
                              title: Text(item.title),
                              onTap: () =>
                                  update(() => selectedService = item.title),
                            ),
                        ]
                      : [
                          for (final topic in [
                            ...?serviceInquiryTopics[service],
                            'General Inquiry',
                          ])
                            ListTile(
                              title: Text(topic),
                              onTap: () => Navigator.pop(
                                sheetContext,
                                serviceInquiryDraft(service, topic),
                              ),
                            ),
                          if (service == 'Testing Service')
                            StreamBuilder<List<StudentInquiryRecord>>(
                              stream: resolvedInquiriesStream,
                              builder: (context, snapshot) {
                                final hasActive = (snapshot.data ?? const [])
                                    .any((inq) => inq.isActiveTestingService);
                                return ListTile(
                                  key: const ValueKey(
                                    'composer-testing-schedule-tile',
                                  ),
                                  enabled: !hasActive,
                                  leading: Icon(
                                    hasActive
                                        ? Icons.lock_clock_outlined
                                        : Icons.fact_check_outlined,
                                  ),
                                  title: Text(
                                    hasActive
                                        ? 'Testing Service Request Ongoing'
                                        : 'Request Testing Service Schedule',
                                  ),
                                  subtitle: Text(
                                    hasActive
                                        ? 'Wait until PACC marks your active schedule Completed before requesting again'
                                        : 'Students for OJT, Teaching & Non-Teaching employees',
                                  ),
                                  onTap: hasActive
                                      ? null
                                      : () {
                                          Navigator.pop(sheetContext);
                                          Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  const TestingServiceInquiryScreen(),
                                            ),
                                          );
                                        },
                                );
                              },
                            ),
                        ],
                ),
              ),
              SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (service != null)
                      TextButton(
                        onPressed: () => update(() => selectedService = null),
                        child: const Text('Back'),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Shares the existing chat controller and explicit send callback; no backend IO.
class ServiceInquiryComposer extends StatefulWidget {
  const ServiceInquiryComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
    this.sendBlocked = false,
  });

  final TextEditingController controller;
  final bool sending;
  final bool sendBlocked;
  final VoidCallback onSend;

  @override
  State<ServiceInquiryComposer> createState() => _ServiceInquiryComposerState();
}

class _ServiceInquiryComposerState extends State<ServiceInquiryComposer> {
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final service = ModalRoute.of(context)?.settings.arguments;
    if (service is String &&
        ServicesScreen.services.any((s) => s.title == service)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _select(service);
      });
    }
  }

  Future<void> _select([String? initialService]) async {
    FocusScope.of(context).unfocus();
    final draft = await showServiceInquiryPicker(
      context,
      initialService: initialService,
    );
    if (!mounted || draft == null || widget.sending) return;
    if (widget.controller.text.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace existing draft?'),
          content: const Text(
            'Your unsent message will be replaced with this inquiry.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep draft'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (!mounted || replace != true || widget.sending) return;
    }
    widget.controller.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: widget.sending ? null : _select,
            icon: const Icon(Icons.list_alt),
            label: const Text('Services'),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  readOnly: widget.sending,
                  maxLength: 1600,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Message a counselor',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.controller,
                builder: (context, value, _) => IconButton.filled(
                  tooltip: 'Send message',
                  onPressed:
                      widget.sending ||
                          widget.sendBlocked ||
                          value.text.trim().isEmpty ||
                          value.text.trim().length > 1600
                      ? null
                      : widget.onSend,
                  icon: widget.sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            semanticsLabel: 'Sending',
                          ),
                        )
                      : const Icon(Icons.send),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
