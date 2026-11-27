import 'dart:math';

import 'package:flutter/services.dart';

/// Formats Philippine mobile input (`09171234567`, `9171234567`,
/// `+639171234567`) into `+63 9XX XXX XXXX`.
String formatPhilippineMobile(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  if (digits == '0') return '0';
  if (digits == '6' || digits == '63') return '';

  String national;
  if (digits.startsWith('639')) {
    national = digits.substring(2);
  } else if (digits.startsWith('63')) {
    national = digits.substring(2);
  } else if (digits.startsWith('09')) {
    national = digits.substring(1);
  } else if (digits.startsWith('0')) {
    national = digits.substring(1);
  } else {
    national = digits;
  }

  if (national.isEmpty) return '';
  if (national.length > 10) {
    national = national.substring(0, 10);
  }

  final buffer = StringBuffer('+63 ');
  buffer.write(national.substring(0, min(3, national.length)));
  if (national.length > 3) {
    buffer.write(' ');
    buffer.write(national.substring(3, min(6, national.length)));
  }
  if (national.length > 6) {
    buffer.write(' ');
    buffer.write(national.substring(6));
  }
  return buffer.toString();
}

bool isValidPhilippineMobile(String raw) {
  final compact = raw.trim().replaceAll(RegExp(r'[\s\-().]'), '');
  return RegExp(r'^(\+?63|0)?9\d{9}$').hasMatch(compact);
}

class PhilippineMobileInputFormatter extends TextInputFormatter {
  const PhilippineMobileInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatPhilippineMobile(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
