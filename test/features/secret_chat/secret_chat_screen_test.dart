import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/secret_chat/domain/secret_chat_safety_validator.dart';
import 'package:mind_mates/features/secret_chat/domain/forum_live_check.dart';
import 'package:mind_mates/features/secret_chat/screens/secret_chat_screen.dart';
import 'package:mind_mates/models/secret_chat_model.dart';
import 'package:mind_mates/features/secret_chat/pages/secret_chat_page.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/insights_provider.dart';
import 'package:mind_mates/providers/report_provider.dart';
import 'package:mind_mates/providers/secret_chat_provider.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/insights_repository.dart';
import 'package:mind_mates/repositories/report_repository.dart';
import 'package:mind_mates/repositories/secret_chat_repository.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:provider/provider.dart';

const forumWarning =
    'MindMate is a safe and supportive community. Please revise your message using respectful language before publishing.';

void main() {
  testWidgets('empty Secret Chat shows real empty state', (tester) async {
    await tester.pumpWidget(_app(posts: const []));

    expect(find.text('No thoughts found'), findsOneWidget);
    expect(
      find.text('No anonymous threads yet. Start a wellbeing conversation.'),
      findsOneWidget,
    );
  });

  testWidgets('header does not duplicate the main Home navigation', (
    tester,
  ) async {
    await tester.pumpWidget(_app(posts: const []));

    expect(find.byIcon(Icons.home_rounded), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('compose shows validation message for blocked content', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(posts: const []));

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pump();
    await tester.enterText(
      find.byType(TextField).last,
      'Selling my old laptop this week',
    );
    await tester.pump();

    expect(find.textContaining('Secret Chat is only for'), findsOneWidget);
  });

  testWidgets('tapping comments opens full thread screen', (tester) async {
    await tester.pumpWidget(_app(posts: [_post()]));

    await tester.tap(find.byIcon(Icons.mode_comment_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Anonymous Thread'), findsOneWidget);
    expect(find.text('You are not alone in this.'), findsOneWidget);
  });

  testWidgets('profile header button opens custom profile action', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      _app(posts: [_post()], onProfile: () => opened = true),
    );

    await tester.tap(find.byTooltip('Secret Chat profile'));

    expect(opened, isTrue);
  });

  testWidgets('thread shows friendly message when reply cannot be saved', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        posts: [_post()],
        onAddComment: ({required postId, required message}) async {
          throw const SecretChatActionException(
            'This thread is no longer available for replies.',
          );
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.mode_comment_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(
      find.byType(TextField).last,
      'I feel this too. Support helps.',
    );
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(
      find.text('This thread is no longer available for replies.'),
      findsWidgets,
    );
  });

  testWidgets('thread shows success message when reply is saved', (
    tester,
  ) async {
    await tester.pumpWidget(_app(posts: [_post()]));

    await tester.tap(find.byIcon(Icons.mode_comment_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(
      find.byType(TextField).last,
      'I feel this too. Support helps.',
    );
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(find.text('Reply posted anonymously.'), findsWidgets);
  });

  testWidgets('only the post owner sees and confirms delete', (tester) async {
    String? deletedPostId;
    await tester.pumpWidget(
      _app(
        posts: [_post(isMine: true)],
        onDeletePost: (postId) async => deletedPostId = postId,
      ),
    );

    await tester.tap(find.byTooltip('Post options'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Delete post'), findsOneWidget);
    await tester.tap(find.text('Delete post'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Delete this post?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(deletedPostId, 'post_1');
    expect(find.text('Secret Chat post deleted.'), findsOneWidget);
  });

  testWidgets('non-owner does not see post delete options', (tester) async {
    await tester.pumpWidget(_app(posts: [_post()]));

    expect(find.byTooltip('Post options'), findsNothing);
    expect(find.text('Delete post'), findsNothing);
  });

  testWidgets('a reply the server refuses stays in the box for editing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        posts: [_post()],
        onAddComment: ({required postId, required message}) async {
          throw const SecretChatValidationException(
            SecretChatValidationResult(
              code: SecretChatValidationCode.inappropriateLanguage,
              message: forumWarning,
            ),
          );
        },
      ),
    );
    await tester.tap(find.byIcon(Icons.mode_comment_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    const draft = 'I feel this too, kaya natin to.';
    await tester.enterText(find.byType(TextField).last, draft);
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();
    expect(find.text(forumWarning), findsWidgets);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      draft,
    );
    expect(
      find.text(draft),
      findsOneWidget,
      reason: 'no failed copy left behind',
    );
  });

  testWidgets(
    'a post the server refuses keeps the composer open with the draft',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          posts: const [],
          onCreatePost: ({required message, required categories}) async {
            throw const SecretChatValidationException(
              SecretChatValidationResult(
                code: SecretChatValidationCode.inappropriateLanguage,
                message: forumWarning,
              ),
            );
          },
        ),
      );
      await tester.tap(find.byIcon(Icons.edit_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      const draft = 'Exams are stressful but I am grateful for support.';
      await tester.enterText(find.byType(TextField).last, draft);
      await tester.tap(find.text('Stress').last);
      await tester.pump();
      await tester.ensureVisible(find.text('Post anonymously'));
      await tester.tap(find.text('Post anonymously'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Post anonymously'),
        findsOneWidget,
        reason: 'sheet stays open',
      );
      expect(find.text(forumWarning), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        draft,
      );
    },
  );

  testWidgets('the composer explains the community language guideline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(posts: const []));
    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Community language guidelines'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('respectful language'), findsWidgets);
  });

  testWidgets('a prohibited word disables posting before it is sent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var created = 0;
    await tester.pumpWidget(
      _app(
        posts: const [],
        onCreatePost: ({required message, required categories}) async =>
            created++,
      ),
    );
    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
      find.byType(TextField).last,
      'Putangina ng stress sa school',
    );
    await tester.pump();
    expect(find.text(forumWarning), findsOneWidget);
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Post anonymously'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(created, 0);
  });

  testWidgets('a reply that fails to send stays in the box', (tester) async {
    await tester.pumpWidget(
      _app(
        posts: [_post()],
        onAddComment: ({required postId, required message}) async {
          throw StateError('offline');
        },
      ),
    );
    await tester.tap(find.byIcon(Icons.mode_comment_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    const draft = 'Sending this while offline.';
    await tester.enterText(find.byType(TextField).last, draft);
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      draft,
    );
  });

  Future<SecretChatValidationResult?> serverRefuses(String text) async =>
      text.contains('tarantado')
      ? const SecretChatValidationResult(
          code: SecretChatValidationCode.inappropriateLanguage,
          message: forumWarning,
        )
      : null;

  testWidgets('the server check warns and disables Post while typing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(posts: const [], onCheckText: serverRefuses));
    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
      find.byType(TextField).last,
      'Stress sa school, tarantado yung group mate ko',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text(forumWarning), findsOneWidget);
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Post anonymously'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('the server check also guards comments', (tester) async {
    await tester.pumpWidget(_app(posts: [_post()], onCheckText: serverRefuses));
    await tester.tap(find.byIcon(Icons.mode_comment_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(TextField).last, 'tarantado ka');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text(forumWarning), findsWidgets);
    final send = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.send_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(send.onPressed, isNull);
  });

  testWidgets(
    'with the keyboard open the composer scrolls instead of overflowing',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(posts: const []));
      await tester.tap(find.byIcon(Icons.edit_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Post anonymously'));
      await tester.pump();
      expect(find.text('Post anonymously').hitTestable(), findsOneWidget);
    },
  );

  testWidgets('the Forum screen fits a TECNO CN5 without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2364);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(posts: [_post()]));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Saved (0)'), findsOneWidget);
  });

  _pageRefreshTests();
}

