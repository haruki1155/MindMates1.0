import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/admin_inquiry_model.dart';

class InquiryPdfService {
  const InquiryPdfService._();

  static Future<Uint8List> build(AdminInquiryModel inquiry) async {
    final document = pw.Document(
      title: inquiry.subject,
      author: 'MindMate PAACC',
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'MindMate | PAACC',
              style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            ),
            pw.Divider(),
          ],
        ),
        build: (_) => [
          pw.Text(
            inquiry.subject,
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 16),
          _row('Submitted by', inquiry.displayName),
          _row('Email', inquiry.email.isEmpty ? 'Not provided' : inquiry.email),
          _row('Category', inquiry.category),
          _row('Status', inquiry.status.label),
          _row('Submitted', inquiry.createdAt.toLocal().toString()),
          pw.SizedBox(height: 18),
          if (inquiry.message.isNotEmpty) ...[
            pw.Text(
              'Message',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 5),
            pw.Text(inquiry.message),
            pw.SizedBox(height: 18),
          ],
          pw.Text(
            'Form responses',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          ...inquiry.formData.entries.map(
            (entry) => _row(entry.key, _value(entry.value)),
          ),
        ],
      ),
    );
    return document.save();
  }

  static Future<void> download(AdminInquiryModel inquiry) async {
    final bytes = await build(inquiry);
    await Printing.sharePdf(bytes: bytes, filename: _fileName(inquiry));
  }

  static Future<void> preview(AdminInquiryModel inquiry) async {
    await Printing.layoutPdf(
      name: _fileName(inquiry),
      onLayout: (_) => build(inquiry),
    );
  }

  static pw.Widget _row(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 130,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Expanded(child: pw.Text(value)),
      ],
    ),
  );

  static String _value(Object? value) {
    if (value is List) return value.join(', ');
    if (value is Map) {
      return value.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
    }
    return value?.toString() ?? 'Not provided';
  }

  static String _fileName(AdminInquiryModel inquiry) {
    final safe = inquiry.subject.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    return '${safe}_${inquiry.id}.pdf';
  }
}
