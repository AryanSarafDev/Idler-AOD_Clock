import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:idler/main.dart';

void main() {
  testWidgets('always on display shows time and date', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlwaysOnDisplayApp());
    
    // Wait for the widget tree to build
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // Find all Text widgets
    final allTextFinder = find.byType(Text);
    
    // Debug: print what text widgets were found
    expect(allTextFinder, findsWidgets);

    // Look for time-like text (contains digits and colon)
    final timeFinder = find.byWidgetPredicate(
      (widget) => widget is Text && 
          widget.data != null &&
          (widget.data!.contains(':') || 
           RegExp(r'^\d{2}$').hasMatch(widget.data!)),
    );

    // Look for weekday names or month names
    final dateFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data != null &&
          (widget.data!.length >= 3 && widget.data!.length <= 9 && 
           RegExp(r'^[A-Za-z]+$').hasMatch(widget.data!)),
    );

    expect(timeFinder, findsWidgets);
    expect(dateFinder, findsWidgets);
  });
}
