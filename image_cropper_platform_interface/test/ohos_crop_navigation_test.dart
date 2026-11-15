import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_cropper_platform_interface/src/models/cropped_file/crop_page.dart';
import 'package:image_cropper_platform_interface/image_cropper_platform_interface.dart';

void main() {
  for (final action in ['close', 'back', 'confirm']) {
    testWidgets('HarmonyOS crop completes on $action', (tester) async {
      final dir = Directory.systemTemp.createTempSync();
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = File('${dir.path}/source.jpg')..createSync();
      late BuildContext page;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        page = context;
        return const SizedBox();
      })));

      var completed = false;
      String? result;
      MethodChannelImagecropperOhos().cropImage(
        sourcePath: source.path,
        aspectRatio: action == 'confirm'
            ? const CropAspectRatio(ratioX: 1, ratioY: 1)
            : null,
        uiSettings: [WebUiSettings(context: page)],
      ).then((file) {
        completed = true;
        result = file?.path;
      });
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Crop Image'), findsOneWidget);
      expect(completed, isFalse);
      final cropPage = tester.widget<CropWidget>(find.byType(CropWidget));
      expect(cropPage.fixedAspectRatio, action == 'confirm' ? 1.0 : isNull);
      expect(find.text('4:3'), action == 'confirm' ? findsNothing : findsOneWidget);

      if (action == 'close') {
        await tester.tap(find.byIcon(Icons.close));
      } else if (action == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        Navigator.of(page).pop('cropped.jpg');
      }
      await tester.pump();
      expect(completed, isTrue);
      expect(result, action == 'confirm' ? 'cropped.jpg' : isNull);
    });
  }
}
