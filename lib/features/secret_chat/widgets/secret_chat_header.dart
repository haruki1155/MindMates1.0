import 'package:flutter/material.dart';

import '../../../models/secret_chat_model.dart';
import 'secret_chat_background.dart';

class SecretChatHeaderDelegate extends SliverPersistentHeaderDelegate {
  SecretChatHeaderDelegate({
    required this.selectedFilter,
    required this.savedCount,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onFilterChanged,
    this.onProfile,
  });

  final SecretChatFilter selectedFilter;
  final int savedCount;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<SecretChatFilter> onFilterChanged;
  final VoidCallback? onProfile;

  @override
  double get minExtent => 144;

  @override
  double get maxExtent => 144;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      elevation: overlapsContent || shrinkOffset > 0 ? 8 : 4,
      shadowColor: const Color(0x33000000),
      color: SecretChatPalette.sun,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _SearchField(
                    initialValue: searchQuery,
                    onChanged: onSearchChanged,
                  ),
                ),
                const SizedBox(width: 14),
                _HeaderIconButton(
                  icon: Icons.person_outline_rounded,
                  tooltip: 'Secret Chat profile',
                  onTap:
                      onProfile ??
                      () => onFilterChanged(SecretChatFilter.saved),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FilterChipButton(
                  label: 'Popular',
                  isSelected: selectedFilter == SecretChatFilter.popular,
                  onTap: () => onFilterChanged(SecretChatFilter.popular),
                ),
                const SizedBox(width: 10),
                _FilterChipButton(
                  label: 'My post',
                  isSelected: selectedFilter == SecretChatFilter.mine,
                  onTap: () => onFilterChanged(SecretChatFilter.mine),
                ),
                const SizedBox(width: 10),
                _FilterChipButton(
                  label: 'Saved ($savedCount)',
                  isSelected: selectedFilter == SecretChatFilter.saved,
                  onTap: () => onFilterChanged(SecretChatFilter.saved),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SecretChatHeaderDelegate oldDelegate) {
    return oldDelegate.selectedFilter != selectedFilter ||
        oldDelegate.savedCount != savedCount ||
        oldDelegate.searchQuery != searchQuery;
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.initialValue, required this.onChanged});

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search thoughts...',
          hintStyle: const TextStyle(
            color: SecretChatPalette.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: Colors.white, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: const Color(0x33000000),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, color: SecretChatPalette.text, size: 24),
          ),
        ),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 170),
      scale: isSelected ? 1.04 : 1,
      child: Material(
        color: isSelected ? SecretChatPalette.text : Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: 3,
        shadowColor: const Color(0x22000000),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? Colors.white : SecretChatPalette.text,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
