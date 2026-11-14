import 'package:flutter_test/flutter_test.dart';

import 'package:mind_mates/features/mind_aid/ai_engine/mind_aid_chat_engine.dart';
import 'package:mind_mates/features/mind_aid/data/mind_aid_dataset_loader.dart';
import 'package:mind_mates/features/mind_aid/domain/mind_aid_chat_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MindAidDatasetLoader loader;

  setUp(() {
    loader = MindAidDatasetLoader();
  });

  Future<void> checkIntent(String question, String expectedIntent) async {
    final dataset = await loader.load();
    final response = await MindAidChatEngine().respond(
      MindAidChatRequest(userId: 'integration_test', text: question),
      dataset,
    );

    expect(
      response.primaryIntent,
      expectedIntent,
      reason: 'Question: $question\nResponse: ${response.text}',
    );

    expect(response.text.trim(), isNotEmpty);
  }

  test('MindMate overview', () async {
    await checkIntent('What is MindMate?', 'mindmate_overview');
  });

  test('MindAid chatbot', () async {
    await checkIntent('What is MindAid?', 'mindaid_help');
  });

  test('Mood tracking', () async {
    await checkIntent('How can I track my mood?', 'mood_tracking_help');
  });

  test('Breathing exercises', () async {
    await checkIntent(
      'How do I use breathing exercises?',
      'breathing_feature_help',
    );
  });

  test('Secret Posting', () async {
    await checkIntent('How does Secret Posting work?', 'secret_posting_help');
  });

  test('Facial tracking', () async {
    await checkIntent('What is facial tracking?', 'facial_tracking_help');
  });

  test('Insights', () async {
    await checkIntent('Where can I view my insights?', 'insights_help');
  });

  test('Appointments', () async {
    await checkIntent('How can I book an appointment?', 'appointment_help');
  });

  test('Counselor messaging', () async {
    await checkIntent(
      'Can I message a guidance counselor?',
      'counselor_messaging_help',
    );
  });

  test('Privacy', () async {
    await checkIntent('Is my mental health data private?', 'privacy_help');
  });

  test('General stress', () async {
    await checkIntent('How can I cope with stress?', 'general_stress');
  });

  test('Academic stress', () async {
    await checkIntent('I am stressed about exams', 'academic_stress');
  });

  test('Crisis safety overrides MindMate topic', () async {
    final dataset = await loader.load();

    final response = await MindAidChatEngine().respond(
      const MindAidChatRequest(
        userId: 'integration_test',
        text: 'I use MindMate but I want to end my life',
      ),
      dataset,
    );

    expect(response.requiresEscalation, isTrue);
    expect(response.status, 'urgent');
  });
}
