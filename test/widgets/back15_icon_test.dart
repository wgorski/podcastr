import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcastr/widgets/back15_icon.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('SkipIcon renders the seconds label and replay glyph', (tester) async {
    await tester.pumpWidget(
      wrap(const SkipIcon(seconds: 15, forward: false)),
    );

    expect(find.text('15'), findsOneWidget);
    expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
  });

  testWidgets('SkipIcon shows the seconds value passed in (30)', (tester) async {
    await tester.pumpWidget(
      wrap(const SkipIcon(seconds: 30, forward: true)),
    );
    expect(find.text('30'), findsOneWidget);
  });

  testWidgets('forward=true flips the replay arrow horizontally', (tester) async {
    await tester.pumpWidget(
      wrap(const SkipIcon(seconds: 15, forward: true)),
    );

    // Transform.flip(flipX: true) yields a Transform whose matrix has -1 on
    // the X scale axis. Look only within SkipIcon's own subtree to dodge the
    // Transforms Material itself uses for chrome.
    final transforms = tester
        .widgetList<Transform>(
          find.descendant(
            of: find.byType(SkipIcon),
            matching: find.byType(Transform),
          ),
        )
        .toList();
    expect(transforms, isNotEmpty);
    expect(transforms.any((t) => t.transform.storage[0] == -1.0), isTrue);
  });

  testWidgets('forward=false does not flip the arrow', (tester) async {
    await tester.pumpWidget(
      wrap(const SkipIcon(seconds: 15, forward: false)),
    );

    final transforms = tester
        .widgetList<Transform>(
          find.descendant(
            of: find.byType(SkipIcon),
            matching: find.byType(Transform),
          ),
        )
        .toList();
    expect(transforms, isNotEmpty);
    expect(transforms.every((t) => t.transform.storage[0] == 1.0), isTrue);
  });

  testWidgets('uses the size argument as the SizedBox dimension', (tester) async {
    await tester.pumpWidget(
      wrap(const SkipIcon(seconds: 15, forward: false, size: 48)),
    );

    final box = tester.widget<SizedBox>(
      find.descendant(of: find.byType(SkipIcon), matching: find.byType(SizedBox)).first,
    );
    expect(box.width, 48);
    expect(box.height, 48);
  });
}
