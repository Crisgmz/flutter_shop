import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/select_in.dart';
import 'fiscal_consumo_summary.dart';

class FiscalDocument implements FiscalSummarySource {
  FiscalDocument({
    required this.id,
    required this.branchId,
    required this.receiptType,
    required this.ncf,
    required this.fiscalStatus,
    required this.issuedAt,
    required this.subtotal,
    required this.taxableAmount,
    required this.exemptAmount,
    required this.taxAmount,
    required this.serviceChargeAmount,
    required this.totalAmount,
    required this.discountAmount,
    this.saleId,
    this.clientId,
    this.ncfSequenceId,
    this.sequenceNumber,
    this.expiresOn,
    this.voidedAt,
    this.voidReason,
    this.customerName,
    this.customerDocumentType,
    this.customerDocumentNumber,
    this.customerAddress,
    this.issuerName,
    this.issuerTaxId,
    this.issuerAddress,
    this.ecfStatus,
    this.alanubeDocumentId,
    this.ecfTrackingNumber,
    this.ecfSecurityCode,
    this.ecfSignedAt,
    this.publicUrl,
    this.xmlUrl,
    this.pdfUrl,
    this.submittedAt,
    this.acceptedAt,
    this.lastError,
    this.saleNumber,
    this.saleDate,
    this.saleStatus,
    this.salePayments = const [],
  });

  final String id;
  final String branchId;
  final String? saleId;
  final String? clientId;
  final String? ncfSequenceId;
  @override
  final String receiptType;
  final String ncf;
  final int? sequenceNumber;
  final String fiscalStatus;
  final DateTime issuedAt;
  final DateTime? expiresOn;
  final DateTime? voidedAt;
  final String? voidReason;
  final String? customerName;
  final String? customerDocumentType;
  final String? customerDocumentNumber;
  final String? customerAddress;
  final String? issuerName;
  final String? issuerTaxId;
  final String? issuerAddress;
  final double subtotal;
  final double discountAmount;
  final double taxableAmount;
  final double exemptAmount;
  @override
  final double taxAmount;
  @override
  final double serviceChargeAmount;
  @override
  final double totalAmount;

  // === e-CF (DGII vía Alanube). Solo populado en documentos serie E ===
  final String? ecfStatus; // 'pending' | 'sent' | 'accepted' | 'rejected'
  final String? alanubeDocumentId;
  final String? ecfTrackingNumber;
  final String? ecfSecurityCode;
  final DateTime? ecfSignedAt;
  final String? publicUrl; // URL DGII de verificación (contenido del QR)
  final String? xmlUrl;
  final String? pdfUrl;
  final DateTime? submittedAt;
  final DateTime? acceptedAt;
  final String? lastError;

  // === Venta de origen (embed `sales`), para saber cómo se pagó ===
  final String? saleNumber;
  final DateTime? saleDate;
  final String? saleStatus;
  final List<FiscalSalePayment> salePayments;

  bool get isVoided => voidedAt != null;

  /// Anulado como comprobante o anulada la venta. "Anular venta" no marca el
  /// comprobante, así que hay que mirar las dos cosas.
  @override
  bool get isCancelled => isVoided || saleStatus == 'voided';

  /// Cómo se pagó la factura al venderla (ver [salePaymentBreakdown]).
  /// Vacío si el comprobante no tiene venta asociada.
  @override
  Map<String, double> get paymentBreakdown => saleStatus == null
      ? const {}
      : salePaymentBreakdown(
          total: totalAmount,
          saleNumber: saleNumber,
          saleDate: saleDate,
          saleStatus: saleStatus!,
          payments: salePayments,
        );

  bool get isApproved => fiscalStatus == 'approved';
  bool get isPending => fiscalStatus == 'pending';

  bool get isElectronic => ncf.startsWith('E');

  /// Código e-CF DGII derivado del NCF: 'E31', 'E32', 'E44', 'E45'…
  String get ncfTypeCode => ncf.length >= 3 ? ncf.substring(0, 3) : ncf;

  /// `true` cuando podemos imprimir un QR válido en la representación del
  /// e-CF. DGII Norma 01-2020 exige el QR en la representación impresa, por
  /// eso renderizamos en cuanto hay `ecf_security_code` (estado `sent`), sin
  /// esperar al webhook que mueve a `accepted`: DGII acepta consultas de docs
  /// "EN PROCESO" mostrando ese estado a quien escanea.
  bool get hasQrData =>
      isElectronic &&
      (ecfStatus == 'accepted' || ecfStatus == 'sent') &&
      (ecfSecurityCode?.isNotEmpty ?? false);

