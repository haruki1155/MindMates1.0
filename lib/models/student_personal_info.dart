/// Models for the Student Information form and the callable responses that
/// carry it. Callable payloads arrive as `Map<Object?, Object?>`, so every
/// parser here converts defensively.
library;

Map<String, Object?> asStringMap(Object? value) {
  if (value is Map) {
    return {for (final e in value.entries) e.key.toString(): e.value};
  }
  return const {};
}

List<Object?> asList(Object? value) => value is List ? value : const [];

String asText(Object? value) => value?.toString() ?? '';

DateTime parseIso(Object? value) {
  final parsed = DateTime.tryParse(asText(value));
  return parsed ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

class StudentAddress {
  const StudentAddress({
    required this.number,
    required this.street,
    required this.barangay,
    required this.cityTown,
    required this.province,
    required this.zipCode,
  });

  final String number;
  final String street;
  final String barangay;
  final String cityTown;
  final String province;
  final String zipCode;

  bool get isEmpty =>
      [
        number,
        street,
        barangay,
        cityTown,
        province,
        zipCode,
      ].every((part) => part.trim().isEmpty);

  factory StudentAddress.fromJson(Map<Object?, Object?> json) {
    final map = asStringMap(json);
    return StudentAddress(
      number: asText(map['number']),
      street: asText(map['street']),
      barangay: asText(map['barangay']),
      cityTown: asText(map['cityTown']),
      province: asText(map['province']),
      zipCode: asText(map['zipCode']),
    );
  }

  Map<String, Object?> toJson() => {
    'number': number,
    'street': street,
    'barangay': barangay,
    'cityTown': cityTown,
    'province': province,
    'zipCode': zipCode,
  };
}

class StudentPersonalInfo {
  const StudentPersonalInfo({
    required this.sex,
    required this.civilStatus,
    required this.spouse,
    required this.nationality,
    required this.placeOfBirth,
    required this.cityAddress,
    required this.homeAddress,
    required this.father,
    required this.fatherOccupation,
    required this.mother,
    required this.motherOccupation,
    required this.guardian,
    required this.guardianRelationship,
    required this.guardianAddress,
    required this.telephone,
    required this.cellphone,
  });

  final String sex;
  final String civilStatus;
  final String spouse;
  final String nationality;
  final String placeOfBirth;
  final StudentAddress? cityAddress;
  final StudentAddress homeAddress;
  final String father;
  final String fatherOccupation;
  final String mother;
  final String motherOccupation;
  final String guardian;
  final String guardianRelationship;
  final String guardianAddress;
  final String telephone;
  final String cellphone;

  factory StudentPersonalInfo.fromJson(Map<Object?, Object?> json) {
    final map = asStringMap(json);
    final city = map['cityAddress'];
    return StudentPersonalInfo(
      sex: asText(map['sex']),
      civilStatus: asText(map['civilStatus']),
      spouse: asText(map['spouse']),
      nationality: asText(map['nationality']),
      placeOfBirth: asText(map['placeOfBirth']),
      cityAddress: city is Map ? StudentAddress.fromJson(city) : null,
      homeAddress: StudentAddress.fromJson(asStringMap(map['homeAddress'])),
      father: asText(map['father']),
      fatherOccupation: asText(map['fatherOccupation']),
      mother: asText(map['mother']),
      motherOccupation: asText(map['motherOccupation']),
      guardian: asText(map['guardian']),
      guardianRelationship: asText(map['guardianRelationship']),
      guardianAddress: asText(map['guardianAddress']),
      telephone: asText(map['telephone']),
      cellphone: asText(map['cellphone']),
    );
  }

  Map<String, Object?> toJson() => {
    'sex': sex,
    'civilStatus': civilStatus,
    'spouse': spouse,
    'nationality': nationality,
    'placeOfBirth': placeOfBirth,
    'cityAddress': cityAddress?.toJson(),
    'homeAddress': homeAddress.toJson(),
    'father': father,
    'fatherOccupation': fatherOccupation,
    'mother': mother,
    'motherOccupation': motherOccupation,
    'guardian': guardian,
    'guardianRelationship': guardianRelationship,
    'guardianAddress': guardianAddress,
    'telephone': telephone,
    'cellphone': cellphone,
  };
}

class StudentOfficialInfo {
  const StudentOfficialInfo({
    required this.studentNo,
    required this.surname,
    required this.firstName,
    required this.middleName,
    required this.dateOfBirth,
    required this.college,
    required this.course,
    required this.yearLevel,
    required this.email,
  });

  final String studentNo;
  final String surname;
  final String firstName;
  final String middleName;

  /// `YYYY-MM-DD` key, as sent by the server.
  final String dateOfBirth;
  final String college;
  final String course;
  final String yearLevel;
  final String email;

  factory StudentOfficialInfo.fromJson(Map<Object?, Object?> json) {
    final map = asStringMap(json);
    return StudentOfficialInfo(
      studentNo: asText(map['studentNo']),
      surname: asText(map['surname']),
      firstName: asText(map['firstName']),
      middleName: asText(map['middleName']),
      dateOfBirth: asText(map['dateOfBirth']),
      college: asText(map['college']),
      course: asText(map['course']),
      yearLevel: asText(map['yearLevel']),
      email: asText(map['email']),
    );
  }
}

/// A correction request. The student view leaves [userId], [studentNo] and
/// [studentName] empty; the admin view fills them.
class StudentCorrection {
  const StudentCorrection({
    required this.id,
    required this.field,
    required this.currentValue,
    required this.requestedValue,
    required this.reason,
    required this.status,
    required this.reviewReason,
    required this.createdAt,
    this.userId = '',
    this.studentNo = '',
    this.studentName = '',
  });

  final String id;
  final String field;
  final String currentValue;
  final String requestedValue;
  final String reason;
  final String status;
  final String reviewReason;
  final DateTime createdAt;
  final String userId;
  final String studentNo;
  final String studentName;

  factory StudentCorrection.fromJson(Map<Object?, Object?> json) {
    final map = asStringMap(json);
    return StudentCorrection(
      id: asText(map['id']),
      field: asText(map['field']),
      currentValue: asText(map['currentValue']),
      requestedValue: asText(map['requestedValue']),
      reason: asText(map['reason']),
      status: asText(map['status']),
      reviewReason: asText(map['reviewReason']),
      createdAt: parseIso(map['createdAt']),
      userId: asText(map['userId']),
      studentNo: asText(map['studentNo']),
      studentName: asText(map['studentName']),
    );
  }
}

class StudentInformation {
  const StudentInformation({
    required this.official,
    required this.personal,
    required this.corrections,
  });

  final StudentOfficialInfo official;
  final StudentPersonalInfo? personal;
  final List<StudentCorrection> corrections;

  factory StudentInformation.fromJson(Map<Object?, Object?> json) {
    final map = asStringMap(json);
    final personal = map['personal'];
    return StudentInformation(
      official: StudentOfficialInfo.fromJson(asStringMap(map['official'])),
      personal: personal is Map ? StudentPersonalInfo.fromJson(personal) : null,
      corrections: [
        for (final c in asList(map['corrections']))
          StudentCorrection.fromJson(asStringMap(c)),
      ],
    );
  }
}
