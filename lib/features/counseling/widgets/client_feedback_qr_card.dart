import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr/qr.dart';

/// Exact PACC Client Feedback Google Form supplied for MindMate Task #47.
const clientFeedbackGoogleFormUrl =
    'https://docs.google.com/forms/d/e/1FAIpQLSez67vzLMN0Ziz9tGA9Umc5hw894y8B3sbFyuIX1ADLD4FBjQ/viewform';

/// Generates a downloadable, offline PDF containing a real QR code.
/// Two download options share the same verified Google Form destination.
Future<Uint8List> buildClientFeedbackQrPdf({required bool accessSheet}) async {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(42),
      build: (context) => pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              'URDANETA CITY UNIVERSITY',
              style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 7),
            pw.Text(
              'Psychological Assessment and Counseling Center',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 12),
            ),
            pw.SizedBox(height: 28),
            pw.Text(
              'CLIENT FEEDBACK FORM',
              style: pw.TextStyle(fontSize: 21, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 26),
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: clientFeedbackGoogleFormUrl,
              width: accessSheet ? 235 : 285,
              height: accessSheet ? 235 : 285,
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'Scan this QR code to open the PACC Google Feedback Form.',
              textAlign: pw.TextAlign.center,
            ),
            if (accessSheet) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                '1. Open your phone camera or QR scanner.',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.Text(
                '2. Scan the QR code and open the Google Form.',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.Text(
                '3. Complete the form online and submit your responses.',
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
            pw.SizedBox(height: 18),
            pw.Text(
              clientFeedbackGoogleFormUrl,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 7),
            ),
          ],
        ),
      ),
    ),
  );
  return doc.save();
}

class ClientFeedbackQrCard extends StatelessWidget {
  const ClientFeedbackQrCard({super.key});

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(
      const ClipboardData(text: clientFeedbackGoogleFormUrl),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Feedback form link copied.')),
    );
  }

  Future<void> _downloadPdf(
    BuildContext context, {
    required bool accessSheet,
  }) async {
    try {
      final bytes = await buildClientFeedbackQrPdf(accessSheet: accessSheet);
      await Printing.sharePdf(
        bytes: bytes,
        filename: accessSheet
            ? 'MindMate_Client_Feedback_Access_Sheet.pdf'
            : 'MindMate_Client_Feedback_QR.pdf',
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save the PDF. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrImage = QrImage(
      QrCode.fromData(
        data: clientFeedbackGoogleFormUrl,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Client Feedback Form',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Scan this QR code to open the PACC Google Client Feedback Form. An internet connection is required to submit the form.',
            ),
            const SizedBox(height: 18),
            Center(
              child: Semantics(
                label: 'QR code for the PACC Client Feedback Google Form',
                image: true,
                child: SizedBox(
                  key: const Key('client-feedback-qr'),
                  width: 256,
                  height: 256,
                  child: CustomPaint(
                    painter: _FeedbackQrPainter(qrImage),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const SelectableText(
              clientFeedbackGoogleFormUrl,
              style: TextStyle(fontSize: 11, color: Color(0xFF555555)),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _copyLink(context),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy form link'),
                ),
                FilledButton.icon(
                  onPressed: () => _downloadPdf(context, accessSheet: false),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download QR PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _downloadPdf(context, accessSheet: true),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Download Feedback Sheet'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'PDF files can be saved or shared using your device options. The form itself is completed online.',
              style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackQrPainter extends CustomPainter {
  _FeedbackQrPainter(this.image);
  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final dimension = size.shortestSide;
    final moduleSize = dimension / (image.moduleCount + 8);
    canvas.drawRect(
      Offset.zero & Size(dimension, dimension),
      Paint()..color = Colors.white,
    );
    final ink = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var row = 0; row < image.moduleCount; row++) {
      for (var column = 0; column < image.moduleCount; column++) {
        if (!image.isDark(row, column)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            (column + 4) * moduleSize,
            (row + 4) * moduleSize,
            moduleSize,
            moduleSize,
          ),
          ink,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FeedbackQrPainter oldDelegate) => false;
}