  /// URL DGII de verificación del e-CF (contenido del QR del recibo).
  /// Fallback cuando Alanube aún no populó `public_url` (típico en `sent`).
  /// Norma DGII 01-2020: FechaEmision va DD-MM-YYYY; E31 exige RncComprador.
  String? buildDgiiVerifyUrl({
    required String emitterRnc,
    required bool sandbox,
  }) {
    final code = ecfSecurityCode;
    if (code == null || code.isEmpty) return null;
    if (emitterRnc.trim().isEmpty) return null;

    final base = sandbox
        ? 'https://ecf.dgii.gov.do/testecf/ConsultaTimbreFC'
        : 'https://ecf.dgii.gov.do/ecf/ConsultaTimbreFC';

    final d = issuedAt;
    final fecha = '${d.day.toString().padLeft(2, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.year}';

    final params = <String, String>{
      'RncEmisor': emitterRnc.trim(),
      'ENCF': ncf,
      'FechaEmision': fecha,
      'MontoTotal': totalAmount.toStringAsFixed(2),
      'CodigoSeguridad': code,
    };
    final buyerRnc = customerDocumentNumber?.trim() ?? '';
    if (ncfTypeCode == 'E31' && buyerRnc.isNotEmpty) {
      params['RncComprador'] = buyerRnc;
    }

    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$base?$query';
  }

  /// Mensaje legible del estado e-CF para imprimir cuando aún no hay QR.
  /// Devuelve null si el doc es físico o ya fue aceptado.
  String? get ecfStatusMessage {
    if (!isElectronic) return null;
    switch (ecfStatus) {
      case 'pending':
        return 'Pendiente de emisión a DGII';
      case 'sent':
        return 'En proceso DGII (esperando confirmación)';
      case 'rejected':
        final err = lastError ?? '';
        return err.isNotEmpty
            ? 'Rechazado DGII: ${err.substring(0, err.length.clamp(0, 80))}'
            : 'Rechazado por DGII';
      default:
        return null;
    }
  }

  factory FiscalDocument.fromMap(Map<String, dynamic> map) {
    final sale = map['sales'] is Map
        ? Map<String, dynamic>.from(map['sales'] as Map)
        : null;
    return FiscalDocument(
      id: (map['id'] ?? '').toString(),
      branchId: (map['branch_id'] ?? '').toString(),
      saleId: map['sale_id']?.toString(),
      clientId: map['client_id']?.toString(),
      ncfSequenceId: map['ncf_sequence_id']?.toString(),
      receiptType: (map['receipt_type'] ?? '').toString(),
      ncf: (map['ncf'] ?? '').toString(),
      sequenceNumber: map['sequence_number'] == null
          ? null
          : _toInt(map['sequence_number']),
      fiscalStatus: (map['fiscal_status'] ?? 'pending').toString(),
      issuedAt: DateTime.tryParse((map['issued_at'] ?? '').toString()) ??
          DateTime.now(),
      expiresOn: map['expires_on'] == null
          ? null
          : DateTime.tryParse(map['expires_on'].toString()),
      voidedAt: map['voided_at'] == null
          ? null
          : DateTime.tryParse(map['voided_at'].toString()),
      voidReason: map['void_reason']?.toString(),
      customerName: map['customer_name']?.toString(),
      customerDocumentType: map['customer_document_type']?.toString(),
      customerDocumentNumber: map['customer_document_number']?.toString(),
      customerAddress: map['customer_address']?.toString(),
      issuerName: map['issuer_name']?.toString(),
      issuerTaxId: map['issuer_tax_id']?.toString(),
      issuerAddress: map['issuer_address']?.toString(),
      subtotal: _toDouble(map['subtotal']),
      discountAmount: _toDouble(map['discount_amount']),
      taxableAmount: _toDouble(map['taxable_amount']),
      exemptAmount: _toDouble(map['exempt_amount']),
      taxAmount: _toDouble(map['tax_amount']),
      serviceChargeAmount: _toDouble(map['service_charge_amount']),
      totalAmount: _toDouble(map['total_amount']),
      ecfStatus: map['ecf_status']?.toString(),
      alanubeDocumentId: map['alanube_document_id']?.toString(),
      ecfTrackingNumber: map['ecf_tracking_number']?.toString(),
      ecfSecurityCode: map['ecf_security_code']?.toString(),
      ecfSignedAt: map['ecf_signed_at'] == null
          ? null
          : DateTime.tryParse(map['ecf_signed_at'].toString()),
      publicUrl: map['public_url']?.toString(),
      xmlUrl: map['xml_url']?.toString(),
      pdfUrl: map['pdf_url']?.toString(),
      submittedAt: map['submitted_at'] == null
          ? null
          : DateTime.tryParse(map['submitted_at'].toString()),
      acceptedAt: map['accepted_at'] == null
          ? null
          : DateTime.tryParse(map['accepted_at'].toString()),
      lastError: map['last_error']?.toString(),
      saleNumber: sale?['sale_number']?.toString(),
      saleDate: sale?['sale_date'] == null
          ? null
          : DateTime.tryParse(sale!['sale_date'].toString()),
      saleStatus: sale?['status']?.toString(),
      salePayments: [
        for (final raw in (sale?['payments'] as List?) ?? const [])
          if (raw is Map)
            FiscalSalePayment.fromMap(Map<String, dynamic>.from(raw)),
      ],
    );
  }
}

