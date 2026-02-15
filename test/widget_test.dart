import 'package:flutter_test/flutter_test.dart';
import 'package:buri_split/main.dart'; // Make sure this matches your project name!

void main() {
  testWidgets('BuriSplit initial UI test', (WidgetTester tester) async {
    // 1. Build our app and trigger a frame.
    await tester.pumpWidget(const BuriSplitApp());

    // 2. Verify that our main button exists.
    expect(find.text('Upload Japanese Receipt'), findsOneWidget);

    // 3. Verify that the initial "Me" person is there.
    expect(find.text('Me'), findsOneWidget);

    // 4. Verify that there are no items initially.
    expect(find.text('Items (Tap name to assign)'), findsOneWidget);
  });
}
