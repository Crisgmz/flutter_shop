import 'package:flutter_app/shared/pricing/margin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('priceFromMargin', () {
    test('suma el porcentaje sobre el costo (200 + 20% = 240)', () {
      expect(priceFromMargin(200, 20), 240);
    });

    test('margen 0 deja el precio igual al costo', () {
      expect(priceFromMargin(150, 0), 150);
    });

    test('redondea a dos decimales', () {
      expect(priceFromMargin(33.33, 15), 38.33);
    });
  });

  group('marginFromPrice', () {
    test('devuelve el margen implícito de un precio escrito a mano', () {
      expect(marginFromPrice(200, 240), 20);
    });

    test('sin costo no hay margen que calcular', () {
      expect(marginFromPrice(0, 500), isNull);
    });

    test('precio por debajo del costo da margen negativo', () {
      expect(marginFromPrice(100, 80), -20);
    });
  });

  group('formatMargin', () {
    test('quita los decimales cuando son ceros', () {
      expect(formatMargin(20), '20');
      expect(formatMargin(12.5), '12.5');
      expect(formatMargin(12.34), '12.34');
    });
  });
}