/// Un pago (`payments`) de la venta de origen del comprobante.
class FiscalSalePayment {
  const FiscalSalePayment({
    required this.method,
    required this.amount,
    this.paidAt,
    this.reference,
  });

  final String method;
  final double amount;
  final DateTime? paidAt;
  final String? reference;

  factory FiscalSalePayment.fromMap(Map<String, dynamic> map) {
    return FiscalSalePayment(
      method: (map['payment_method'] ?? '').toString(),
      amount: _toDouble(map['amount']),
      paidAt: map['paid_at'] == null
          ? null
          : DateTime.tryParse(map['paid_at'].toString()),
      reference: map['reference']?.toString(),
    );
  }
}

/// Cómo se pagó una venta al venderla: monto por método de pago (`cash`,
/// `card`, `transfer`…) y `credit` para lo que quedó debiendo.
///
/// Los abonos que se cobraron después NO cuentan: para la DGII una factura
/// a crédito sigue siendo "A crédito" aunque ya esté saldada. Los pagos
/// hechos al vender (checkout y el editor de pagos) llevan como referencia
/// el número de la venta; los abonos de Cobros llevan la del usuario. La
/// conversión de cotización no pone referencia, pero se registra en el
/// mismo instante que la venta.
Map<String, double> salePaymentBreakdown({
  required double total,
  required String? saleNumber,
  required DateTime? saleDate,
  required String saleStatus,
  required List<FiscalSalePayment> payments,
}) {
  // Venta vieja cobrada sin filas en `payments`: igual que el 607
  // (`dgii_607_data`), una venta completada sin pagos cuenta como efectivo.
  if (payments.isEmpty && saleStatus == 'completed') {
    return {'cash': total};
  }

  bool paidAtSale(FiscalSalePayment payment) {
    if (saleNumber != null &&
        saleNumber.isNotEmpty &&
        payment.reference == saleNumber) {
      return true;
    }
    final paidAt = payment.paidAt;
    if (saleDate == null || paidAt == null) return false;
    return paidAt.difference(saleDate).inMinutes.abs() <= 2;
  }

  final byMethod = <String, double>{};
  var paid = 0.0;
  for (final payment in payments.where(paidAtSale)) {
    byMethod[payment.method] = (byMethod[payment.method] ?? 0) + payment.amount;
    paid += payment.amount;
  }

  // Si la venta se editó después de emitir el comprobante, los pagos pueden
  // pasar del total del comprobante: se reparten en proporción para que el
  // desglose cuadre con el monto fiscal.
  if (paid > total && paid > 0) {
    final factor = total / paid;
    byMethod.updateAll((_, amount) => amount * factor);
    paid = total;
  }

  final credit = total - paid;
  if (credit > 0.005) {
    byMethod['credit'] = (byMethod['credit'] ?? 0) + credit;
  }
  return byMethod;
}

/// Pagos de cada venta (`sale_id` → filas de `payments`), buscados por id en
/// grupos (ver `selectIn`). Nunca unir `payments` dentro de la consulta de
/// ventas o comprobantes: con la RLS, Postgres puede resolver esa unión
/// recorriendo todo el historial y la consulta muere por tiempo (57014).
Future<Map<String, List<Map<String, dynamic>>>> fetchPaymentsBySale(
  SupabaseClient client,
  Iterable<String> saleIds,
) async {
  final rows = await selectIn(
    client,
    table: 'payments',
    columns: 'sale_id, payment_method, amount, paid_at, reference',
    column: 'sale_id',
    values: saleIds,
  );
  final bySale = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    bySale.putIfAbsent(row['sale_id'].toString(), () => []).add(row);
  }
  return bySale;
}

