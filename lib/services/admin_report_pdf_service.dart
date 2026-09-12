import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../features/admin/domain/report_generation_models.dart';

class AdminReportPdfService {
  const AdminReportPdfService._();

  static const _colors = <PdfColor>[
    PdfColor.fromInt(0xFFB89400),
    PdfColor.fromInt(0xFF3F7257),
    PdfColor.fromInt(0xFF6D5E9C),
    PdfColor.fromInt(0xFF4F7799),
    PdfColor.fromInt(0xFFB7654D),
    PdfColor.fromInt(0xFF7D7D75),
  ];

  static Future<Uint8List> build({
    required AdminReportAnalytics report,
    required AdminReportType reportType,
    required ReportChartType chartType,
    String userCategoryKey = 'all',
    AppointmentReportDimension appointmentDimension =
        AppointmentReportDimension.department,
  }) async {
    final document = pw.Document(
      title: reportType == AdminReportType.users
          ? 'App User Activity Report'
          : 'Counseling Appointments Report',
      author: 'MindMate PAACC',
      subject: 'Privacy-preserving aggregate report',
    );
    final data = reportType == AdminReportType.users
        ? _userData(report, userCategoryKey)
        : report.appointmentsFor(appointmentDimension);
    final chartData = _compact(data);
    final title = reportType == AdminReportType.users
        ? 'App User Activity Report - ${report.userScopeLabel}'
        : 'Counseling Appointments - ${report.appointmentDepartmentScopeLabel}';

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(42),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'MindMate | PAACC',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  'CONFIDENTIAL | AGGREGATE DATA',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.Divider(color: PdfColors.grey400),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (_) => [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 23, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            reportType == AdminReportType.users
                ? 'Active means activity recorded within the last ${report.activeWindowDays} days.'
                : 'Grouped by ${_dimensionLabel(appointmentDimension)}. Only appointments within the selected department scope are included.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Generated ${_dateTime(report.generatedAt.toLocal())}. Counts and personal identifiers are intentionally omitted.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 24),
          if (data.isEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Text(
                'No reportable data is available for this category.',
              ),
            )
          else
            pw.SizedBox(
              height: 270,
              child: chartType == ReportChartType.pie
                  ? _pieChart(chartData)
                  : _barChart(chartData),
            ),
          pw.SizedBox(height: 24),
          pw.Text(
            'Percentage summary',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (data.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headers: const ['Category', 'Share / rate'],
              data: data
                  .map((item) => [item.label, _percent(item.percentage)])
                  .toList(growable: false),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 7,
              ),
              border: pw.TableBorder.all(color: PdfColors.grey300),
            ),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFFFFBE8),
            ),
            child: pw.Text(
              'Privacy note: this report contains aggregate percentages only. Admin, counselor, and other portal accounts are excluded from the app-user population and appointment joins.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
            ),
          ),
        ],
      ),
    );
    return document.save();
  }

  static Future<void> download({
    required AdminReportAnalytics report,
    required AdminReportType reportType,
    required ReportChartType chartType,
    String userCategoryKey = 'all',
    AppointmentReportDimension appointmentDimension =
        AppointmentReportDimension.department,
  }) async {
    final bytes = await build(
      report: report,
      reportType: reportType,
      chartType: chartType,
      userCategoryKey: userCategoryKey,
      appointmentDimension: appointmentDimension,
    );
    final scope = reportType == AdminReportType.users
        ? report.userScopeLabel
        : report.appointmentDepartmentScopeLabel;
    final type = reportType == AdminReportType.users
        ? 'app_users_${_safe(scope)}'
        : 'appointments_${_safe(scope)}';
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'mindmate_${type}_${_date(report.generatedAt)}.pdf',
    );
  }

  static List<ReportPercentageItem> _userData(
    AdminReportAnalytics report,
    String categoryKey,
  ) {
    final active = categoryKey == 'all'
        ? report.overallActivePercentage
        : report.userCategories
                  .where((category) => category.key == categoryKey)
                  .map((category) => category.activePercentage)
                  .firstOrNull ??
              0;
    return [
      ReportPercentageItem(
        key: 'active',
        label: 'Active app users',
        percentage: active,
      ),
      ReportPercentageItem(
        key: 'inactive',
        label: 'No activity in reporting window',
        percentage: 100 - active,
      ),
    ];
  }

  static pw.Widget _pieChart(List<ReportPercentageItem> data) {
    var colorIndex = 0;
    return pw.Chart(
      grid: pw.PieGrid(),
      datasets: [
        for (final item in data.where((item) => item.percentage > 0))
          pw.PieDataSet(
            value: item.percentage,
            legend: '${item.label} ${_percent(item.percentage)}',
            color: _colors[(colorIndex++) % _colors.length],
            legendPosition: pw.PieLegendPosition.outside,
          ),
      ],
    );
  }

  static pw.Widget _barChart(List<ReportPercentageItem> data) => pw.Column(
    mainAxisAlignment: pw.MainAxisAlignment.center,
    children: [
      for (var index = 0; index < data.length; index++) ...[
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                data[index].label,
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            pw.Text(
              _percent(data[index].percentage),
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Container(
          height: 15,
          alignment: pw.Alignment.centerLeft,
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          child: pw.Container(
            width: 4.2 * data[index].percentage.clamp(0, 100),
            color: _colors[index % _colors.length],
          ),
        ),
        pw.SizedBox(height: 14),
      ],
    ],
  );

  static String _dimensionLabel(AppointmentReportDimension dimension) =>
      switch (dimension) {
        AppointmentReportDimension.department => 'Department',
        AppointmentReportDimension.course => 'Course',
        AppointmentReportDimension.yearLevel => 'Year Level',
      };

  static List<ReportPercentageItem> _compact(List<ReportPercentageItem> items) {
    if (items.length <= 8) return items;
    final visible = items.take(7).toList(growable: true);
    final remaining = items
        .skip(7)
        .fold<double>(0, (total, item) => total + item.percentage);
    visible.add(
      ReportPercentageItem(
        key: 'remaining',
        label: 'Remaining categories',
        percentage: remaining.clamp(0, 100),
      ),
    );
    return visible;
  }

  static String _percent(double value) {
    final rounded = value.roundToDouble() == value
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$rounded%';
  }

  static String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _dateTime(DateTime date) =>
      '${_date(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  static String _safe(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}
