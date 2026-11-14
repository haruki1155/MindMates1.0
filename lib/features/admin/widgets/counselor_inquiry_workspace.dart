import 'package:flutter/material.dart';

/// Presentation-only navigation for the existing Counselor inquiry workspace.
/// This does not modify message threads, submitted inquiries, or permissions.
enum CounselorInquirySection { messages, otherServices }

class CounselorInquiryWorkspace extends StatefulWidget {
  const CounselorInquiryWorkspace({
    super.key,
    required this.messages,
    required this.otherServices,
  });

  final Widget messages;
  final Widget otherServices;

  @override
  State<CounselorInquiryWorkspace> createState() =>
      _CounselorInquiryWorkspaceState();
}

class _CounselorInquiryWorkspaceState extends State<CounselorInquiryWorkspace> {
  CounselorInquirySection _section = CounselorInquirySection.messages;

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
          segments: const [
            ButtonSegment(
              value: CounselorInquirySection.messages,
              icon: Icon(Icons.forum_outlined),
              label: Text('Messages'),
            ),
            ButtonSegment(
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
