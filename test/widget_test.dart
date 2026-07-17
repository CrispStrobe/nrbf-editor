// Smoke test: the app builds its widget tree without throwing. (Replaces the
// default `flutter create` counter template, which referenced a non-existent
// `MyApp` and could never compile.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nrbf_editor/main.dart';

void main() {
  testWidgets('the app builds and mounts a MaterialApp', (tester) async {
    // A generous surface so the home screen lays out without a RenderFlex
    // overflow at the default 800x600 test size.
    await tester.binding.setSurfaceSize(const Size(1400, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const NrbfEditorApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
