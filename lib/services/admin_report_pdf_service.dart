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
    final emotional = report.emotionalActivity;
    final emotionalParticipation =
        emotional.participationRate ?? emotional.appUserCohortShare;
    final visibleUserCategories = userCategoryKey == 'all'
        ? report.userCategories
        : report.userCategories
              .where((item) => item.key == userCategoryKey)
              .toList(growable: false);
    final document = pw.Document(
      title: switch (reportType) {
        AdminReportType.users => 'App User Activity Report',
        AdminReportType.appointments => 'Counseling Appointments Report',
        AdminReportType.emotionalActivity => 'Emotional Activity Report',
      },
      author: 'MindMate PACC',
      subject: 'Privacy-preserving aggregate report',
    );
    final showAppointmentDistribution =
        report.population.configured &&
        report.totalAppointments > 0 &&
        report.uniqueStudentsServed >= 5;
    final data = switch (reportType) {
      AdminReportType.users => _userData(report, userCategoryKey),
      AdminReportType.appointments =>
        showAppointmentDistribution
            ? report.appointmentsFor(appointmentDimension)
            : const <ReportPercentageItem>[],
      AdminReportType.emotionalActivity =>
        emotional.isReady
            ? emotional.valenceBreakdown
                  .where((item) => !item.suppressed && item.percentage != null)
                  .map(
                    (item) => ReportPercentageItem(
                      key: item.key,
                      label: item.label,
                      percentage: item.percentage!,
                    ),
                  )
                  .toList(growable: false)
            : const <ReportPercentageItem>[],
    };
    final chartData = _compact(data);
    final filters = report.filters;
    final activeYear = filters.schoolYear.isNotEmpty
        ? filters.schoolYear
        : report.population.schoolYear;
    final activeCollege = filters.collegeKey != 'all'
        ? filters.collegeLabel
        : report.appointmentDepartmentScopeLabel;
    final activeProgram = filters.programKey != 'all'
        ? filters.programLabel
        : 'All programs';
    final activeCategory = filters.userCategory != 'all'
        ? filters.userCategoryLabel
        : report.userScopeLabel;
    final title = switch (reportType) {
      AdminReportType.users => 'App User Activity Report - $activeCategory',
      AdminReportType.appointments =>
        'Counseling Appointments - $activeCollege',
      AdminReportType.emotionalActivity =>
        'Emotional Activity Report - $activeYear',
    };
    final subtitle = switch (reportType) {
      AdminReportType.users =>
        'Year: $activeYear | Period: ${filters.periodLabel} | Category: $activeCategory | College: $activeCollege | Program: $activeProgram | Active window: ${report.activeWindowDays} days.',
      AdminReportType.appointments =>
        'Year: $activeYear | Period: ${filters.periodLabel} | College: $activeCollege | Program: $activeProgram | Category: $activeCategory | Grouped by ${_dimensionLabel(appointmentDimension)}.',
      AdminReportType.emotionalActivity =>
        'Year: $activeYear | Period: ${emotional.dateRangeLabel} | ${emotional.sourceScopeLabel} | Category: $activeCategory | College: $activeCollege | Program: $activeProgram.',
    };

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
                  'MindMate | PACC',
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
            subtitle,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Generated ${_dateTime(report.generatedAt.toLocal())}. Raw notes, questionnaire answers, photos, and personal identifiers are intentionally omitted.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 24),
          if (reportType == AdminReportType.appointments) ...[
            _summaryMetricsTable(
              'Appointment summary',
              [
                ['Total appointments', '${report.totalAppointments}'],
                ['Unique students served', '${report.uniqueStudentsServed}'],
                [
                  'Counseling reach',
                  report.population.configured
                      ? _percent(report.counselingReach)
                      : 'Not available',
                ],
                ['Completion rate', _percent(report.completionRate)],
                [
                  'Appointment rate',
                  report.population.configured
                      ? _percent(report.appointmentRate)
                      : 'Not available',
                ],
                [
                  'Waiting time',
                  report.waitingTimeDays == null
                      ? 'No data'
                      : '${report.waitingTimeDays!.toStringAsFixed(1)} days',
                ],
                ['Rescheduled', '${report.rescheduledAppointments}'],
              ],
            ),
            pw.SizedBox(height: 18),
          ],
          if (reportType == AdminReportType.emotionalActivity &&
              emotional.isReady) ...[
            _summaryMetricsTable(
              'Emotional activity summary',
              [
                [
                  'Population participation',
                  emotionalParticipation == null
                      ? 'Not available'
                      : _percent(emotionalParticipation),
                ],
                [
                  'Primary emotional pattern',
                  emotional.dominantValenceLabel ??
                      'Suppressed (n < ${emotional.suppressionThreshold})',
                ],
                if (emotional.moodCheckInShare != null &&
                    emotional.assessmentShare != null)
                  [
                    'Mood vs assessments mix',
                    '${_percent(emotional.moodCheckInShare!)} mood / ${_percent(emotional.assessmentShare!)} assessment',
                  ],
              ],
            ),
            pw.SizedBox(height: 18),
          ],
          if (reportType == AdminReportType.emotionalActivity &&
              emotional.suppressed)
            _noticeBox(
              emotional.suppressionReason ??
                  'Results suppressed to protect privacy (n < ${emotional.suppressionThreshold}).',
            )
          else if (reportType == AdminReportType.appointments &&
              !report.population.configured)
            _noticeBox(
              'Complete and save the student population in Report setup below to calculate population-based percentages. Appointment counts remain available.',
            )
          else if (reportType == AdminReportType.appointments &&
              report.totalAppointments == 0)
            _noticeBox(
              'No counseling appointments matched the selected filters.',
            )
          else if (reportType == AdminReportType.appointments &&
              report.uniqueStudentsServed < 5)
            _noticeBox(
              'Distribution details are hidden because this report contains fewer than 5 unique students. Aggregate totals remain available.',
            )
          else if (data.isEmpty)
            _noticeBox(
              reportType == AdminReportType.emotionalActivity
                  ? (emotional.isReady
                        ? 'Chart omitted: all category distributions are suppressed to protect privacy (n < ${emotional.suppressionThreshold}).'
                        : 'No reportable emotional activity data is available for the selected filters.')
                  : 'No reportable data is available for this category.',
            )
          else if (chartType == ReportChartType.pie &&
              !chartData.any(
                (item) => item.percentage.isFinite && item.percentage > 0,
              ))
            _noticeBox(
              'Chart omitted: no non-zero percentages are available for the selected filters.',
            )
          else if (chartType == ReportChartType.pie)
            pw.SizedBox(height: 270, child: _pieChart(chartData))
          else
            _barChart(chartData),
          if (reportType == AdminReportType.emotionalActivity &&
              emotional.isReady &&
              (emotional.valenceBreakdown.isNotEmpty ||
                  emotional.moodBreakdown.isNotEmpty ||
                  emotional.assessmentBreakdown.isNotEmpty ||
                  emotional.periodTrends.isNotEmpty)) ...[
            pw.SizedBox(height: 24),
            pw.Text(
              'Percentage summary',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            if (emotional.valenceBreakdown.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              _emotionalTable(
                'Emotional valence summary',
                const ['Pattern', 'Share'],
                emotional.valenceBreakdown,
                emotional.suppressionThreshold,
              ),
            ],
            if (emotional.moodBreakdown.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              _emotionalTable(
                'Mood check-in breakdown',
                const ['Mood state', 'Share'],
                emotional.moodBreakdown,
                emotional.suppressionThreshold,
              ),
            ],
            if (emotional.assessmentBreakdown.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              _emotionalTable(
                'Well-being assessment breakdown',
                const ['Assessment pattern', 'Share'],
                emotional.assessmentBreakdown,
                emotional.suppressionThreshold,
              ),
            ],
            if (emotional.periodTrends.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              _emotionalTable(
                'Monthly emotional activity trend',
                const ['Period', 'Share of activity'],
                emotional.periodTrends,
                emotional.suppressionThreshold,
              ),
            ],
          ] else if (reportType != AdminReportType.emotionalActivity &&
              data.isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Text(
              'Percentage summary',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
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
            if (reportType == AdminReportType.users &&
                visibleUserCategories.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                userCategoryKey == 'all'
                    ? 'App users per category'
                    : 'Selected app-user category only',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headers: const ['Category', 'Population share', 'Active rate'],
                data: visibleUserCategories
                    .map(
                      (item) => [
                        item.label,
                        _percent(item.populationPercentage),
                        _percent(item.activePercentage),
                      ],
                    )
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
            ],
          ],
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

  static String filenameFor(
    AdminReportAnalytics report,
    AdminReportType reportType,
  ) {
    final activeYear = report.filters.schoolYear.isNotEmpty
        ? report.filters.schoolYear
        : report.population.schoolYear;
    final scope = switch (reportType) {
      AdminReportType.users => report.userScopeLabel,
      AdminReportType.appointments => report.appointmentDepartmentScopeLabel,
      AdminReportType.emotionalActivity =>
        '${activeYear}_${report.appointmentDepartmentScopeLabel}',
    };
    final programSuffix = report.filters.programKey != 'all'
        ? '_${_safe(report.filters.programLabel)}'
        : '';
    final type = switch (reportType) {
      AdminReportType.users => 'app_users_${_safe(scope)}$programSuffix',
      AdminReportType.appointments =>
        'appointments_${_safe(scope)}$programSuffix',
      AdminReportType.emotionalActivity =>
        'emotional_activity_${_safe(scope)}$programSuffix',
    };
    return 'mindmate_${type}_${_date(report.generatedAt)}.pdf';
  }

  static Future<void> download({
    required AdminReportAnalytics report,
    required AdminReportType reportType,
    required ReportChartType chartType,
    String userCategoryKey = 'all',
    AppointmentReportDimension appointmentDimension =
        AppointmentReportDimension.department,
    Uint8List? prebuiltBytes,
  }) async {
    final bytes =
        prebuiltBytes ??
        await build(
          report: report,
          reportType: reportType,
          chartType: chartType,
          userCategoryKey: userCategoryKey,
          appointmentDimension: appointmentDimension,
        );
    await Printing.sharePdf(
      bytes: bytes,
      filename: filenameFor(report, reportType),
    );
  }

  static pw.Widget _noticeBox(String message) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(20),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      border: pw.Border.all(color: PdfColors.grey300),
    ),
    child: pw.Text(message),
  );

  static pw.Widget _summaryMetricsTable(
    String title,
    List<List<String>> rows,
  ) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        headers: const ['Metric', 'Value'],
        data: rows,
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        border: pw.TableBorder.all(color: PdfColors.grey300),
      ),
    ],
  );

  static List<ReportPercentageItem> _userData(
    AdminReportAnalytics report,
    String categoryKey,
  ) {
    if (report.userCategories.isEmpty) return const [];
    final selected = report.userCategories
        .where((category) => category.key == categoryKey)
        .firstOrNull;
    if (categoryKey != 'all' && selected == null) return const [];
    final active = categoryKey == 'all'
        ? report.overallActivePercentage
        : selected!.activePercentage;
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
        for (final item in data.where(
          (item) => item.percentage.isFinite && item.percentage > 0,
        ))
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
            width:
                4.2 *
                (data[index].percentage.isFinite ? data[index].percentage : 0)
                    .clamp(0, 100),
            color: _colors[index % _colors.length],
          ),
        ),
        pw.SizedBox(height: 14),
      ],
    ],
  );

  static pw.Widget _emotionalTable(
    String sectionTitle,
    List<String> headers,
    List<EmotionalActivityBucket> buckets,
    int suppressionThreshold,
  ) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        sectionTitle,
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: buckets
            .map(
              (item) => [
                item.label,
                item.suppressed || item.percentage == null
                    ? 'Suppressed (n < $suppressionThreshold)'
                    : _percent(item.percentage!),
              ],
            )
            .toList(growable: false),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        border: pw.TableBorder.all(color: PdfColors.grey300),
      ),
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
        .fold<double>(
          0,
          (total, item) =>
              total + (item.percentage.isFinite ? item.percentage : 0),
        );
    visible.add(
      ReportPercentageItem(
        key: 'remaining',
        label: 'Remaining categories',
        percentage: remaining.isFinite ? remaining.clamp(0, 100) : 0,
      ),
    );
    return visible;
  }

  static String _percent(double value) {
    final safe = value.isFinite ? value : 0.0;
    final rounded = safe.roundToDouble() == safe
        ? safe.toStringAsFixed(0)
        : safe.toStringAsFixed(1);
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
