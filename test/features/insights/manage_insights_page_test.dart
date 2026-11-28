import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/admin/screens/admin_portal.dart';
import 'package:mind_mates/features/admin/theme/admin_theme.dart';
import 'package:mind_mates/features/insights/data/admin_insight_catalog_repository.dart';
import 'package:mind_mates/features/insights/models/insights_models.dart';
import 'package:mind_mates/features/insights/screens/manage_insights_page.dart';
import 'package:mind_mates/features/insights/theme/insights_admin_theme.dart';
import 'package:mind_mates/features/insights/widgets/insight_content_editor.dart';
import 'package:mind_mates/models/profile_roles.dart';

final _now = DateTime(2026, 11, 28, 9);

Map<String, dynamic> _provenance() => {
  'sourceTitle': 'WHO — Mental Health at Work',
  'sourceUrl':
      'https://www.who.int/news-room/fact-sheets/detail/mental-health-at-work',
  'evidenceType': 'official_guideline',
  'rightsStatus': 'original',
};

Map<String, dynamic> _doc(
  String id, {
  String? reviewStatus,
  bool withProvenance = true,
  List<String> targetRoles = const ['all'],
  bool isActive = true,
  int sortOrder = 1,
}) => {
  'id': id,
  'title': 'Title $id',
  'subtitle': 'Subtitle',
  'categoryId': 'stress_burnout',
  'categoryLabel': 'Stress relief',
  'sectionId': 'recommended',
  'sortOrder': sortOrder,
  'isActive': isActive,
  'targetRoles': targetRoles,
  'reviewStatus': ?reviewStatus,
  if (withProvenance) ..._provenance(),
};

InsightCardItem _item(Map<String, dynamic> json) =>
    InsightCardItem.fromJson(json);

AdminInsightCatalogRepository _repo(_MemoryDataSource source) =>
    AdminInsightCatalogRepository(
      dataSource: source,
      currentUid: () => 'admin_1',
      now: () => _now,
    );

