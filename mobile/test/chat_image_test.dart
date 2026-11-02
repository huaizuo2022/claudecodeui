import 'package:cloudcli_mobile/features/chat/widgets/chat_image.dart';
import 'package:cloudcli_mobile/core/models/chat_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  test('parses Claude inline image data URLs', () {
    final image = ChatImage.fromJson({
      'data': 'data:image/png;base64,$_onePixelPng',
    });

    expect(image.hasInlineData, isTrue);
    expect(image.path, isNull);
  });

  test('keeps the stored asset filename ahead of the display name', () {
    final image = ChatImage.fromJson({
      'name': 'picker.png',
      'path': '/Users/shang/.cloudcli/assets/1793-picker.png',
    });

    expect(image.name, 'picker.png');
    expect(image.storedFilename, '1793-picker.png');
  });

  test('message keeps both inline and path-backed images', () {
    final message = ChatMessage.fromJson({
      'id': 'm1',
      'kind': 'text',
      'timestamp': '2026-11-02T00:00:00Z',
      'images': [
        {'data': 'data:image/png;base64,$_onePixelPng'},
        {'path': '/Users/shang/.cloudcli/assets/1793-picker.png'},
      ],
    });

    expect(message.images, hasLength(2));
    expect(message.images.first.hasInlineData, isTrue);
    expect(message.images.last.storedFilename, '1793-picker.png');
  });

  testWidgets('renders a data URL attachment without a network request', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChatImageThumb(
              image: ChatImage.fromJson({
                'data': 'data:image/png;base64,$_onePixelPng',
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(
      (tester.widget<Image>(find.byType(Image)).image),
      isA<MemoryImage>(),
    );
  });
}
