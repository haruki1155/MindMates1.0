import 'package:flutter/foundation.dart';

import '../models/assessment_explanation_model.dart';
import '../models/report_model.dart';
import '../repositories/report_repository.dart';

class ReportProvider extends ChangeNotifier {
  ReportProvider(this._repository);

  final ReportRepository _repository;

  ReportModel? _latestReport;
  bool _isLoading = false;
  String? _errorMessage;

  ReportModel? get latestReport => _latestReport;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<V4AssessmentResponseReviewData?> fetchLatestV4ResponseReview(
    String userId,
  ) => _repository.fetchLatestV4ResponseReview(userId);

  Future<void> loadLatestReport(String userId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _latestReport = await _repository.fetchLatestReport(userId);
    } catch (error, stackTrace) {
      debugPrint('Unable to load mental health summary: $error');
      debugPrintStack(stackTrace: stackTrace);
      _errorMessage = 'Unable to load mental health summary.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> ensureWeeklyPlaceholder(String userId) async {
    if (_latestReport != null) return;

    try {
      await _repository.createPlaceholderWeeklyReport(userId);
      await loadLatestReport(userId);
    } catch (error, stackTrace) {
      debugPrint('Unable to prepare mental health summary: $error');
      debugPrintStack(stackTrace: stackTrace);
      _errorMessage = 'Unable to prepare mental health summary.';
      notifyListeners();
    }
  }

  Future<void> refreshWeeklyReport(String userId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.generateWeeklyReport(userId);
      _latestReport = await _repository.fetchLatestReport(userId);
    } catch (error, stackTrace) {
      debugPrint('Unable to refresh mental health summary: $error');
      debugPrintStack(stackTrace: stackTrace);
      _errorMessage = 'Unable to refresh mental health summary.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