void main() {
  group('AdminInsightCatalogRepository', () {
    test('lists every document sorted by sortOrder', () async {
      final source = _MemoryDataSource([
        _doc('b', sortOrder: 2, isActive: false),
        _doc('a', sortOrder: 1, reviewStatus: 'archived'),
      ]);
      final items = await _repo(source).loadAllContent();
      expect(items.map((item) => item.id), ['a', 'b']);
    });

    test('approving stamps reviewer and timestamps', () async {
      final source = _MemoryDataSource();
      await _repo(source).saveContent(
        _item(_doc('guide', reviewStatus: 'approved')),
        reviewerUid: 'admin_1',
      );

      final saved = source.writes.single.value;
      expect(saved['reviewStatus'], 'approved');
      expect(saved['reviewedBy'], 'admin_1');
      expect(saved['reviewedAt'], _now);
      expect(saved['updatedAt'], _now);
      expect(_item({...saved, 'id': 'guide'}).hasApprovedProvenance, isTrue);
    });

    test('blocks approval without complete provenance', () async {
      final repository = _repo(_MemoryDataSource());
      final invalid = <Map<String, dynamic>>[
        {'sourceUrl': null},
        {'sourceUrl': 'http://www.who.int/x'},
        {'sourceUrl': 'https://user:pw@www.who.int/x'},
        {'sourceTitle': ' '},
        {'rightsStatus': 'unknown'},
        {'evidenceType': 'blog'},
      ];
      for (final override in invalid) {
        final draft = _item({
          ..._doc('guide', reviewStatus: 'approved'),
          ...override,
        });
        await expectLater(
          repository.saveContent(draft, reviewerUid: 'admin_1'),
          throwsA(isA<InsightCatalogValidationException>()),
          reason: '$override',
        );
        await expectLater(
          repository.setReviewStatus(
            item: draft,
            reviewStatus: 'approved',
            reviewerUid: 'admin_1',
          ),
          throwsA(isA<InsightCatalogValidationException>()),
        );
      }
    });

    test('rejects bad ids, empty titles, and unlisted routes', () async {
      final repository = _repo(_MemoryDataSource());
      for (final json in [
        {..._doc('Bad ID!')},
        {..._doc('ok_id'), 'title': ''},
        {..._doc('ok_id'), 'actionRoute': '/admin'},
      ]) {
        await expectLater(
          repository.saveContent(_item(json), reviewerUid: 'admin_1'),
          throwsA(isA<InsightCatalogValidationException>()),
        );
      }
    });

    test('drafts save without provenance; archive hides content', () async {
      final source = _MemoryDataSource();
      final repository = _repo(source);
      await repository.saveContent(
        _item(_doc('draft_guide', withProvenance: false)),
        reviewerUid: '',
      );
      await repository.setReviewStatus(
        item: _item(_doc('draft_guide')),
        reviewStatus: 'archived',
        reviewerUid: 'admin_1',
      );
      await repository.setActive(id: 'draft_guide', isActive: true);

      expect(source.writes[1].value, {
        'reviewStatus': 'archived',
        'updatedAt': _now,
        'isActive': false,
      });
      expect(source.writes[2].value, {'isActive': true, 'updatedAt': _now});
    });
  });

  group('ManageInsightsPage', () {
    Future<_MemoryDataSource> pumpPage(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = _MemoryDataSource([
        _doc('approved_guide', reviewStatus: 'approved', sortOrder: 1),
        _doc(
          'legacy_guide',
          withProvenance: false,
          targetRoles: const ['teaching'],
          sortOrder: 2,
        ),
        _doc('archived_guide', reviewStatus: 'archived', sortOrder: 3),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ManageInsightsPage(repository: _repo(source))),
        ),
      );
      await tester.pumpAndSettle();
      return source;
    }

    testWidgets('lists items with eligibility badges and counts', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(
        find.text('1 Featured-eligible • 2 Need provenance/review'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('insight_row_approved_guide')),
          matching: find.text('Featured-eligible'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('insight_row_legacy_guide')),
          matching: find.text('Library only'),
        ),
        findsOneWidget,
      );
      final approve = tester.widget<FilledButton>(
        find.byKey(const Key('approve_legacy_guide')),
      );
      expect(approve.onPressed, isNull);
    });

    testWidgets('status, role, and search filters narrow the list', (
      tester,
    ) async {
      await pumpPage(tester);

      await tester.tap(find.byKey(const Key('status_filter_approved')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('insight_row_approved_guide')), findsOne);
      expect(find.byKey(const Key('insight_row_legacy_guide')), findsNothing);

      await tester.tap(find.byKey(const Key('status_filter_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All roles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Student').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('insight_row_legacy_guide')), findsNothing);
      expect(find.byKey(const Key('insight_row_approved_guide')), findsOne);

      await tester.enterText(find.byType(TextField), 'archived');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('insight_row_approved_guide')), findsNothing);
      expect(find.byKey(const Key('insight_row_archived_guide')), findsOne);
    });

    testWidgets('applies page-scoped visual enhancement without altering AdminTheme', (
      tester,
    ) async {
      await pumpPage(tester);

      // Global AdminTheme stays untouched.
      expect(AdminTheme.data.scaffoldBackgroundColor, AdminColors.canvas);

      // Scoped #F4F7FB page background.
      final canvas = tester.widget<ColoredBox>(
        find.byKey(const Key('insights_page_canvas')),
      );
      expect(canvas.color, const Color(0xFFF4F7FB));

      // Warm yellow New insight CTA with 12px border radius.
      final newBtn = tester.widget<FilledButton>(
        find.byKey(const Key('new_insight_button')),
      );
      expect(
        newBtn.style?.backgroundColor?.resolve(<WidgetState>{}),
        InsightsAdminColors.ctaYellow,
      );
      expect(
        newBtn.style?.shape?.resolve(<WidgetState>{}),
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      );

      // Cohesive segmented status bar, role dropdown, search icon, and 2-column grid.
      expect(
        find.byKey(const Key('insights_status_segmented_control')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('insights_role_filter')), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(
        find.byKey(const Key('insights_card_grid_two_col')),
        findsOneWidget,
      );

      // Squircle card container (#FFFFFF, 16px radius, 20px padding, #F3F4F6 border).
      final card = tester.widget<Container>(
        find.byKey(const Key('insight_row_legacy_guide')),
      );
      final decoration = card.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFFFFFFFF));
      expect(
        decoration.borderRadius,
        const BorderRadius.all(Radius.circular(16)),
      );
      expect(card.padding, const EdgeInsets.all(20));
      expect(
        (decoration.border! as Border).top.color,
        const Color(0xFFF3F4F6),
      );

      // Needs Provenance pill, description, provenance text, status pills,
      // category tags, and action icons are rendered.
      final legacyRow = find.byKey(const Key('insight_row_legacy_guide'));
      expect(
        find.byKey(const Key('needs_provenance_legacy_guide')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: legacyRow, matching: find.text('Subtitle')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: legacyRow,
          matching: find.textContaining('Needs: Source title'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: legacyRow,
          matching: find.byType(InsightsStatusPill),
        ),
        findsNWidgets(3),
      );
      expect(
        find.descendant(
          of: legacyRow,
          matching: find.byType(InsightsCategoryTag),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: legacyRow,
          matching: find.byIcon(Icons.edit_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: legacyRow,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: legacyRow,
          matching: find.byIcon(Icons.visibility_off_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: legacyRow,
          matching: find.byIcon(Icons.archive_outlined),
        ),
        findsOneWidget,
      );

      // Primary Approve style uses #89CFF0 and Archive hover uses light red.
      final approveBtn = tester.widget<FilledButton>(
        find.byKey(const Key('approve_legacy_guide')),
      );
      expect(
        approveBtn.style?.backgroundColor?.resolve(<WidgetState>{}),
        const Color(0xFF89CFF0),
      );
      final archiveBtn = tester.widget<OutlinedButton>(
        find.byKey(const Key('archive_legacy_guide')),
      );
      expect(
        archiveBtn.style?.backgroundColor?.resolve({WidgetState.hovered}),
        InsightsAdminColors.dangerBg,
      );
    });

    testWidgets('renders cleanly on narrow viewports without overflow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = _MemoryDataSource([
        _doc('legacy_guide', withProvenance: false, sortOrder: 1),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ManageInsightsPage(repository: _repo(source))),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('insight_row_legacy_guide')), findsOneWidget);
    });

    testWidgets('archive and restore update review status', (tester) async {
      final source = await pumpPage(tester);

      await tester.tap(find.byKey(const Key('archive_approved_guide')));
      await tester.pumpAndSettle();
      expect(source.docs['approved_guide']!['reviewStatus'], 'archived');
      expect(source.docs['approved_guide']!['isActive'], false);

      await tester.tap(find.byKey(const Key('archive_archived_guide')));
      await tester.pumpAndSettle();
      expect(source.docs['archived_guide']!['reviewStatus'], 'pending_review');

      await tester.tap(find.byKey(const Key('toggle_active_legacy_guide')));
      await tester.pumpAndSettle();
      expect(source.docs['legacy_guide']!['isActive'], false);
    });
  });

  group('InsightContentEditor', () {
    Future<void> pumpEditor(
      WidgetTester tester,
      _MemoryDataSource source, {
      InsightCardItem? item,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1000, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: InsightContentEditor(repository: _repo(source), item: item),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('creates a draft with an auto-slugged id', (tester) async {
      final source = _MemoryDataSource();
      await pumpEditor(tester, source);

      await tester.enterText(
        find.byKey(const Key('insight_editor_title')),
        'Sleep & Rest Basics',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('insight_editor_save')));
      await tester.pumpAndSettle();

      final saved = source.docs['sleep_rest_basics']!;
      expect(saved['title'], 'Sleep & Rest Basics');
      expect(saved['reviewStatus'], 'draft');
      expect(saved['targetRoles'], ['all']);
    });

    testWidgets('edits keep approval only while provenance is complete', (
      tester,
    ) async {
      final source = _MemoryDataSource();
      final item = _item({
        ..._doc('guide', reviewStatus: 'approved'),
        'actionRoute': '/mood/log',
      });
      await pumpEditor(tester, source, item: item);

      final checklist = find.byKey(const Key('insight_eligibility_checklist'));
      expect(
        find.descendant(
          of: checklist,
          matching: find.byIcon(Icons.check_circle),
        ),
        findsNWidgets(5),
      );

      await tester.enterText(
        find.byKey(const Key('insight_editor_source_url')),
        'http://insecure.example.com',
      );
      await tester.pump();
      expect(
        find.descendant(
          of: checklist,
          matching: find.byIcon(Icons.radio_button_unchecked),
        ),
        findsNWidgets(2),
      );

      await tester.tap(find.byKey(const Key('insight_editor_save')));
      await tester.pumpAndSettle();
      expect(source.docs, isEmpty, reason: 'invalid https link blocks save');

      await tester.enterText(
        find.byKey(const Key('insight_editor_source_url')),
        'https://www.nimh.nih.gov/health/topics/depression',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('insight_editor_save')));
      await tester.pumpAndSettle();

      final saved = source.docs['guide']!;
      expect(saved['sourceUrl'], startsWith('https://www.nimh.nih.gov'));
      expect(saved['actionRoute'], '/mood/log');
      // Approval was dropped when the link became invalid; re-approval is an
      // explicit step.
      expect(saved['reviewStatus'], 'pending_review');
    });

    testWidgets('uses scoped #F4F7FB canvas, status pills, and primary save styling', (
      tester,
    ) async {
      final source = _MemoryDataSource();
      await pumpEditor(tester, source);

      final scaffold = tester.widget<Scaffold>(
        find.byKey(const Key('insight_editor_scaffold')),
      );
      expect(scaffold.backgroundColor, const Color(0xFFF4F7FB));
      expect(find.text('New insight'), findsOneWidget);
      expect(find.byType(InsightsStatusPill), findsAtLeastNWidgets(2));
      expect(find.byKey(const Key('insight_editor_cancel')), findsOneWidget);

      final saveBtn = tester.widget<FilledButton>(
        find.byKey(const Key('insight_editor_save')),
      );
      expect(
        saveBtn.style?.backgroundColor?.resolve(<WidgetState>{}),
        const Color(0xFF89CFF0),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders cleanly on narrow viewports without overflow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = _MemoryDataSource();
      await tester.pumpWidget(
        MaterialApp(
          home: InsightContentEditor(repository: _repo(source)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('insight_editor_save')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('insight_editor_save')), findsOneWidget);
    });
  });

  testWidgets('Insights Content nav is visible to administrators only', (
    tester,
  ) async {
    for (final role in [
      AccessRole.admin,
      AccessRole.counselor,
      AccessRole.portalStaff,
    ]) {
      AdminPortalPage? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AdminTheme.data,
          home: Scaffold(
            body: SizedBox(
              width: 280,
              height: 1000,
              child: PortalWorkspaceNavigation(
                page: AdminPortalPage.dashboard,
                onChanged: (page) => selected = page,
                accessRole: role,
                isSuperAdmin: role == AccessRole.admin,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final finder = find.text('Insights Content');
      if (role == AccessRole.admin) {
        expect(finder, findsOneWidget);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
        expect(selected, AdminPortalPage.insightCatalog);
      } else {
        expect(finder, findsNothing, reason: '$role');
      }
    }
  });
}

class _MemoryDataSource implements AdminInsightCatalogDataSource {
  _MemoryDataSource([List<Map<String, dynamic>> initial = const []]) {
    for (final doc in initial) {
      docs[doc['id'] as String] = {...doc};
    }
  }

  final docs = <String, Map<String, dynamic>>{};
  final writes = <MapEntry<String, Map<String, dynamic>>>[];

  @override
  Future<List<Map<String, dynamic>>> loadAll() async => [
    for (final entry in docs.entries) {...entry.value, 'id': entry.key},
  ];

  @override
  Future<void> merge(String id, Map<String, dynamic> data) async {
    writes.add(MapEntry(id, data));
    docs[id] = {...?docs[id], ...data};
  }
}
