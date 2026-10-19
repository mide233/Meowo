import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/main.dart';

void main() {
  testWidgets('startup error page is readable', (tester) async {
    await tester.pumpWidget(
      StartupErrorApp(error: '核心库缺失', stack: StackTrace.current),
    );
    expect(find.text('喵记启动失败'), findsOneWidget);
    expect(find.textContaining('核心库缺失'), findsOneWidget);
  });
}
