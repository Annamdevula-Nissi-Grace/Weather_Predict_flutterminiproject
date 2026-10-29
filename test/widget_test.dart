import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/main.dart';

void main() {
  testWidgets('shows worldwide place search', (WidgetTester tester) async {
    await tester.pumpWidget(const WeatherApp());

    expect(
      find.text('City, region, country (e.g. Tanuku, Andhra Pradesh, India)'),
      findsOneWidget,
    );
  });
}
