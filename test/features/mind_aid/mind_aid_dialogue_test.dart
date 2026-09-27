import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/providers/mind_aid_provider.dart';
import 'package:mind_mates/repositories/mind_aid_repository_screen.dart';
import 'package:mind_mates/models/mind_aid_message_model.dart';
import 'package:mind_mates/models/mind_aid_suggestion_model.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_chat_models.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_context.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_dataset_models.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_dialogue_state.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_integration_models.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_safety.dart';
import 'package:mind_mates/features/mind_aid/models/paacc_route_decision.dart';
import 'package:mind_mates/features/mind_aid/services/paacc_intent_router.dart';

class TestRouter extends PaaccIntentRouter {
  int calls = 0;
  @override
  Future<PaaccRouteDecision> route(String text) async {
    calls++;
    return const PaaccRouteDecision(
      route: PaaccRouteType.copingHelp,
      rawIntent: 'coping_help',
      confidence: .99,
    );
  }
}

class TestRepository extends MindAidRepository {
  bool syncFails = false;
  bool historyFails = false;
  MindAidDialogueState? state;
  int turn = 0;
  MindAidSafetyLevel safety = MindAidSafetyLevel.safeSupport;
  final history = <MindAidMessageModel>[];
  @override
  Future<MindAidPreferences> loadPreferences(String userId) async =>
      const MindAidPreferences(
        hasDecision: true,
        cloudConsent: false,
        personalizationEnabled: false,
        conversationId: 'conversation',
      );
  @override
  Future<List<MindAidMessageModel>> fetchMessages(
    String userId, {
    String? conversationId,
  }) async {
    if (historyFails) throw StateError('History unavailable');
    return history;
  }
  @override
  Future<List<MindAidSuggestionModel>> fetchSuggestions() async => [];
  @override
  Future<MindAidDialogueState> loadDialogueState(
    String userId,
    String conversationId,
  ) async => state ?? MindAidDialogueState(conversationId: conversationId);
  @override
  Future<void> saveDialogueState(
    String userId,
    MindAidDialogueState next,
  ) async {
    if (syncFails) throw StateError('State sync unavailable');
    state = next;
  }

  @override
  Future<bool> consumeDialogueAction(
    String userId,
    String conversationId,
    String messageId,
    MindAidAction action, {
    bool dismiss = false,
  }) async {
    final valid = dismiss
        ? state?.sourceMessageId == messageId
        : state?.matches(messageId, action, DateTime.now()) == true;
    if (valid) state = MindAidDialogueState(conversationId: conversationId);
    return valid;
  }

  @override
  Future<void> savePaaccDisplayOverride({
    required String messageId,
    required String text,
    required List<MindAidAction> actions,
  }) async {}
  @override
  Future<MindAidSendResult> sendMessage({
    required String userId,
    required String text,
    List<MindAidMessageModel> recentMessages = const [],
    MindAidContext context = const MindAidContext(),
    MindAidPreferences? preferences,
    String launchContext = '',
    String? requestId,
  }) async {
    final message = MindAidMessageModel(
      id: 'bot${++turn}',
      conversationId: 'conversation',
      sender: 'assistant',
      text: 'Original safety-screened response',
      createdAt: DateTime.now(),
      status: safety.blocksCloud ? 'urgent' : 'sent',
      safetyLevel: safety.name,
      requiresEscalation: safety.blocksCloud,
    );
    return MindAidSendResult(
      message: message,
      suggestions: [],
      userMessageSaved: true,
      chatResponse: MindAidChatResponse(
        text: message.text,
        intentMatches: [],
        severity: MindAidSeverity.low,
        suggestions: [],
        followUpQuestions: [],
        recommendations: [],
        requiresEscalation: safety.blocksCloud,
        conversationState: const MindAidConversationState(),
        status: message.status,
        safetyLevel: safety,
      ),
    );
  }
}

