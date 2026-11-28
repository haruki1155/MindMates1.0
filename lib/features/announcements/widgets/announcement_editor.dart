import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../../../models/profile_roles.dart';
import '../../admin/theme/admin_theme.dart';
import 'announcement_presentation.dart';
import '../../../services/firebase/firebase_error_message.dart';
import '../data/announcement_repository.dart';
import '../models/announcement.dart';

class AnnouncementEditor extends StatefulWidget {
  const AnnouncementEditor({
    super.key,
    required this.repository,
    this.announcement,
  });
  final AnnouncementRepository repository;
  final Announcement? announcement;
  @override
  State<AnnouncementEditor> createState() => _AnnouncementEditorState();
}

class _AnnouncementEditorState extends State<AnnouncementEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _body, _source, _image;
  late AnnouncementKind _kind;
  late AnnouncementPostType _postType;
  late AnnouncementMediaType _mediaType;
  late Set<PopulationRole> _audience;
  AnnouncementCategory? _category;
  bool _saving = false, _previewing = false, _audienceError = false;
  String? _notice, _error;

  /// The preview server allows 10 requests/minute, so URL edits are debounced.
  static const _previewDebounce = Duration(milliseconds: 650);
  Timer? _debounce;
  String? _lastFetchedUrl;
  int _previewRequest = 0;

  /// Last value a preview wrote per field; a field whose text differs was edited by the publisher.
  final _autoFilled = <TextEditingController, String>{};
  @override
  void initState() {
    super.initState();
    final post = widget.announcement?.content;
    _title = TextEditingController(text: post?.title);
    _body = TextEditingController(text: post?.body);
    _source = TextEditingController(text: post?.sourceUrl);
    _image = TextEditingController(text: post?.imageUrl);
    _kind = post?.kind ?? AnnouncementKind.original;
    _postType = post?.postType ?? AnnouncementPostType.announcement;
    _mediaType = post?.mediaType ?? AnnouncementMediaType.standard;
    _audience = {...(post?.audienceRoles ?? PopulationRole.values)};
    _category = post?.category;
    // Existing posts already have their details; don't spend a preview request on open.
    if (post != null && post.sourceUrl.trim().isNotEmpty) {
      _lastFetchedUrl = post.sourceUrl.trim();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final controller in [_title, _body, _source, _image]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _sourceChanged(String value) {
    _debounce?.cancel();
    final url = value.trim();
    if (_kind == AnnouncementKind.link &&
        announcementHttpUri(url) != null &&
        url != _lastFetchedUrl) {
      _debounce = Timer(_previewDebounce, () => _preview(automatic: true));
    }
    setState(() {});
  }

  bool _canFill(TextEditingController field) =>
      field.text.trim().isEmpty || _autoFilled[field] == field.text;

  void _fill(TextEditingController field, String value) {
    if (value.isEmpty || !_canFill(field)) return;
    field.text = value;
    _autoFilled[field] = value;
  }

  Future<void> _preview({bool automatic = false}) async {
    _debounce?.cancel();
    final url = _source.text.trim();
    if (announcementHttpUri(url) == null) {
      if (!automatic) {
        setState(() => _error = 'Enter a valid http or https source link.');
      }
      return;
    }
    if (automatic && url == _lastFetchedUrl) return;
    _lastFetchedUrl = url;
    final request = ++_previewRequest;
    setState(() {
      _previewing = true;
      _error = null;
      _notice = null;
    });
    bool current() =>
        mounted &&
        request == _previewRequest &&
        _source.text.trim() == url &&
        _kind == AnnouncementKind.link;
    try {
      final preview = await widget.repository.previewLink(url);
      if (!current()) return;
      setState(() {
        _fill(_title, preview.title);
        _fill(_body, preview.description);
        _fill(_image, preview.imageUrl);
        _notice = preview.available
            ? 'Preview loaded. Review and edit before publishing. Your edits were kept.'
            : 'Preview unavailable. Enter the details manually.';
      });
    } catch (error) {
      if (current()) {
        final limited =
            error is FirebaseException && error.code == 'resource-exhausted';
        setState(
          () => _notice = limited
              ? 'Too many preview requests. Wait a minute and tap Load preview, or enter the details manually.'
              : 'Preview unavailable. Enter the details manually.',
        );
      }
    } finally {
      if (mounted && request == _previewRequest) {
        setState(() => _previewing = false);
      }
    }
  }

  void _selectKind(AnnouncementKind kind) => setState(() {
    _kind = kind;
    _notice = null;
    if (kind == AnnouncementKind.original) {
      _debounce?.cancel();
      _mediaType = AnnouncementMediaType.standard;
    }
  });

  Future<void> _save(AnnouncementAction action) async {
    // Saving never waits on, or races with, a link preview.
    _debounce?.cancel();
    _previewRequest++;
    _previewing = false;
    final formValid = _form.currentState!.validate();
    setState(() => _audienceError = _audience.isEmpty);
    if (!formValid || _audience.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.save(
        id: widget.announcement?.id,
        expectedRevision: widget.announcement?.revision ?? 0,
        action: action,
        post: AnnouncementInput(
          kind: _kind,
          postType: _postType,
          audienceRoles: canonicalAudienceRoles(_audience),
          mediaType: _kind == AnnouncementKind.link
              ? _mediaType
              : AnnouncementMediaType.standard,
          category: _category,
          title: _title.text,
          body: _body.text,
          sourceUrl: _source.text,
          imageUrl: _image.text,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to save. ${FirebaseErrorMessage.describe(error, fallback: 'Please retry. If this post changed, reopen it before saving.')}',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggleAudience(PopulationRole role) {
    if (_saving) return;
    setState(() {
      if (_audience.contains(role)) {
        _audience.remove(role);
      } else {
        _audience.add(role);
      }
      if (_audience.isNotEmpty) _audienceError = false;
    });
  }

  Widget _editorSection({
    required String step,
    required String title,
    required String description,
    required List<Widget> children,
  }) => Card(
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AdminColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AdminColors.accentFaint,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  step,
                  style: const TextStyle(
                    color: AdminColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AdminColors.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: AdminColors.muted,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    ),
  );

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        color: AdminColors.ink,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _selectionGrid({
    required int maxColumns,
    required List<Widget> Function(double width) buildPanels,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 12.0;
      const minPanelWidth = 220.0;
      final availableWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : minPanelWidth * maxColumns;
      final columns = (availableWidth / (minPanelWidth + gap))
          .floor()
          .clamp(1, maxColumns)
          .toInt();
      final panelWidth = (availableWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: buildPanels(panelWidth),
      );
    },
  );

  Widget _selectionPanel({
    required double width,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final radius = BorderRadius.circular(14);
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: selected,
        label: '$title, $subtitle',
        child: Opacity(
          opacity: enabled ? 1 : 0.6,
          child: Material(
            type: MaterialType.transparency,
            borderRadius: radius,
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: radius,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                constraints: const BoxConstraints(minHeight: 100),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: selected
                      ? AdminColors.accentFaint
                      : AdminColors.surface,
                  borderRadius: radius,
                  border: Border.all(
                    color: selected
                        ? AdminColors.accentStrong
                        : AdminColors.border,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? AdminColors.accentSoft
                            : AdminColors.surfaceMuted,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 22, color: AdminColors.ink),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: AdminColors.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: AdminColors.muted,
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      size: 22,
                      color: selected
                          ? AdminColors.accentStrong
                          : AdminColors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _audienceDescription(PopulationRole role) => switch (role) {
    PopulationRole.student => 'Student app users',
    PopulationRole.teaching => 'Teaching personnel',
    PopulationRole.nonTeaching => 'Non-Teaching personnel',
  };

  @override
  Widget build(BuildContext context) {
    final baseTheme = AdminTheme.data;
    final editorTheme = baseTheme.copyWith(
      visualDensity: VisualDensity.standard,
      textTheme: baseTheme.textTheme.copyWith(
        bodyLarge: baseTheme.textTheme.bodyLarge?.copyWith(fontSize: 16),
        bodyMedium: baseTheme.textTheme.bodyMedium?.copyWith(fontSize: 15),
        bodySmall: baseTheme.textTheme.bodySmall?.copyWith(fontSize: 14),
        titleMedium: baseTheme.textTheme.titleMedium?.copyWith(fontSize: 18),
        labelLarge: baseTheme.textTheme.labelLarge?.copyWith(fontSize: 15),
        labelMedium: baseTheme.textTheme.labelMedium?.copyWith(fontSize: 14),
      ),
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        labelStyle: const TextStyle(
          color: AdminColors.muted,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        helperStyle: const TextStyle(
          color: AdminColors.muted,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      chipTheme: baseTheme.chipTheme.copyWith(
        labelStyle: const TextStyle(
          color: AdminColors.ink,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
    return Theme(
      data: editorTheme,
      child: Builder(builder: (context) => _buildEditor(context)),
    );
  }

  Widget _buildEditor(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.announcement == null
              ? 'New announcement'
              : 'Edit announcement',
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Share an update',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineLarge?.copyWith(fontSize: 32),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose who should see this post, then add clear details for your audience.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 28),
                    _editorSection(
                      step: '1',
                      title: 'Publishing options',
                      description:
                          'Choose a post type, audience, and source format.',
                      children: [
                        _fieldLabel('Post type'),
                        _selectionGrid(
                          maxColumns: 2,
                          buildPanels: (width) => [
                            for (final type in AnnouncementPostType.values)
                              _selectionPanel(
                                width: width,
                                title: type.label,
                                subtitle:
                                    type == AnnouncementPostType.announcement
                                    ? 'Share a specific announcement or update.'
                                    : 'Share helpful or general information.',
                                icon: type == AnnouncementPostType.announcement
                                    ? Icons.campaign_outlined
                                    : Icons.info_outline,
                                selected: _postType == type,
                                enabled: !_saving,
                                onTap: () => setState(() => _postType = type),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _fieldLabel('Audience'),
                        Text(
                          'Select one or more groups. People see posts addressed to their role.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        _selectionGrid(
                          maxColumns: 3,
                          buildPanels: (width) => [
                            for (final role in PopulationRole.values)
                              _selectionPanel(
                                width: width,
                                title: role.label,
                                subtitle: _audienceDescription(role),
                                icon: switch (role) {
                                  PopulationRole.student =>
                                    Icons.school_outlined,
                                  PopulationRole.teaching =>
                                    Icons.cast_for_education_outlined,
                                  PopulationRole.nonTeaching =>
                                    Icons.work_outline,
                                },
                                selected: _audience.contains(role),
                                enabled: !_saving,
                                onTap: () => _toggleAudience(role),
                              ),
                          ],
                        ),
                        if (_audienceError) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 18,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Select at least one audience.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),
                        _fieldLabel('Post source'),
                        Text(
                          'Write an original post or link to an existing source.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final kind in AnnouncementKind.values)
                              ChoiceChip(
                                label: Text(
                                  kind == AnnouncementKind.original
                                      ? 'Original post'
                                      : 'Linked post',
                                ),
                                selected: _kind == kind,
                                onSelected: _saving
                                    ? null
                                    : (_) => _selectKind(kind),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _fieldLabel('Media'),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final media in AnnouncementMediaType.values)
                              ChoiceChip(
                                label: Text(
                                  media == AnnouncementMediaType.video
                                      ? 'Video'
                                      : 'Standard',
                                ),
                                selected:
                                    _kind == AnnouncementKind.link &&
                                        _mediaType == media ||
                                    _kind == AnnouncementKind.original &&
                                        media == AnnouncementMediaType.standard,
                                onSelected: _saving
                                    ? null
                                    : (_) => setState(() {
                                        _mediaType = media;
                                        if (media ==
                                            AnnouncementMediaType.video) {
                                          _kind = AnnouncementKind.link;
                                        }
                                      }),
                              ),
                          ],
                        ),
                        if (_kind == AnnouncementKind.link) ...[
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _source,
                            onChanged: _sourceChanged,
                            enabled: !_saving,
                            keyboardType: TextInputType.url,
                            style: Theme.of(context).textTheme.bodyLarge,
                            decoration: InputDecoration(
                              labelText: 'Source link',
                              helperText:
                                  _mediaType == AnnouncementMediaType.video
                                  ? 'Paste the video link. App users tap Watch Video to open it.'
                                  : 'App users open this original post when they tap.',
                            ),
                            maxLength: 2048,
                            validator: (v) => announcementHttpUri(v) == null
                                ? 'Enter a valid http or https link.'
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _previewing || _saving
                                    ? null
                                    : _preview,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                ),
                                icon: _previewing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.link),
                                label: Text(
                                  _previewing
                                      ? 'Loading preview…'
                                      : 'Load preview',
                                ),
                              ),
                              if (announcementHttpUri(_source.text) != null)
                                Text(
                                  'Destination: ${announcementHttpUri(_source.text)!.host}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                            ],
                          ),
                        ],
                        AnimatedSwitcher(
                          duration: announcementTransitionDuration(context),
                          child: _notice == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: AnnouncementStatusPanel(
                                    key: ValueKey(_notice),
                                    icon: Icons.info_outline,
                                    title: 'Link preview',
                                    message: _notice!,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _editorSection(
                      step: '2',
                      title: 'Announcement content',
                      description:
                          'Write a clear title and description. Add an image URL if you have a cover image.',
                      children: [
                        TextFormField(
                          controller: _title,
                          enabled: !_saving,
                          style: Theme.of(context).textTheme.bodyLarge,
                          decoration: const InputDecoration(
                            labelText: 'Title',
                            helperText:
                                'Use a short headline that tells readers what the post is about.',
                          ),
                          maxLength: 160,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter a title.'
                              : null,
                        ),
                        const SizedBox(height: 22),
                        TextFormField(
                          controller: _body,
                          enabled: !_saving,
                          style: Theme.of(context).textTheme.bodyLarge,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            alignLabelWithHint: true,
                            helperText:
                                'Add the details, dates, or next steps readers need.',
                          ),
                          minLines: 5,
                          maxLines: 12,
                          maxLength: 10000,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter a description.'
                              : null,
                        ),
                        const SizedBox(height: 22),
                        TextFormField(
                          controller: _image,
                          enabled: !_saving,
                          keyboardType: TextInputType.url,
                          style: Theme.of(context).textTheme.bodyLarge,
                          decoration: InputDecoration(
                            labelText: 'Image URL (optional)',
                            helperText:
                                _kind == AnnouncementKind.link &&
                                    _mediaType == AnnouncementMediaType.video
                                ? 'Use an image URL for the video thumbnail.'
                                : 'Paste a link to the image used with this post.',
                          ),
                          maxLength: 2048,
                          onChanged: (_) => setState(() {}),
                          validator: (v) =>
                              v != null &&
                                  v.trim().isNotEmpty &&
                                  announcementHttpUri(v) == null
                              ? 'Enter a valid image URL.'
                              : null,
                        ),
                        if (announcementHttpUri(_image.text) != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                _image.text.trim(),
                                height: 220,
                                width: double.infinity,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => Container(
                                  height: 96,
                                  alignment: Alignment.center,
                                  color: AdminColors.surfaceMuted,
                                  child: Text(
                                    'Image unavailable. The post can still be published.',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _editorSection(
                      step: '3',
                      title: 'Review and publish',
                      description:
                          'Check your post content, then save a draft or publish it for the selected audience.',
                      children: [
                        if (_error != null) ...[
                          AnnouncementStatusPanel(
                            icon: Icons.error_outline,
                            title: 'Changes not published',
                            message: _error!,
                          ),
                          const SizedBox(height: 16),
                        ],
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            if (widget.announcement?.status !=
                                AnnouncementStatus.published)
                              OutlinedButton(
                                onPressed: _saving
                                    ? null
                                    : () => _save(AnnouncementAction.saveDraft),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(48, 52),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 22,
                                  ),
                                ),
                                child: const Text('Save draft'),
                              ),
                            FilledButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () => _save(AnnouncementAction.publish),
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        semanticsLabel: 'Saving announcement',
                                      ),
                                    )
                                  : const Icon(Icons.campaign_outlined),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(48, 52),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                              ),
                              label: Text(
                                _saving
                                    ? 'Saving…'
                                    : widget.announcement?.status ==
                                          AnnouncementStatus.published
                                    ? 'Publish changes'
                                    : 'Publish announcement',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
