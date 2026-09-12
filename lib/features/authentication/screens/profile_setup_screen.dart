import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../providers/user_provider.dart';
import '../../../routes/route_names.dart';

typedef ProfileImagePicker = Future<ProfileSetupImage?> Function();

class ProfileSetupImage {
  const ProfileSetupImage({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, this.imagePicker});

  final ProfileImagePicker? imagePicker;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  Uint8List? _image;
  String _contentType = 'image/jpeg';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _firstName = TextEditingController(
      text: context.read<UserProvider>().user?.firstName ?? '',
    );
  }

  @override
  void dispose() {
    _firstName.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final selected = widget.imagePicker != null
          ? await widget.imagePicker!()
          : await _pickGalleryImage();
      if (selected == null || !mounted) return;
      if (selected.bytes.isEmpty) {
        _showMessage('The selected photo is empty. Please choose another one.');
        return;
      }
      if (selected.bytes.length > 5 * 1024 * 1024) {
        _showMessage('Choose an image smaller than 5 MB.');
        return;
      }
      setState(() {
        _image = selected.bytes;
        _contentType = selected.contentType;
      });
    } on FormatException catch (error) {
      if (mounted) _showMessage(error.message.toString());
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to open your photos. Check photo permissions and try again.',
        );
      }
    }
  }

  Future<ProfileSetupImage?> _pickGalleryImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) return null;

    final name = picked.name.toLowerCase();
    final reportedType = picked.mimeType?.toLowerCase();
    final contentType = reportedType == 'image/png' || name.endsWith('.png')
        ? 'image/png'
        : reportedType == 'image/jpeg' ||
              name.endsWith('.jpg') ||
              name.endsWith('.jpeg')
        ? 'image/jpeg'
        : null;
    if (contentType == null) {
      throw const FormatException('Only JPG and PNG photos are supported.');
    }

    return ProfileSetupImage(
      bytes: await picked.readAsBytes(),
      contentType: contentType,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final provider = context.read<UserProvider>();
    final user = provider.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your profile could not be loaded. Please sign in again.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final firstName = _firstName.text.trim();
      final updated = user.copyWith(
        firstName: firstName,
        name: firstName,
        profileSetupCompleted: true,
      );
      if (!await provider.updateProfile(updated)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                provider.errorMessage ?? 'Unable to save your profile.',
              ),
            ),
          );
        }
        return;
      }
      var photoUploadFailed = false;
      if (_image != null) {
        photoUploadFailed = !await provider.uploadProfileImage(
          user.id,
          _image!,
          contentType: _contentType,
        );
      }
      if (mounted) {
        if (photoUploadFailed) {
          _showMessage(
            'Your profile was saved, but the photo could not be uploaded. You can add it later from Profile.',
          );
        }
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(RouteNames.onboarding, (_) => false);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Colors.background,
      body: SafeArea(
        child: Stack(
          children: [
            const _SoftCircle(top: -82, left: -72, size: 190),
            const _SoftCircle(bottom: -100, right: -80, size: 220, green: true),
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  24,
                  28,
                  24,
                  28 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 56,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Header(),
                          const SizedBox(height: 24),
                          _ProfileCard(
                            formKey: _formKey,
                            controller: _firstName,
                            image: _image,
                            saving: _saving,
                            onPickImage: _pickImage,
                            onSave: _save,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _StepPill(),
        SizedBox(height: 14),
        Text(
          'Make MindMate yours',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _Colors.text,
            fontSize: 29,
            height: 1.08,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Add the details you want people to recognize you by.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _Colors.muted,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _Colors.accent,
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Text(
        'STEP 2 OF 2',
        style: TextStyle(
          color: _Colors.text,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.formKey,
    required this.controller,
    required this.image,
    required this.saving,
    required this.onPickImage,
    required this.onSave,
  });
  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final Uint8List? image;
  final bool saving;
  final VoidCallback onPickImage;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _Colors.border),
        boxShadow: [
          BoxShadow(
            color: _Colors.shadow.withAlpha(18),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PhotoPicker(image: image, onTap: saving ? null : onPickImage),
            const SizedBox(height: 26),
            const Text(
              'What should we call you?',
              style: TextStyle(
                color: _Colors.text,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'We’ll use your first name throughout the app.',
              style: TextStyle(
                color: _Colors.muted,
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 13),
            TextFormField(
              controller: controller,
              enabled: !saving,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.givenName],
              onFieldSubmitted: (_) {
                if (!saving) onSave();
              },
              style: const TextStyle(
                color: _Colors.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                labelText: 'First name',
                hintText: 'Enter your first name',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                filled: true,
                fillColor: _Colors.fieldSurface,
                border: _fieldBorder,
                enabledBorder: _fieldBorder,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'First name is required'
                  : null,
            ),
            const SizedBox(height: 14),
            const _NameInfo(),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.arrow_forward_rounded, size: 19),
                label: Text(
                  saving ? 'Saving profile...' : 'Continue to MindMate',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withAlpha(110),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({required this.image, required this.onTap});
  final Uint8List? image;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          button: true,
          label: image == null ? 'Add profile photo' : 'Change profile photo',
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withAlpha(80),
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    backgroundColor: const Color(0xFFEAF6F2),
                    backgroundImage: image == null ? null : MemoryImage(image!),
                    child: image == null
                        ? const Icon(
                            Icons.person_rounded,
                            size: 48,
                            color: AppColors.primary,
                          )
                        : null,
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: 3,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _Colors.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Icon(
                      image == null
                          ? Icons.add_a_photo_rounded
                          : Icons.edit_rounded,
                      size: 16,
                      color: _Colors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 11),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: Text(
            image == null ? 'Add a photo (optional)' : 'Change photo',
          ),
        ),
      ],
    );
  }
}

class _NameInfo extends StatelessWidget {
  const _NameInfo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5D8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 18, color: Color(0xFF8A6510)),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Your display name is set automatically from this first name.',
              style: TextStyle(
                color: Color(0xFF725715),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftCircle extends StatelessWidget {
  const _SoftCircle({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.size,
    this.green = false,
  });
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final double size;
  final bool green;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (green ? AppColors.primary : _Colors.accent).withAlpha(32),
          ),
        ),
      ),
    );
  }
}

final _fieldBorder = OutlineInputBorder(
  borderRadius: BorderRadius.circular(15),
  borderSide: const BorderSide(color: _Colors.border),
);

class _Colors {
  const _Colors._();
  static const background = Color(0xFFFFFCF4);
  static const accent = Color(0xFFFFC944);
  static const fieldSurface = Color(0xFFFAFCFB);
  static const border = Color(0xFFECE3D1);
  static const text = Color(0xFF17201D);
  static const muted = Color(0xFF687571);
  static const shadow = Color(0xFF4B3A12);
}
