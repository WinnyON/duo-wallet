import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:duo_wallet/app.dart';
import 'package:duo_wallet/core/db/app_database.dart';
import 'package:duo_wallet/core/db/tables/tables.dart';
import 'package:duo_wallet/core/domain/profile_photo.dart';
import 'package:duo_wallet/features/auth/presentation/auth_screen.dart';
import 'package:duo_wallet/router.dart';
import 'package:duo_wallet/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'reporting_test.dart' show tapVisible;

class TestPicker extends ImagePicker {
  XFile? file;
  bool fail = false;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    if (fail) throw StateError('picker unavailable');
    return file;
  }
}

Future<Uint8List> samplePhoto() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(600, 400);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return png!.buffer.asUint8List();
}

void main() {
  testWidgets('photo thumbnail is bounded and rejects invalid input',
      (tester) async {
    await tester.runAsync(() async {
      final encoded = await encodeProfilePhoto(await samplePhoto());
      final codec =
          await ui.instantiateImageCodec(decodeProfilePhoto(encoded)!);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 256);
      expect(frame.image.height, 171);
      frame.image.dispose();
      codec.dispose();
      await expectLater(
          encodeProfilePhoto(Uint8List(0)), throwsFormatException);
      await expectLater(encodeProfilePhoto(Uint8List(16 * 1024 * 1024)),
          throwsFormatException);
    });
    expect(decodeProfilePhoto('data:image/png;base64,invalid!'), isNull);
    expect(decodeProfilePhoto('https://example.com/photo.png'), isNull);
  });

  testWidgets(
      'selected photo previews, saves, and survives profile serialization',
      (tester) async {
    final picker = TestPicker();
    picker.file = XFile.fromData((await tester.runAsync(samplePhoto))!,
        name: 'photo.png');
    final container = ProviderContainer(overrides: [
      profileImagePickerProvider.overrideWithValue(picker),
    ]);
    addTearDown(container.dispose);
    final db = container.read(appDatabaseProvider);
    final id = container.read(currentUserIdProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const DuoWalletApp()));
    container.read(appRouterProvider).go('/auth');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Photo'));
    await tester.runAsync(() async {
      await tester
          .tap(find.widgetWithText(OutlinedButton, 'Choose profile photo'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final avatar = tester.widget<UserAvatar>(find.byType(UserAvatar).first);
    expect(avatar.avatarUrl, startsWith('data:image/png;base64,'));
    expect(db.findProfile(id)!.avatarUrl, isNot(avatar.avatarUrl));
    await tapVisible(
        tester, find.widgetWithText(FilledButton, 'Save local changes'));
    final restored =
        Profile.fromJson(jsonDecode(jsonEncode(db.findProfile(id)!.toJson())));
    expect(restored.avatarType, 'image');
    expect(restored.avatarUrl, avatar.avatarUrl);
    expect(decodeProfilePhoto(restored.avatarUrl), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'canceling or failing to pick a photo preserves the saved profile',
      (tester) async {
    final picker = TestPicker();
    final container = ProviderContainer(
        overrides: [profileImagePickerProvider.overrideWithValue(picker)]);
    addTearDown(container.dispose);
    final db = container.read(appDatabaseProvider);
    final id = container.read(currentUserIdProvider);
    final before = db.findProfile(id)!.toJson();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const DuoWalletApp()));
    container.read(appRouterProvider).go('/auth');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Photo'));
    for (final fail in [false, true]) {
      picker.fail = fail;
      await tapVisible(
          tester, find.widgetWithText(OutlinedButton, 'Choose profile photo'));
      expect(db.findProfile(id)!.toJson(), before);
      expect(tester.takeException(), isNull);
    }
  });
}
