import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/models/student_personal_info.dart';

void main() {
  const home = StudentAddress(
    number: '12',
    street: 'Rizal St',
    barangay: 'Poblacion',
    cityTown: 'Pasig',
    province: 'Metro Manila',
    zipCode: '1600',
  );

  StudentPersonalInfo sample({StudentAddress? city}) => StudentPersonalInfo(
    sex: 'Female',
    civilStatus: 'Single',
    spouse: '',
    nationality: 'Filipino',
    placeOfBirth: 'Pasig',
    cityAddress: city,
    homeAddress: home,
    father: 'A',
    fatherOccupation: 'B',
    mother: 'C',
    motherOccupation: 'D',
    guardian: 'E',
    guardianRelationship: 'Aunt',
    guardianAddress: 'Somewhere',
    telephone: '',
    cellphone: '09171234567',
  );

  test('round-trips with null cityAddress', () {
    final json = sample().toJson();
    expect(json['cityAddress'], isNull);
    final back = StudentPersonalInfo.fromJson(json);
    expect(back.cityAddress, isNull);
    expect(back.homeAddress.street, 'Rizal St');
    expect(back.toJson(), json);
  });

  test('round-trips with cityAddress and tolerates Object? maps', () {
    final json = Map<Object?, Object?>.from(sample().toJson());
    json['cityAddress'] = Map<Object?, Object?>.from(home.toJson());
    final back = StudentPersonalInfo.fromJson(json);
    expect(back.cityAddress?.zipCode, '1600');
  });

  test('StudentAddress.isEmpty', () {
    expect(StudentAddress.fromJson(const {}).isEmpty, isTrue);
    expect(home.isEmpty, isFalse);
  });

  test('StudentInformation parses a callable response', () {
    final info = StudentInformation.fromJson({
      'official': {
        'studentNo': '2021-00123',
        'surname': 'Cruz',
        'firstName': 'Ana',
        'middleName': '',
        'dateOfBirth': '2003-04-05',
        'college': 'CCS',
        'course': 'BSIT',
        'yearLevel': '2nd Year',
        'email': 'a@b.c',
      },
      'personal': null,
      'corrections': [
        {
          'id': 'c1',
          'field': 'surname',
          'currentValue': 'Cruz',
          'requestedValue': 'Cruzado',
          'reason': 'typo',
          'status': 'pending',
          'reviewReason': '',
          'createdAt': '2026-11-01T10:00:00.000Z',
        },
      ],
    });
    expect(info.official.surname, 'Cruz');
    expect(info.personal, isNull);
    expect(info.corrections.single.createdAt.isUtc, isTrue);
    expect(info.corrections.single.studentName, '');
  });
}