void main() {
  test('reopening the same conversation keeps unsynced messages', () async {
    final repository = TestRepository();
    final provider = MindAidProvider(repository, paaccIntentRouter: TestRouter());
    await provider.loadChat('owner');
    await provider.sendMessage('owner', 'How do I schedule an appointment?');
    expect(provider.messages, hasLength(2));
    expect(provider.messages.last.text, contains('appointment options'));

    // The backend may not yet contain the locally displayed turn.
    await provider.loadChat('owner');
    expect(provider.messages, hasLength(2));
    expect(provider.messages.last.text, contains('appointment options'));
    provider.dispose();
  });

  test('older partial history cannot replace the current reply', () async {
    final repository = TestRepository();
    final provider = MindAidProvider(repository, paaccIntentRouter: TestRouter());
    await provider.loadChat('owner');
    await provider.sendMessage('owner', 'How do I schedule an appointment?');
    repository.history.add(MindAidMessageModel(
      id: 'older',
      conversationId: 'conversation',
      sender: 'assistant',
      text: 'Earlier greeting',
      createdAt: DateTime(2026, 1, 1),
      status: 'sent',
      safetyLevel: MindAidSafetyLevel.safeSupport.name,
    ));

    await provider.loadChat('owner');
    expect(provider.messages.last.text, contains('appointment options'));
    provider.dispose();
  });

  test('reopening retains a pending choice when backend sync failed', () async {
    final repository = TestRepository()..syncFails = true;
    final provider = MindAidProvider(repository, paaccIntentRouter: TestRouter());
    await provider.loadChat('owner');
    await provider.sendMessage('owner', 'appointment');
    final message = provider.messages.last;
    expect(provider.activeActionMessageId, message.id);

    await provider.loadChat('owner');
    expect(provider.activeActionMessageId, message.id);
    expect(provider.messages.last.actions, isNotEmpty);
    provider.dispose();
  });

  test('history read failure does not erase the displayed conversation', () async {
    final repository = TestRepository();
    final provider = MindAidProvider(repository, paaccIntentRouter: TestRouter());
    await provider.loadChat('owner');
    await provider.sendMessage('owner', 'How do I schedule an appointment?');
    repository.historyFails = true;

    await provider.loadChat('owner');
    expect(provider.messages, hasLength(2));
    expect(provider.errorMessage, contains('could not load'));
    provider.dispose();
  });

  test(
    'fresh appointment and service actions work when state sync fails',
    () async {
      final repository = TestRepository()..syncFails = true;
      final provider = MindAidProvider(
        repository,
        paaccIntentRouter: TestRouter(),
      );
      await provider.loadChat('owner');
      for (final text in ['appointment', 'PACC services']) {
        await provider.sendMessage('owner', text);
        final message = provider.messages.last;
        expect(provider.dialogueSyncError, isNotNull);
        expect(
          await provider.consumeAction(
            'owner',
            message.id,
            message.actions.first,
          ),
          isTrue,
        );
        expect(
          await provider.consumeAction(
            'owner',
            message.id,
            message.actions.first,
          ),
          isFalse,
        );
      }
      provider.dispose();
    },
  );
  test(
    'yes remains in chat; no and topic change clear state; stale taps fail',
    () async {
      final repository = TestRepository();
      final provider = MindAidProvider(
        repository,
        paaccIntentRouter: TestRouter(),
      );
      await provider.loadChat('owner');
      await provider.sendMessage('owner', 'assessment');
      final first = provider.messages.last;
      await provider.sendMessage('owner', 'yes');
      expect(provider.messages.last.text, contains('button'));
      expect(
        await provider.consumeAction('owner', first.id, first.actions.first),
        isFalse,
      );
      await provider.sendMessage('owner', 'no');
      expect(provider.activeActionMessageId, isNull);
      await provider.sendMessage('owner', 'appointment');
      await provider.sendMessage('owner', 'recipe for spaghetti');
      expect(provider.messages.last.text, contains('make sure I understand'));
      expect(provider.activeActionMessageId, isNull);
      provider.dispose();
    },
  );
  test(
    'safety clears pending state before PAACC; another device can consume once',
    () async {
      final repository = TestRepository();
      final router = TestRouter();
      final provider = MindAidProvider(repository, paaccIntentRouter: router);
      await provider.loadChat('owner');
      await provider.sendMessage('owner', 'assessment');
      final message = provider.messages.last;
      final second = MindAidProvider(
        repository,
        paaccIntentRouter: TestRouter(),
      );
      await second.loadChat('owner');
      expect(second.activeActionMessageId, message.id);
      expect(
        await second.consumeAction('owner', message.id, message.actions.first),
        isTrue,
      );
      expect(
        await provider.consumeAction(
          'owner',
          message.id,
          message.actions.first,
        ),
        isFalse,
      );
      await provider.sendMessage('owner', 'appointment');
      final before = router.calls;
      for (final safety in [
        MindAidSafetyLevel.highDistress,
        MindAidSafetyLevel.crisisOrImmediateRisk,
      ]) {
        repository.safety = safety;
        await provider.sendMessage('owner', 'I want to end my life');
        expect(router.calls, before);
        expect(
          provider.messages.last.text,
          'Original safety-screened response',
        );
        expect(provider.activeActionMessageId, isNull);
      }
      provider.dispose();
      second.dispose();
    },
  );
}
