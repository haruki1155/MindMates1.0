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

  @override
  Widget build(BuildContext context) => Theme(
    data: AdminTheme.data.copyWith(visualDensity: VisualDensity.standard),
    child: Builder(builder: (context) => _buildEditor(context)),
  );
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );

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
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Share an update',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Announcements and information from PACC. Publishing makes this visible to the selected app users.',
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'POST DETAILS',
                      style: TextStyle(
                        color: AdminColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
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
                    const SizedBox(height: 16),
                    _label('Post type'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        for (final type in AnnouncementPostType.values)
                          ChoiceChip(
                            label: Text(type.label),
                            selected: _postType == type,
                            onSelected: _saving
                                ? null
                                : (_) => setState(() => _postType = type),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _label('Audience'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        for (final role in PopulationRole.values)
                          FilterChip(
                            label: Text(role.label),
                            selected: _audience.contains(role),
                            onSelected: _saving
                                ? null
                                : (selected) => setState(() {
                                    selected
                                        ? _audience.add(role)
                                        : _audience.remove(role);
                                    if (_audience.isNotEmpty) {
                                      _audienceError = false;
                                    }
                                  }),
                          ),
                      ],
                    ),
                    if (_audienceError)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Select at least one audience.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    _label('Media'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
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
                                    // Video posts always point to an external source.
                                    if (media == AnnouncementMediaType.video) {
                                      _kind = AnnouncementKind.link;
                                    }
                                  }),
                          ),
                      ],
                    ),
                    if (_kind == AnnouncementKind.link) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _source,
                        onChanged: _sourceChanged,
                        enabled: !_saving,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: 'Source link',
                          helperText: _mediaType == AnnouncementMediaType.video
                              ? 'Paste the video link. App users tap Watch Video to open it.'
                              : 'App users open this original post when they tap.',
                        ),
                        maxLength: 2048,
                        validator: (v) => announcementHttpUri(v) == null
                            ? 'Enter a valid http or https link.'
                            : null,
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _previewing || _saving ? null : _preview,
                          icon: _previewing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.link),
                          label: Text(
                            _previewing ? 'Loading preview…' : 'Load preview',
                          ),
                        ),
                      ),
                      if (announcementHttpUri(_source.text) != null)
                        Text(
                          'Destination: ${announcementHttpUri(_source.text)!.host}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 12),
                    const Text(
                      'ANNOUNCEMENT CONTENT',
                      style: TextStyle(
                        color: AdminColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _title,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: 'Title'),
                      maxLength: 160,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter a title.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _body,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                      minLines: 4,
                      maxLines: 12,
                      maxLength: 10000,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter a description.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _image,
                      enabled: !_saving,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'Image URL (optional)',
                        helperText:
                            _kind == AnnouncementKind.link &&
                                _mediaType == AnnouncementMediaType.video
                            ? 'Used as the video thumbnail.'
                            : null,
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
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Image.network(
                          _image.text.trim(),
                          height: 180,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Text(
                            'Image unavailable. The post can still be published.',
                          ),
                        ),
                      ),
                    AnimatedSwitcher(
                      duration: announcementTransitionDuration(context),
                      child: _notice == null
                          ? const SizedBox.shrink()
                          : AnnouncementStatusPanel(
                              key: ValueKey(_notice),
                              icon: Icons.info_outline,
                              title: 'Link preview',
                              message: _notice!,
                            ),
                    ),
                    if (_error != null)
                      AnnouncementStatusPanel(
                        icon: Icons.error_outline,
                        title: 'Changes not published',
                        message: _error!,
                      ),
                    const SizedBox(height: 16),
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
                              minimumSize: const Size(48, 48),
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
                                    semanticsLabel: "Saving announcement",
                                  ),
                                )
                              : const Icon(Icons.campaign_outlined),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          label: Text(
                            _saving
                                ? 'Saving…'
                                : widget.announcement?.status ==
                                      AnnouncementStatus.published
                                ? 'Publish changes'
                                : 'Publish',
                          ),
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
