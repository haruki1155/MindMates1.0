import 'package:flutter/material.dart';

import '../../../models/secret_chat_model.dart';
import '../domain/secret_chat_safety_validator.dart';
import '../screens/secret_chat_screen.dart';
import 'secret_chat_background.dart';

class SecretChatComposeSheet extends StatefulWidget {
  const SecretChatComposeSheet({
    super.key,
    required this.categories,
    required this.onSubmit,
  });

  final List<SecretChatCategory> categories;
  final CreateSecretPost onSubmit;

  @override
  State<SecretChatComposeSheet> createState() => _SecretChatComposeSheetState();
}

class _SecretChatComposeSheetState extends State<SecretChatComposeSheet> {
  final _controller = TextEditingController();
  final _validator = const SecretChatSafetyValidator();
  final List<String> _selectedCategories = [];
  bool _isSubmitting = false;
  SecretChatValidationResult? _validation;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE4D9B8),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Share anonymously',
                    style: TextStyle(
                      color: SecretChatPalette.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Community language guidelines',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Community language'),
                      content: const Text(forumLanguageGuideline),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Your post appears without your name and is filtered for mental health and wellbeing only.',
              style: TextStyle(
                color: SecretChatPalette.muted,
                fontSize: 12,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in widget.categories)
                  FilterChip(
                    label: Text(category.label),
                    selected: _selectedCategories.contains(category.label),
                    selectedColor: category.color.withAlpha(115),
                    onSelected: (selected) {
                      if (selected && _selectedCategories.length == 3) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('You can choose up to 3 categories.'),
                          ),
                        );
                        return;
                      }
                      setState(() {
                        if (selected) {
                          _selectedCategories.add(category.label);
                        } else {
                          _selectedCategories.remove(category.label);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 7,
              maxLength: SecretChatSafetyValidator.postMaxLength,
              onChanged: (value) {
                if (value.trim().isEmpty) {
                  setState(() => _validation = null);
                  return;
                }
                setState(() => _validation = _validator.validatePost(value));
              },
              decoration: InputDecoration(
                hintText: 'What would you like to share?',
                filled: true,
                fillColor: SecretChatPalette.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_validation != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _validation!.message,
                  style: TextStyle(
                    color: _validation!.isAllowed
                        ? const Color(0xFF167A56)
                        : const Color(0xFFB45309),
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed:
                    _isSubmitting ||
                        _validation?.code ==
                            SecretChatValidationCode.inappropriateLanguage
                    ? null
                    : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('Post anonymously'),
                style: FilledButton.styleFrom(
                  backgroundColor: SecretChatPalette.sun,
                  foregroundColor: SecretChatPalette.text,
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final message = _controller.text.trim();
    if (message.isEmpty) return;
    if (_selectedCategories.isEmpty) {
      setState(
        () => _validation = const SecretChatValidationResult(
          code: SecretChatValidationCode.offTopic,
          message: 'Choose at least one category.',
        ),
      );
      return;
    }
    final validation = _validator.validatePost(message);
    if (!validation.isAllowed) {
      setState(() => _validation = validation);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // Wait for the server so a moderation refusal keeps the draft here.
      await widget.onSubmit(
        message: message,
        categories: List.unmodifiable(_selectedCategories),
      );
      if (mounted) Navigator.of(context).pop();
    } on SecretChatValidationException catch (error) {
      if (mounted) setState(() => _validation = error.result);
    } catch (_) {
      if (mounted) {
        setState(
          () => _validation = const SecretChatValidationResult(
            code: SecretChatValidationCode.unsafe,
            message: 'Unable to post right now. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
