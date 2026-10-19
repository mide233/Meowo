import 'package:flutter_test/flutter_test.dart';
import 'package:meowo/canvas_view.dart';

void main() {
  testWidgets('renders a page to PNG for export', (tester) async {
    await tester.runAsync(() async {
      final document = <String, dynamic>{
        'id': 'doc_test',
        'title': 'test',
        'kind': 'paged',
        'paper': {'width': 595.276, 'height': 841.89, 'background': 'blank'},
      };
      final page = <String, dynamic>{
        'id': 'page_test',
        'width': 595.276,
        'height': 841.89,
        'layers': [
          {
            'id': 'layer_test',
            'visible': true,
            'opacity': 1.0,
            'elements': [
              {
                'id': 'text_test',
                'type': 'text',
                'x': 50,
                'y': 50,
                'w': 300,
                'h': 80,
                'markdown': '# Hello\nMeowo',
                'fontSize': 16,
                'lineHeight': 1.5,
                'color': '#222222',
              },
            ],
          },
        ],
        'body': null,
      };
      final png = await renderPagePng(
        document: document,
        page: page,
        images: {},
      );
      expect(png.length, greaterThan(1000));
    });
  });
}
