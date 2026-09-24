import 'package:flutter/material.dart';

const String mindMateTermsAndConditionsTitle = 'Terms and Conditions';

const String mindMateTermsAndConditions =
    '''The MindMate system provides psychological self-assessment, mental health information, counseling-related services, appointment scheduling, and other supportive digital tools for authorized users of the Psychological Assessment and Counseling Center (PACC).

Users accept the responsibility for providing, reviewing, and verifying the accuracy of the information they submit in MindMate. Incorrect or incomplete information may affect assessment results, counseling appointments, and other services provided through the system.

MindMate psychological assessments are intended for self-awareness and support purposes only and do not constitute an official psychological or medical diagnosis. The AI chatbot and Expression Check-In feature are supplementary tools and do not replace professional counseling, psychological assessment, medical treatment, or emergency services.

Users are responsible for using MindMate appropriately and respectfully. Content submitted through the Secret Chat must not contain harmful, abusive, threatening, discriminatory, or inappropriate material. Posts may be subject to moderation by authorized personnel.

By proceeding with the use of MindMate, I understand that I am giving my consent to the collection, processing, storage, and use of my personal and sensitive information for the purposes of providing psychological assessment, counseling-related services, and other functions of the system. I understand that my information will be handled in accordance with the Data Privacy Act of 2012 (Republic Act No. 10173), the Mental Health Act (Republic Act No. 11036), and applicable Urdaneta City University and PACC policies. I also understand that MindMate does not replace professional psychological or medical services. By selecting “I Agree,” I confirm that I have read, understood, and accepted these Terms and Conditions.''';

Future<bool> showMindMateTermsAndConditions(
  BuildContext context, {
  bool requireAcceptance = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: !requireAcceptance,
    builder: (_) =>
        _TermsAndConditionsDialog(requireAcceptance: requireAcceptance),
  );
  return result ?? false;
}

class _TermsAndConditionsDialog extends StatefulWidget {
  const _TermsAndConditionsDialog({required this.requireAcceptance});

  final bool requireAcceptance;

  @override
  State<_TermsAndConditionsDialog> createState() =>
      _TermsAndConditionsDialogState();
}

class _TermsAndConditionsDialogState extends State<_TermsAndConditionsDialog> {
  final ScrollController _scrollController = ScrollController();
  bool _hasReachedBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollProgress);
  }

  void _updateScrollProgress() {
    if (_hasReachedBottom || !_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter <= 8) {
      setState(() => _hasReachedBottom = true);
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateScrollProgress)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contentHeight = (MediaQuery.sizeOf(context).height * 0.52).clamp(
      240.0,
      390.0,
    );

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.gavel_outlined),
          SizedBox(width: 10),
          Expanded(child: Text(mindMateTermsAndConditionsTitle)),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: contentHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  key: const Key('terms-scroll-view'),
                  controller: _scrollController,
                  padding: const EdgeInsets.only(right: 14),
                  child: Text(
                    mindMateTermsAndConditions,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ),
            ),
            if (widget.requireAcceptance) ...[
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _hasReachedBottom
                    ? const Row(
                        key: Key('terms-ready-message'),
                        children: [
                          Icon(Icons.check_circle_outline, size: 18),
                          SizedBox(width: 7),
                          Expanded(
                            child: Text('You can now accept the terms.'),
                          ),
                        ],
                      )
                    : const Row(
                        key: Key('terms-scroll-message'),
                        children: [
                          Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                          SizedBox(width: 5),
                          Expanded(
                            child: Text('Scroll to the bottom to continue.'),
                          ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.requireAcceptance)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        FilledButton(
          key: Key(widget.requireAcceptance ? 'terms-agree' : 'terms-close'),
          onPressed: !widget.requireAcceptance || _hasReachedBottom
              ? () => Navigator.of(context).pop(widget.requireAcceptance)
              : null,
          child: Text(widget.requireAcceptance ? 'I Agree' : 'Close'),
        ),
      ],
    );
  }
}