/// Venta con NCF y sus pagos. El 607 sale de `sales` (no de
/// `fiscal_documents`): con esto se le pone el método de pago a cada fila y
/// se arma su resumen.
class FiscalSale implements FiscalSummarySource {
  const FiscalSale({
    required this.id,
    required this.ncf,
    required this.receiptType,
    required this.status,
    required this.totalAmount,
    required this.taxAmount,
    required this.serviceChargeAmount,
    this.saleNumber,
    this.saleDate,
    this.payments = const [],
  });

  final String id;
  final String ncf;
  @override
  final String receiptType;
  final String status;
  @override
  final double totalAmount;
  @override
  final double taxAmount;
  @override
  final double serviceChargeAmount;
  final String? saleNumber;
  final DateTime? saleDate;
  final List<FiscalSalePayment> payments;

  @override
  bool get isCancelled => status == 'voided';

  @override
  Map<String, double> get paymentBreakdown => salePaymentBreakdown(
        total: totalAmount,
        saleNumber: saleNumber,
        saleDate: saleDate,
        saleStatus: status,
        payments: payments,
      );

  factory FiscalSale.fromMap(Map<String, dynamic> map) {
    return FiscalSale(
      id: (map['id'] ?? '').toString(),
      ncf: (map['ncf'] ?? '').toString(),
      receiptType: (map['receipt_type'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      totalAmount: _toDouble(map['total_amount']),
      taxAmount: _toDouble(map['tax_amount']),
      serviceChargeAmount: _toDouble(map['service_charge_amount']),
      saleNumber: map['sale_number']?.toString(),
      saleDate: map['sale_date'] == null
          ? null
          : DateTime.tryParse(map['sale_date'].toString()),
      payments: [
        for (final raw in (map['payments'] as List?) ?? const [])
          if (raw is Map)
            FiscalSalePayment.fromMap(Map<String, dynamic>.from(raw)),
      ],
    );
  }
}

class FiscalDocumentsRepository {
  FiscalDocumentsRepository(this._client);

  final SupabaseClient _client;

  /// Comprobantes de la sucursal con su venta de origen y los pagos de esa
  /// venta (para la columna "Método de pago" y el resumen DGII).
  ///
  /// Con `limit` trae solo los más recientes; con `limit: null` trae todos
  /// los del filtro, de 1000 en 1000 (el tope por petición de PostgREST).
  Future<List<FiscalDocument>> fetchDocuments({
    String? statusFilter,
    String? receiptTypeFilter,
    DateTime? from,
    DateTime? to,
    int? limit = 100,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    // Sin unir `sales`/`payments` aquí: con esa unión la consulta de los
    // 100 más recientes se iba a todo el historial y moría por tiempo
    // (57014). La venta y los pagos se buscan después, por id.
    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      var query = _client
          .from('fiscal_documents')
          .select(
            'id, branch_id, sale_id, client_id, ncf_sequence_id, receipt_type, ncf, '
            'sequence_number, fiscal_status, issued_at, expires_on, voided_at, void_reason, '
            'customer_name, customer_document_type, customer_document_number, customer_address, '
            'issuer_name, issuer_tax_id, issuer_address, '
            'subtotal, discount_amount, taxable_amount, exempt_amount, tax_amount, '
            'service_charge_amount, total_amount, '
            'ecf_status, alanube_document_id, ecf_tracking_number, ecf_security_code, '
            'ecf_signed_at, public_url, xml_url, pdf_url, submitted_at, accepted_at, last_error',
          )
          .eq('branch_id', branchId);

      if (statusFilter != null && statusFilter.isNotEmpty) {
        query = query.eq('fiscal_status', statusFilter);
      }
      if (receiptTypeFilter != null && receiptTypeFilter.isNotEmpty) {
        query = query.eq('receipt_type', receiptTypeFilter);
      }
      // Días locales completos. Antes se mandaba la medianoche local sin zona
      // y el servidor la leía como UTC: el último día del rango quedaba fuera.
      if (from != null) query = query.gte('issued_at', _dayStartUtc(from));
      if (to != null) query = query.lt('issued_at', _nextDayStartUtc(to));

      if (limit != null) {
        // Solo por fecha y con NULLS FIRST (issued_at nunca es nulo): es el
        // orden del índice (branch_id, issued_at desc), así los 100 más
        // recientes salen de él sin ordenar toda la sucursal. El
        // `desc.nullslast` que manda postgrest por defecto no lo usa.
        final page = await query
            .order('issued_at', ascending: false, nullsFirst: true)
            .limit(limit);
        rows.addAll(page.map((e) => Map<String, dynamic>.from(e as Map)));
        break;
      }

      // Paginando hace falta un desempate fijo; el rango ya acota las filas.
      final page = await query
          .order('issued_at', ascending: false, nullsFirst: true)
          .order('id', ascending: false)
          .range(offset, offset + pageSize - 1);
      rows.addAll(page.map((e) => Map<String, dynamic>.from(e as Map)));
      if (page.length < pageSize) break;
      offset += page.length;
    }

    final saleIds = [
      for (final row in rows)
        if (row['sale_id'] != null) row['sale_id'].toString(),
    ];
    final (sales, payments) = await (
      selectIn(
        _client,
        table: 'sales',
        columns: 'id, sale_number, sale_date, status',
        column: 'id',
        values: saleIds,
      ),
      fetchPaymentsBySale(_client, saleIds),
    ).wait;
    final salesById = {for (final sale in sales) sale['id'].toString(): sale};

    return [
      for (final row in rows)
        FiscalDocument.fromMap({
          ...row,
          if (salesById[row['sale_id']?.toString()] case final sale?)
            'sales': {
              ...sale,
              'payments': payments[sale['id'].toString()] ?? const [],
            },
        }),
    ];
  }

  /// Ventas con NCF del rango (días locales completos) con sus pagos, de
  /// 1000 en 1000. Los pagos van aparte, por id (ver [fetchPaymentsBySale]).
  Future<List<FiscalSale>> fetchSalesWithPayments({
    required DateTime from,
    required DateTime to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await _client
          .from('sales')
          .select(
            'id, ncf, receipt_type, status, sale_number, sale_date, '
            'total_amount, tax_amount, service_charge_amount',
          )
          .eq('branch_id', branchId)
          .not('ncf', 'is', null)
          .gte('sale_date', _dayStartUtc(from))
          .lt('sale_date', _nextDayStartUtc(to))
          .order('sale_date')
          .order('id')
          .range(offset, offset + pageSize - 1);
      rows.addAll(page.map((e) => Map<String, dynamic>.from(e as Map)));
      if (page.length < pageSize) break;
      offset += page.length;
    }

    final payments = await fetchPaymentsBySale(
      _client,
      rows.map((row) => row['id'].toString()),
    );
    return [
      for (final row in rows)
        FiscalSale.fromMap({
          ...row,
          'payments': payments[row['id'].toString()] ?? const [],
        }),
    ];
  }

  Future<FiscalDocument?> fetchDocument(String id) async {
    final rows = await _client
        .from('fiscal_documents')
        .select()
        .eq('id', id)
        .limit(1);

    if (rows.isEmpty) return null;
    return FiscalDocument.fromMap(
        Map<String, dynamic>.from(rows.first as Map));
  }

  Future<FiscalDocument?> fetchDocumentBySaleId(String saleId) async {
    final rows = await _client
        .from('fiscal_documents')
        .select()
        .eq('sale_id', saleId)
        .order('created_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) return null;
    return FiscalDocument.fromMap(
        Map<String, dynamic>.from(rows.first as Map));
  }

  /// Dispara la Edge Function `emit-document` en modo sync para un documento
  /// electrónico (serie E). Devuelve el documento refrescado con los datos
  /// del QR si la emisión respondió a tiempo; si el timeout expira, el cron
  /// de respaldo drenará la cola y el webhook actualizará el estado después.
  /// Nunca lanza: el e-CF no debe romper el flujo de venta/impresión.
  Future<FiscalDocument?> emitElectronicDocument(
    String fiscalDocumentId, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      await _client.functions
          .invoke(
            'emit-document',
            body: {'fiscal_document_id': fiscalDocumentId},
          )
          .timeout(timeout);
    } catch (_) {
      // La cola/cron reintenta; seguimos para refrescar el estado actual.
    }
    try {
      return await fetchDocument(fiscalDocumentId);
    } catch (_) {
      return null;
    }
  }

  Future<void> voidDocument({
    required String id,
    required String reason,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    await _client
        .from('fiscal_documents')
        .update({
          'fiscal_status': 'voided',
          'voided_at': DateTime.now().toUtc().toIso8601String(),
          'void_reason': reason.trim(),
        })
        .eq('id', id)
        .eq('branch_id', branchId);
  }

  static String _dayStartUtc(DateTime d) =>
      DateTime(d.year, d.month, d.day).toUtc().toIso8601String();

  static String _nextDayStartUtc(DateTime d) =>
      DateTime(d.year, d.month, d.day + 1).toUtc().toIso8601String();

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
