import 'package:flutter_test/flutter_test.dart';
import 'package:sy_im_flutter_sdk_example/main.dart';

void main() {
  testWidgets('IM example loads', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.textContaining('SY IM'), findsWidgets);
    expect(find.text('初始化'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });
}
