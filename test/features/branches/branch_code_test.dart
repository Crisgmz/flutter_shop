import 'package:flutter_app/features/branches/data/branches_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// El error que devolvió la base en la captura del 14 oct 2026.
const _duplicate = PostgrestException(
  message: 'duplicate key value violates unique constraint "branches_code_key"',
  code: '23505',
);

void main() {
  test('el código automático tiene el formato de las sucursales del alta', () {
    final code = generateBranchCode();
    expect(code, matches(RegExp(r'^B-[0-9A-F]{8}$')));
    expect(generateBranchCode(), isNot(code));
  });

  test('sin código: genera uno y reintenta si por casualidad choca', () async {
    final tried = <String>[];
    final id = await saveWithBranchCode('  ', (code) async {
      tried.add(code);
      if (tried.length == 1) throw _duplicate;
      return 'branch-1';
    });
    expect(id, 'branch-1');
    expect(tried, hasLength(2));
    expect(tried[0], isNot(tried[1]));
  });

  test('código escrito que ya existe: aviso claro, sin reintentar', () async {
    var calls = 0;
    await expectLater(
      saveWithBranchCode('12345', (code) async {
        calls++;
        throw _duplicate;
      }),
      throwsA(
        isA<BranchCodeTakenException>()
            .having((e) => e.code, 'code', '12345')
            .having((e) => e.toString(), 'mensaje',
                contains('ya lo usa otra sucursal')),
      ),
    );
    expect(calls, 1);
  });

  test('el código escrito se guarda en mayúsculas', () async {
    final code = await saveWithBranchCode(' suc-norte ', (c) async => c);
    expect(code, 'SUC-NORTE');
  });

  test('otros errores de la base pasan tal cual', () async {
    await expectLater(
      saveWithBranchCode('X1', (_) async {
        throw const PostgrestException(message: 'permission denied', code: '42501');
      }),
      throwsA(isA<PostgrestException>()),
    );
  });
}
