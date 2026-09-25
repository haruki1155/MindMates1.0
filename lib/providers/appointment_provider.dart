import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/appointment_model.dart';
import '../repositories/appointment_repository.dart';
import '../services/firebase/firebase_error_message.dart';

class AppointmentProvider extends ChangeNotifier {
  AppointmentProvider(this._repository);

  final AppointmentRepository _repository;

  List<AppointmentModel> _appointments = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String? _loadedUserId;
  int _loadGeneration = 0;
  StreamSubscription<List<AppointmentModel>>? _subscription;

  List<AppointmentModel> get appointments => List.unmodifiable(_appointments);
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String? get loadedUserId => _loadedUserId;

  Future<void> loadAppointments(String userId) async {
    final generation = ++_loadGeneration;
    if (_loadedUserId != userId) {
      _loadedUserId = userId;
      _appointments = [];
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final appointments = await _repository.fetchAppointments(userId);
      if (generation != _loadGeneration || _loadedUserId != userId) return;
      _appointments = appointments
          .where((appointment) => appointment.userId == userId)
          .toList(growable: false);
    } catch (_) {
      if (generation != _loadGeneration || _loadedUserId != userId) return;
      _errorMessage = 'Unable to load appointments.';
    } finally {
      if (generation == _loadGeneration && _loadedUserId == userId) {
        _isLoading = false;
        notifyListeners();
      }
    }
    await _subscribe(userId);
  }

  Future<void> _subscribe(String userId) async {
    await _subscription?.cancel();
    _subscription = _repository
        .watchAppointments(userId)
        .listen(
          (appointments) {
            if (_loadedUserId != userId) return;
            _appointments = appointments;
            _errorMessage = null;
            _isLoading = false;
            notifyListeners();
          },
          onError: (_) {
            if (_loadedUserId != userId) return;
            _errorMessage = 'Unable to keep appointments up to date.';
            notifyListeners();
          },
        );
  }

  Future<bool> createAppointment(AppointmentModel appointment) async {
    if (_isSaving) return false;
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final created = await _repository.createAppointment(appointment);
      if (created.userId != appointment.userId) {
        throw StateError('Appointment owner mismatch.');
      }
      final existing = _loadedUserId == appointment.userId
          ? _appointments
          : const <AppointmentModel>[];
      _loadedUserId = appointment.userId;
      _appointments =
          [
              created,
              ...existing,
            ].where((item) => item.userId == appointment.userId).toList()
            ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      return true;
    } catch (error, stackTrace) {
      FirebaseErrorMessage.log(
        error,
        stackTrace,
        area: 'Appointment request failed.',
      );
      _errorMessage = FirebaseErrorMessage.describe(
        error,
        fallback: 'Unable to save appointment. Please try again.',
      );
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> acceptReschedule(String appointmentId) =>
      _performAction(() => _repository.acceptReschedule(appointmentId));

  Future<List<AppointmentSlot>> getAvailableSlots(DateTime date) async {
    try {
      return await _repository.getAvailableSlots(date);
    } catch (error, stackTrace) {
      FirebaseErrorMessage.log(
        error,
        stackTrace,
        area: 'Appointment slots failed.',
      );
      _errorMessage = FirebaseErrorMessage.describe(
        error,
        fallback: 'Unable to load available appointment times.',
      );
      notifyListeners();
      return const [];
    }
  }

  Future<bool> _performAction(Future<void> Function() action) async {
    if (_isSaving) return false;
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (error, stackTrace) {
      FirebaseErrorMessage.log(
        error,
        stackTrace,
        area: 'Appointment action failed.',
      );
      _errorMessage = FirebaseErrorMessage.describe(
        error,
        fallback: 'Unable to update appointment. Please try again.',
      );
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
