import '../../models/student_personal_info.dart';

/// Client-side mirror of the server's `validatePersonalInfo`. Keys and
/// messages match so server and client errors render the same way.
class StudentInfoValidator {
  const StudentInfoValidator._();

  static const maxText = 160;
  static const civilStatuses = ['Single', 'Married', 'Widowed', 'Separated'];
  static const sexOptions = ['Male', 'Female'];

  static Map<String, String> validate(StudentPersonalInfo info) {
    final errors = <String, String>{};

    void text(String key, String value, bool required, String label) {
      final v = value.trim();
      if (v.length > maxText) {
        errors[key] = '$label must be at most $maxText characters.';
      } else if (required && v.isEmpty) {
        errors[key] = '$label is required.';
      }
    }

    if (!sexOptions.contains(info.sex)) {
      errors['sex'] = 'Select Male or Female.';
    }
    final civil = info.civilStatus.trim();
    if (!civilStatuses.contains(civil)) {
      errors['civilStatus'] = 'Select a valid civil status.';
    }
    text('spouse', info.spouse, civil == 'Married', 'Spouse');
    text('nationality', info.nationality, true, 'Nationality');
    text('placeOfBirth', info.placeOfBirth, true, 'Place of birth');

    void address(String key, String label, StudentAddress? a) {
      if (a == null || a.isEmpty && key == 'cityAddress') return;
      final parts = {
        'number': a.number,
        'street': a.street,
        'barangay': a.barangay,
        'cityTown': a.cityTown,
        'province': a.province,
        'zipCode': a.zipCode,
      };
      const required = {
        'barangay': 'Barangay',
        'cityTown': 'City / Town',
        'province': 'Province',
      };
      parts.forEach((field, raw) {
        final v = raw.trim();
        final path = '$key.$field';
        if (v.length > maxText) {
          errors[path] = '$label $field must be at most $maxText characters.';
        } else if (required.containsKey(field) && v.isEmpty) {
          errors[path] = '${required[field]} is required.';
        }
      });
      final zip = a.zipCode.trim();
      if (zip.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(zip)) {
        errors['$key.zipCode'] = 'Zip code must be 4 digits.';
      }
    }

    address('cityAddress', 'City address', info.cityAddress);
    address(
      'homeAddress',
      'Home address',
      info.homeAddress.isEmpty
          ? const StudentAddress(
              number: '',
              street: '',
              barangay: '',
              cityTown: '',
              province: '',
              zipCode: '',
            )
          : info.homeAddress,
    );

    text('father', info.father, false, 'Father');
    text(
      'fatherOccupation',
      info.fatherOccupation,
      false,
      "Father's occupation",
    );
    text('mother', info.mother, false, 'Mother');
    text(
      'motherOccupation',
      info.motherOccupation,
      false,
      "Mother's occupation",
    );
    text('guardian', info.guardian, true, 'Guardian');
    text(
      'guardianRelationship',
      info.guardianRelationship,
      true,
      'Guardian relationship',
    );
    text('guardianAddress', info.guardianAddress, true, 'Guardian address');
    text('telephone', info.telephone, false, 'Telephone');

    final cell = info.cellphone.trim();
    if (cell.isEmpty) {
      errors['cellphone'] = 'Cellphone is required.';
    } else if (normalizeCellphone(cell) == null) {
      errors['cellphone'] = 'Enter a valid Philippine mobile number.';
    }
    return errors;
  }

  /// Returns the `09XXXXXXXXX` form, or null when [value] is not valid.
  static String? normalizeCellphone(String value) {
    final digits = value.replaceAll(RegExp(r'[\s-]'), '');
    final m = RegExp(r'^(?:\+63|63|0)(9\d{9})$').firstMatch(digits);
    return m == null ? null : '0${m.group(1)}';
  }
}
