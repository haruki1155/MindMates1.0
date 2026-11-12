import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/authentication/auth_flow_routes.dart';
import 'package:mind_mates/features/student_info/student_info_validator.dart';
import 'package:mind_mates/models/profile_roles.dart';
import 'package:mind_mates/models/student_personal_info.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/routes/route_names.dart';

StudentAddress _address({String zip = ''}) => StudentAddress(
  number: '1',
  street: 'Main St',
  barangay: 'Poblacion',
  cityTown: 'Alaminos',
  province: 'Pangasinan',
  zipCode: zip,
);

StudentPersonalInfo _info({
  String sex = 'Male',
  String civilStatus = 'Single',
  String spouse = '',
  StudentAddress? cityAddress,
  StudentAddress? homeAddress,
  String guardian = 'Ana Cruz',
  String cellphone = '09171234567',
}) => StudentPersonalInfo(
  sex: sex,
  civilStatus: civilStatus,
  spouse: spouse,
  nationality: 'Filipino',
  placeOfBirth: 'Alaminos',
  cityAddress: cityAddress,
  homeAddress: homeAddress ?? _address(),
  father: '',
  fatherOccupation: '',
  mother: '',
  motherOccupation: '',
  guardian: guardian,
  guardianRelationship: 'Mother',
  guardianAddress: 'Alaminos City',
  telephone: '',
  cellphone: cellphone,
);

void main() {
  group('StudentInfoValidator', () {
    test('accepts a valid form', () {
      expect(StudentInfoValidator.validate(_info()), isEmpty);
    });

    test('spouse required only when Married', () {
      expect(
        StudentInfoValidator.validate(_info(civilStatus: 'Married')),
        containsPair('spouse', 'Spouse is required.'),
      );
      expect(
        StudentInfoValidator.validate(
          _info(civilStatus: 'Married', spouse: 'Leo'),
        ),
        isEmpty,
      );
    });

    test('home address parts and zip', () {
      final errors = StudentInfoValidator.validate(
        _info(
          homeAddress: const StudentAddress(
            number: '',
            street: '',
            barangay: '',
            cityTown: '',
            province: '',
            zipCode: '12a',
          ),
        ),
      );
      expect(errors['homeAddress.barangay'], 'Barangay is required.');
      expect(errors['homeAddress.cityTown'], 'City / Town is required.');
      expect(errors['homeAddress.province'], 'Province is required.');
      expect(errors['homeAddress.zipCode'], 'Zip code must be 4 digits.');
    });

    test('city address optional but validated when partly filled', () {
      expect(StudentInfoValidator.validate(_info(cityAddress: null)), isEmpty);
      final errors = StudentInfoValidator.validate(
        _info(
          cityAddress: const StudentAddress(
            number: '',
            street: 'x',
            barangay: '',
            cityTown: '',
            province: '',
            zipCode: '',
          ),
        ),
      );
      expect(errors, contains('cityAddress.barangay'));
    });

    test('cellphone normalization', () {
      for (final ok in [
        '09171234567',
        '+639171234567',
        '639171234567',
        '0917 123-4567',
      ]) {
        expect(
          StudentInfoValidator.validate(_info(cellphone: ok)),
          isEmpty,
          reason: ok,
        );
      }
      expect(
        StudentInfoValidator.validate(_info(cellphone: '12345')),
        containsPair('cellphone', 'Enter a valid Philippine mobile number.'),
      );
      expect(
        StudentInfoValidator.validate(_info(cellphone: '')),
        containsPair('cellphone', 'Cellphone is required.'),
      );
    });

    test('guardian fields required, sex and status checked', () {
      final errors = StudentInfoValidator.validate(
        _info(guardian: '', sex: '', civilStatus: ''),
      );
      expect(errors['guardian'], 'Guardian is required.');
      expect(errors['sex'], 'Select Male or Female.');
      expect(errors['civilStatus'], 'Select a valid civil status.');
    });

    test('text over 160 chars is rejected', () {
      expect(
        StudentInfoValidator.validate(_info(guardian: 'a' * 161)),
        contains('guardian'),
      );
    });
  });

  group('gateRouteForUser', () {
    test('student needing info goes to the information screen first', () {
      const user = UserModel(
        id: 'u',
        email: 'a@b.c',
        populationRole: PopulationRole.student,
        personalInfoRequired: true,
        profileVersion: 3,
      );
      expect(gateRouteForUser(user), RouteNames.studentInformation);
    });

    test('teaching user with the flag is not sent to the info route', () {
      const user = UserModel(
        id: 'u',
        email: 'a@b.c',
        populationRole: PopulationRole.teaching,
        personalInfoRequired: true,
        profileVersion: 3,
      );
      expect(gateRouteForUser(user), RouteNames.profileSetup);
    });

    test('incomplete v3 profile goes to profile setup', () {
      const user = UserModel(id: 'u', email: 'a@b.c', profileVersion: 3);
      expect(gateRouteForUser(user), RouteNames.profileSetup);
    });

    test('nothing pending returns null', () {
      const user = UserModel(id: 'u', email: 'a@b.c');
      expect(gateRouteForUser(user), isNull);
    });
  });
}
