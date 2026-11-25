import 'package:flutter/material.dart';

/// Presentation-only navigation for the existing Counselor inquiry workspace.
/// This does not modify message threads, submitted inquiries, or permissions.
enum CounselorInquirySection { messages, otherServices }

class CounselorInquiryWorkspace extends StatefulWidget {
  const CounselorInquiryWorkspace({
    super.key,
    required this.messages,
    required this.otherServices,
    this.initialSection = CounselorInquirySection.messages,
    this.messagesBadge,
  });

  final Widget messages;
  final Widget otherServices;
  final CounselorInquirySection initialSection;
  final Widget? messagesBadge;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<CounselorInquirySection>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: CounselorInquirySection.messages,
              icon: const Icon(Icons.forum_outlined),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Messages'),
                  if (widget.messagesBadge != null) widget.messagesBadge!,
                ],
              ),
            ),
            const ButtonSegment(
              value: CounselorInquirySection.otherServices,
              icon: Icon(Icons.support_agent_outlined),
              label: Text('Other services'),
            ),
          ],
          selected: {_section},
          onSelectionChanged: (selected) =>
              setState(() => _section = selected.single),
        ),
        const SizedBox(height: 16),
        if (_section == CounselorInquirySection.messages)
          SizedBox(height: panelHeight, child: widget.messages)
        else
          widget.otherServices,
      ],
    );
  }
}
