import 'package:flutter_app/features/settings/data/ecf_request_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('etapa de la solicitud', () {
    test('lee cada etapa que manda el servidor', () {
      for (final stage in EcfRequestStage.values) {
        expect(EcfRequestStage.parse(stage.name), stage);
      }
    });

    test('una etapa desconocida no rompe la pantalla', () {
      // El servidor puede agregar etapas antes de que se actualice la app.
      expect(EcfRequestStage.parse('etapa_nueva'), EcfRequestStage.none);
      expect(EcfRequestStage.parse(null), EcfRequestStage.none);
    });
  });

  group('respuesta de request_status', () {
    test('arma el estado completo', () {
      final status = EcfRequestStatus.fromJson({
        'stage': 'sequences',
        'requested_at': '2026-09-20T14:05:00Z',
        'contact_name': 'Hailerin',
        'contact_phone': '8295059592',
        'already_authorized': true,
        'mode': 'physical',
        'environment': 'production',
        'certification_status': 'certified',
        'alanube_company_id': '01J8ABC',
        'data': {'rnc': '131974602', 'legal_name': 'PRUEBA SRL'},
        'branches': [
          {'id': 'b1', 'name': 'Principal'},
        ],
        'sequences': [
          {
            'id': 's1',
            'branch_id': 'b1',
            'ncf_type': 'E31',
            'current_number': 40,
            'range_end': 100,
            'expiration_date': '2026-12-31',
            'is_active': true,
          },
        ],
      });

      expect(status.stage, EcfRequestStage.sequences);
      expect(status.requestedAt?.year, 2026);
      expect(status.alreadyAuthorized, isTrue);
      expect(status.electronicEnabled, isFalse);
      expect(status.data.rnc, '131974602');
      expect(status.branches.single.name, 'Principal');
      // Lo que la tarjeta muestra: cuánto le queda a la secuencia.
      expect(status.sequences.single.remaining, 60);
    });

    test('una respuesta mínima cae en los valores por defecto', () {
      final status = EcfRequestStatus.fromJson({'stage': 'none'});

      expect(status.stage, EcfRequestStage.none);
      expect(status.mode, 'physical');
      expect(status.branches, isEmpty);
      expect(status.sequences, isEmpty);
      expect(status.data.rnc, isNull);
      expect(status.requestedAt, isNull);
    });

    test('modo híbrido cuenta como electrónica encendida', () {
      // 'hybrid' es e-CF con respaldo en papel: la venta no se cae si el
      // proveedor no responde.
      expect(
        EcfRequestStatus.fromJson({'stage': 'active', 'mode': 'hybrid'})
            .electronicEnabled,
        isTrue,
      );
    });
  });

  group('lo que se manda al servidor', () {
    test('la secuencia viaja con los nombres que espera la función', () {
      const submission = EcfSequenceSubmission(
        branchId: 'b1',
        ncfType: 'E31',
        rangeStart: 1,
        rangeEnd: 1000,
        expirationDate: '2026-12-31',
        authorizationNumber: 'AUT-9',
        lastUsed: 40,
      );

      expect(submission.toJson(), {
        'ncf_type': 'E31',
        'range_start': 1,
        'range_end': 1000,
        'expiration_date': '2026-12-31',
        'authorization_number': 'AUT-9',
        'last_used': 40,
      });
    });

    test('los datos del contribuyente van con las llaves de la DGII', () {
      const data = EcfRequestData(
        rnc: '131974602',
        legalName: 'PRUEBA SRL',
        tradeName: 'Prueba',
        fiscalAddress: 'Calle Central 17B',
        province: 'Santo Domingo',
        municipality: 'Santo Domingo Norte',
        email: 'a@b.com',
      );

      expect(data.toJson().keys, [
        'rnc',
        'legal_name',
        'trade_name',
        'fiscal_address',
        'province',
        'municipality',
        'email',
      ]);
    });
  });
}
