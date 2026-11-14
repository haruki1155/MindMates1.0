import 'package:flutter/material.dart';
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
  late AnnouncementCategory _category;
  bool _saving = false, _previewing = false;
  String? _notice, _error;
  @override
  void initState() {
    super.initState();
    final post = widget.announcement?.content;
    _title = TextEditingController(text: post?.title);
    _body = TextEditingController(text: post?.body);
    _source = TextEditingController(text: post?.sourceUrl);
    _image = TextEditingController(text: post?.imageUrl);
    _kind = post?.kind ?? AnnouncementKind.original;
    _category = post?.category ?? AnnouncementCategory.careerGuidance;
  }

  @override
  void dispose() {
    for (final controller in [_title, _body, _source, _image]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _preview() async {
    final url = _source.text.trim();
    if (announcementHttpUri(url) == null) {
      setState(() => _error = 'Enter a valid http or https source link.');
      return;
    }
    setState(() {
      _previewing = true;
      _error = null;
      _notice = null;
    });
    try {
      final preview = await widget.repository.previewLink(url);
      if (!mounted ||
          _source.text.trim() != url ||
          _kind != AnnouncementKind.link) {
        return;
      }
      setState(() {
        if (_title.text.trim().isEmpty) _title.text = preview.title;
        if (_body.text.trim().isEmpty) _body.text = preview.description;
        if (_image.text.trim().isEmpty) _image.text = preview.imageUrl;
        _notice = preview.available
            ? 'Preview loaded. Review and edit before publishing. Existing text was kept.'
            : 'Preview unavailable. Enter the details manually.';
      });
    } catch (_) {
      if (mounted && _source.text.trim() == url) {
        setState(
          () => _notice = 'Preview unavailable. Enter the details manually.',
        );
      }
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _save(AnnouncementAction action) async {
    if (!_form.currentState!.validate()) return;
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
  Widget build(BuildContext context) => PopScope(
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
                      'Share an opportunity',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Career guidance and placement updates from PACC. Publishing makes this visible to app users.',
                    ),
                    const SizedBox(height: 20),
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
                                : (_) => setState(() {
                                    _kind = kind;
                                    _notice = null;
                                  }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<AnnouncementCategory>(
                      initialValue: _category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      isExpanded: true,
                      items: AnnouncementCategory.values
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(v.label),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _category = v!),
                    ),
                    if (_kind == AnnouncementKind.link) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _source,
                        enabled: !_saving,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Source link',
                          helperText:
                              'Students open this original post when they tap.',
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
                      decoration: const InputDecoration(
                        labelText: 'Image URL (optional)',
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
                    if (_notice != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_notice!),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (widget.announcement?.status !=
                            AnnouncementStatus.published)
                          OutlinedButton(
                            onPressed: _saving || _previewing
                                ? null
                                : () => _save(AnnouncementAction.saveDraft),
                            child: const Text('Save draft'),
                          ),
                        FilledButton.icon(
                          onPressed: _saving || _previewing
                              ? null
                              : () => _save(AnnouncementAction.publish),
                          icon: const Icon(Icons.campaign_outlined),
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