void _pageRefreshTests() {
  testWidgets('a forum interaction refreshes the same user insights', (
    tester,
  ) async {
    final users = UserProvider(_ProfileUserRepository())
      ..setUser(const UserModel(id: 'user_1', email: 'a@example.com'));
    final reports = _RecordingReportProvider();
    final insights = _RecordingInsightsProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: users),
          ChangeNotifierProvider<SecretChatProvider>.value(
            value: _QuietSecretChatProvider(),
          ),
          ChangeNotifierProvider<ReportProvider>.value(value: reports),
          ChangeNotifierProvider<InsightsProvider>.value(value: insights),
        ],
        child: const MaterialApp(home: SecretChatPage()),
      ),
    );
    await tester.pump();

    tester
        .widget<SecretChatScreen>(find.byType(SecretChatScreen))
        .onToggleLike('post_1');
    await tester.pump(const Duration(milliseconds: 100));

    expect(reports.refreshedUsers, ['user_1']);
    expect(insights.refreshedUsers, ['user_1']);
  });
}

class _QuietSecretChatProvider extends SecretChatProvider {
  _QuietSecretChatProvider() : super(SecretChatRepository());

  @override
  bool get canCreate => true;

  @override
  Future<void> loadPosts() async {}

  @override
  Future<void> toggleLike(String postId) async {}
}

