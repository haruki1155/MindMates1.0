import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/counseling/screens/service_detail_screen.dart';
import 'package:mind_mates/features/counseling/screens/services_screen.dart';
import 'package:mind_mates/features/counseling/widgets/client_feedback_qr_card.dart';

void main() {
  test('Client Feedback QR targets the exact supplied Google Form', () {
    expect(
      clientFeedbackGoogleFormUrl,
      'https://docs.google.com/forms/d/e/1FAIpQLSez67vzLMN0Ziz9tGA9Umc5hw894y8B3sbFyuIX1ADLD4FBjQ/viewform',
    );
    final followUp = ServicesScreen.services.singleWhere(
      (service) => service.title == 'Follow-up Service',
    );
    expect(followUp.hasFeedbackQr, isTrue);
    expect(
      ServicesScreen.services
          .where((service) => service.title != 'Follow-up Service')
          .every((service) => !service.hasFeedbackQr),
      isTrue,
    );
  });

  testWidgets('Follow-up Service shows QR and downloadable PDFs', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final followUp = ServicesScreen.services.singleWhere(
      (service) => service.title == 'Follow-up Service',
    );
    await tester.pumpWidget(
      MaterialApp(home: ServiceDetailScreen(service: followUp)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('client-feedback-qr')), findsOneWidget);
    expect(find.text('Client Feedback Form'), findsOneWidget);
    expect(find.text('Copy form link'), findsOneWidget);
    expect(find.text('Download QR PDF'), findsOneWidget);
    expect(find.text('Download Feedback Sheet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('QR and access-sheet PDFs contain exportable bytes', () async {
    final qr = await buildClientFeedbackQrPdf(accessSheet: false);
    final sheet = await buildClientFeedbackQrPdf(accessSheet: true);
    expect(qr.length, greaterThan(2000));
    expect(sheet.length, greaterThan(2000));
    expect(qr[0], 0x25);
    expect(sheet[0], 0x25);
  });
}
