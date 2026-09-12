import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_mates/features/authentication/screens/profile_setup_screen.dart';
import 'package:mind_mates/models/user_model.dart';
import 'package:mind_mates/providers/user_provider.dart';
import 'package:mind_mates/repositories/user_repository.dart';
import 'package:mind_mates/routes/route_names.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('selected profile photo uploads before opening onboarding', (
    tester,
  ) async {
    final repository = _ProfileSetupRepository();
    final provider = UserProvider(repository)
      ..setUser(
        const UserModel(
          id: 'user_1',
          email: 'student@example.com',
          firstName: 'Leonardo',
        ),
      );

    await tester.pumpWidget(
      _profileSetupApp(
        provider,
        imagePicker: () async =>
            ProfileSetupImage(bytes: _onePixelPng, contentType: 'image/png'),
      ),
    );

    await tester.tap(find.text('Add a photo (optional)'));
    await tester.pumpAndSettle();
    expect(find.text('Change photo'), findsOneWidget);

    await tester.ensureVisible(find.text('Continue to MindMate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to MindMate'));
    await tester.pumpAndSettle();

    expect(repository.uploadCalls, 1);
    expect(repository.uploadedContentType, 'image/png');
    expect(repository.updatedUser?.profileSetupCompleted, isTrue);
    expect(find.text('Onboarding target'), findsOneWidget);
  });

  testWidgets('optional photo upload failure does not block profile setup', (
    tester,
  ) async {
    final repository = _ProfileSetupRepository(shouldFailUpload: true);
    final provider = UserProvider(repository)
      ..setUser(
        const UserModel(
          id: 'user_1',
          email: 'student@example.com',
          firstName: 'Leonardo',
        ),
      );

    await tester.pumpWidget(
      _profileSetupApp(
        provider,
        imagePicker: () async =>
            ProfileSetupImage(bytes: _onePixelPng, contentType: 'image/png'),
      ),
    );

    await tester.tap(find.text('Add a photo (optional)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continue to MindMate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to MindMate'));
    await tester.pumpAndSettle();

    expect(repository.uploadCalls, 1);
    expect(repository.updatedUser?.profileSetupCompleted, isTrue);
    expect(find.text('Onboarding target'), findsOneWidget);
    expect(find.textContaining('photo could not be uploaded'), findsOneWidget);
  });
}

Widget _profileSetupApp(
  UserProvider provider, {
  required ProfileImagePicker imagePicker,
}) {
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(
      home: ProfileSetupScreen(imagePicker: imagePicker),
      routes: {
        RouteNames.onboarding: (_) =>
            const Scaffold(body: Center(child: Text('Onboarding target'))),
      },
    ),
  );
}

class _ProfileSetupRepository extends UserRepository {
  _ProfileSetupRepository({this.shouldFailUpload = false});

  final bool shouldFailUpload;
  UserModel? updatedUser;
  int uploadCalls = 0;
  String? uploadedContentType;

  @override
  Future<void> updateUserProfile(String uid, UserModel user) async {
    updatedUser = user;
  }

  @override
  Future<({String path, String url})> uploadProfileImage(
    String uid,
    Uint8List bytes, {
    required String contentType,
  }) async {
    uploadCalls += 1;
    uploadedContentType = contentType;
    if (shouldFailUpload) throw StateError('upload failed');
    return (
      path: 'profile_images/$uid/avatar.png',
      url: 'https://example.com/avatar.png',
    );
  }
}

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
