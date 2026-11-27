import 'package:flutter/material.dart';

/// Presentation-only navigation for the existing Counselor inquiry workspace.
/// This does not modify message threads, submitted inquiries, or permissions.
enum CounselorInquirySection { messages, otherServices, testingService }

class CounselorInquiryWorkspace extends StatefulWidget {
  const CounselorInquiryWorkspace({
    super.key,
    required this.messages,
    required this.otherServices,
    this.testingService,
    this.initialSection = CounselorInquirySection.messages,
    this.messagesBadge,
    this.otherServicesBadge,
    this.testingServiceBadge,
  });

  final Widget messages;
  final Widget otherServices;
  final Widget? testingService;
  final CounselorInquirySection initialSection;
  final Widget? messagesBadge;
  final Widget? otherServicesBadge;
  final Widget? testingServiceBadge;

  @override
  State<CounselorInquiryWorkspace> createState() =>
      _CounselorInquiryWorkspaceState();
}

class _CounselorInquiryWorkspaceState extends State<CounselorInquiryWorkspace> {
  late CounselorInquirySection _section;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
  }

  @override
  Widget build(BuildContext context) {
    final panelHeight = (MediaQuery.sizeOf(context).height - 250)
        .clamp(520.0, 920.0)
        .toDouble();
    final effectiveSection =
        (_section == CounselorInquirySection.testingService &&
            widget.testingService == null)
        ? CounselorInquirySection.otherServices
        : _section;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<CounselorInquirySection>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: CounselorInquirySection.messages,
                icon: const Icon(Icons.forum_outlined),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Flexible(
                      child: Text(
                        'Messages',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.messagesBadge != null) widget.messagesBadge!,
                  ],
                ),
              ),
              ButtonSegment(
                value: CounselorInquirySection.otherServices,
                icon: const Icon(Icons.support_agent_outlined),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Flexible(
                      child: Text(
                        'Other services',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.otherServicesBadge != null)
                      widget.otherServicesBadge!,
                  ],
                ),
              ),
              if (widget.testingService != null)
                ButtonSegment(
                  value: CounselorInquirySection.testingService,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Flexible(
                        child: Text(
                          'Testing Service',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.testingServiceBadge != null)
                        widget.testingServiceBadge!,
                    ],
                  ),
                ),
            ],
            selected: {effectiveSection},
            onSelectionChanged: (selected) =>
                setState(() => _section = selected.single),
          ),
        ),
        const SizedBox(height: 16),
        if (effectiveSection == CounselorInquirySection.messages)
          SizedBox(height: panelHeight, child: widget.messages)
        else if (effectiveSection == CounselorInquirySection.testingService &&
            widget.testingService != null)
          widget.testingService!
        else
          widget.otherServices,
      ],
    );
  }
}