class _RecordingReportProvider extends ReportProvider {
  _RecordingReportProvider() : super(ReportRepository());
  final refreshedUsers = <String>[];

  @override
  Future<void> refreshWeeklyReport(String userId) async {
    refreshedUsers.add(userId);
  }
}

class _RecordingInsightsProvider extends InsightsProvider {
  _RecordingInsightsProvider() : super(InsightsRepository());
  final refreshedUsers = <String>[];

  @override
  Future<void> refreshLoadedContext(String userId) async {
    refreshedUsers.add(userId);
  }
}

class _ProfileUserRepository extends UserRepository {
  @override
  Future<UserModel?> fetchUserProfile(String uid) async =>
      UserModel(id: uid, email: 'a@example.com');
}

Widget _app({
  required List<SecretChatModel> posts,
  AddSecretComment? onAddComment,
  CreateSecretPost? onCreatePost,
  CheckForumText? onCheckText,
  VoidCallback? onProfile,
  Future<void> Function(String postId)? onDeletePost,
}) {
  return MaterialApp(
    home: SecretChatScreen(
      posts: posts,
      categories: const [
        SecretChatCategory(label: 'Mental Health', color: Color(0xFFFFC414)),
        SecretChatCategory(label: 'Anxiety', color: Color(0xFFFF7BA5)),
        SecretChatCategory(label: 'Stress', color: Color(0xFFFF9D76)),
      ],
      selectedFilter: SecretChatFilter.popular,
      savedCount: 0,
      searchQuery: '',
      isLoading: false,
      errorMessage: null,
      canCreate: true,
      onFilterChanged: (_) {},
      onSearchChanged: (_) {},
      onCreatePost:
          onCreatePost ?? ({required message, required categories}) async {},
      onToggleLike: (_) {},
      onToggleSave: (_) {},
      onFetchComments: (_) async => [
        SecretChatComment(
          id: 'comment_1',
          postId: 'post_1',
          message: 'You are not alone in this.',
          createdAt: DateTime(2026, 7, 3),
        ),
      ],
      onAddComment:
          onAddComment ?? ({required postId, required message}) async {},
      onRetry: () {},
      onProfile: onProfile,
      onDeletePost: onDeletePost,
      onCheckText: onCheckText,
    ),
  );
}

SecretChatModel _post({bool isMine = false}) {
  return SecretChatModel(
    id: 'post_1',
    message: 'I feel anxious about school pressure.',
    createdAt: DateTime(2026, 7, 3),
    category: 'Anxiety',
    likeCount: 1,
    commentCount: 1,
    authorId: isMine ? 'user_1' : 'user_2',
    isMine: isMine,
  );
}
