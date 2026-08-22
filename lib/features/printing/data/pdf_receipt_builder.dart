import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../shared/formatters/formatters.dart';
import 'printing_models.dart';

/// Reduce una imagen a `maxDim` px en su lado mayor ANTES de embeberla en el
/// PDF. Embeber un logo/QR de ~2000px hace que el `pdf` decodifique millones de
/// píxeles de forma SÍNCRONA al generar — en web eso congela la UI varios
/// segundos. Con ~400px el costo baja ~25x. Si la imagen ya es chica o el
/// decode falla, devuelve los bytes originales.
Future<Uint8List?> _shrinkImageForPdf(List<int>? bytes, {int maxDim = 420}) async {
  if (bytes == null) return null;
  final input = Uint8List.fromList(bytes);
  try {
    final probe = await ui.instantiateImageCodec(input);
    final probeFrame = await probe.getNextFrame();
    final w = probeFrame.image.width;
    final h = probeFrame.image.height;
    probeFrame.image.dispose();

    final longest = w > h ? w : h;
    if (longest <= maxDim) return input; // ya es chica

    final scale = maxDim / longest;
    final codec = await ui.instantiateImageCodec(
      input,
      targetWidth: (w * scale).round(),
      targetHeight: (h * scale).round(),
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    return data?.buffer.asUint8List() ?? input;
  } catch (_) {
    return input;
  }
}

/// Azul corporativo del encabezado (logo / título / número de documento).
const PdfColor _kNavy = PdfColor.fromInt(0xFF1B3A6B);

/// Rojo del "TOTAL A PAGAR".
const PdfColor _kRed = PdfColor.fromInt(0xFFC0202A);

/// Texto que NUNCA envuelve: se dibuja en un solo renglón y, si no cabe en el
/// ancho disponible, se achica proporcionalmente en vez de bajar a una segunda
/// línea. Así el nombre del producto, el precio y la cantidad quedan siempre
/// en la misma fila de la tabla.
///
/// `pw.FittedBox` mide al hijo sin límite de ancho —de ahí que el texto salga
/// en una línea— y después lo escala para caber en la celda.
pw.Widget _oneLine(
  String text, {
  required pw.TextStyle style,
  pw.Alignment align = pw.Alignment.centerLeft,
}) {
  // `FittedBox` mide sin límites y asume un hijo con tamaño > 0; un texto
  // vacío rompería esa premisa.
  if (text.trim().isEmpty) return pw.Text(text, style: style);
  return pw.FittedBox(
    fit: pw.BoxFit.scaleDown,
    alignment: align,
    child: pw.Text(text, style: style, maxLines: 1, softWrap: false),
  );
}

/// Piso de tamaño de letra para la descripción de un ítem. Por debajo de esto
/// el nombre del producto deja de leerse en papel.
const double _kMinItemFontSize = 6.5;

/// Tamaño de letra con el que [text] entra en [maxWidth] en un solo renglón,
/// acotado entre [_kMinItemFontSize] y [baseFontSize].
///
/// Mide con las métricas reales del font del documento (`stringMetrics`
/// devuelve el ancho en ems), así que no depende de estimar el ancho promedio
/// de los caracteres.
double _fitFontSize(
  pw.Context context,
  String text, {
  required double maxWidth,
  required double baseFontSize,
}) {
  if (text.trim().isEmpty || maxWidth <= 0) return baseFontSize;
  final font = pw.Theme.of(context).defaultTextStyle.font?.getFont(context);
  if (font == null) return baseFontSize;
  final width = font.stringMetrics(text).width * baseFontSize;
  if (width <= maxWidth) return baseFontSize;
  final scaled = baseFontSize * maxWidth / width;
  return scaled < _kMinItemFontSize ? _kMinItemFontSize : scaled;
}

/// Margen de la hoja A4.
const double _kA4Margin = 36;

/// Ancho del hueco que reservan los dos costados del encabezado A4. El logo
/// ocupa uno y el otro queda vacío, de modo que los datos de la empresa
/// queden centrados en la hoja sin importar de qué lado esté el logo.
const double _kLogoSlotWidth = 96;

class PdfReceiptBuilder {
  const PdfReceiptBuilder();

  Future<Uint8List> buildBytes(
    PrintDocumentData data, {
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final doc = pw.Document(
      title: data.documentNumber,
      author: data.branch.name,
    );

    // QR: SOLO si el negocio configuró `company_qr_url` (data.qrBytes). Antes
    // había un QR por defecto bundleado (assets/QR.png) que salía siempre; se
    // quitó a pedido — el QR aparece únicamente si el usuario decide agregarlo.
    // Reducir imágenes antes de embeberlas: evita el freeze de la UI al generar.
    final qrBytes = await _shrinkImageForPdf(data.qrBytes, maxDim: 420);
    final logoBytes = await _shrinkImageForPdf(data.branch.logoBytes, maxDim: 320);

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(_kA4Margin),
        build: (context) => _buildContent(
          context,
          data,
          qrBytes: qrBytes,
          logoBytes: logoBytes,
          contentWidth: pageFormat.width - _kA4Margin * 2,
        ),
      ),
    );

    return doc.save();
  }

  /// Construye el PDF en formato ticket térmico ~80mm de ancho.
  /// Layout vertical: logo → empresa centrada → bloque metadata derecha →
  /// "Factura a:" → cliente → items → totales → barcode.
  Future<Uint8List> buildThermalBytes(PrintDocumentData data) async {
    final doc = pw.Document(
      title: data.documentNumber,
      author: data.branch.name,
    );

    // 80mm = 226.77pt; usamos altura infinita (roll continuo).
    final format = PdfPageFormat(
      80 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 8 * PdfPageFormat.mm,
    );

    final logoBytes = await _shrinkImageForPdf(data.branch.logoBytes, maxDim: 320);

    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) => _buildThermalContent(data, logoBytes),
      ),
    );

    return doc.save();
  }

  pw.Widget _buildContent(
    pw.Context context,
    PrintDocumentData data, {
    Uint8List? qrBytes,
    Uint8List? logoBytes,
    required double contentWidth,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _header(data, logoBytes),
        pw.SizedBox(height: 14),
        _titleBand(data),
        pw.SizedBox(height: 12),
        _clientBlock(data),
        pw.SizedBox(height: 12),
        _itemsTable(context, data, contentWidth),
        pw.SizedBox(height: 14),
        _bankAndTotal(data),
        if (_hasText(data.notes)) ...[
          pw.SizedBox(height: 10),
          pw.Text(
            'Notas: ${data.notes}',
            style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
          ),
        ],
        pw.Spacer(),
        _signatureAndObservation(data, qrBytes),
        if (_hasText(data.footerMessage)) ...[
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              data.footerMessage!,
              style: pw.TextStyle(
                fontSize: 9.5,
                color: PdfColors.grey600,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Thermal (80mm) layout — sigue el formato del ticket de la foto.
  // ────────────────────────────────────────────────────────────────────────

  pw.Widget _buildThermalContent(PrintDocumentData data, Uint8List? logoBytes) {
    final mutedColor = PdfColors.grey700;
    final base = const pw.TextStyle(fontSize: 8.5);
    final muted = pw.TextStyle(fontSize: 8.5, color: mutedColor);
    final bold = pw.TextStyle(
      fontSize: 8.5,
      fontWeight: pw.FontWeight.bold,
    );
    final big = pw.TextStyle(
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
    );

    // Aviso de NCF pendiente (cotización / cuenta guardada). Se deriva del
    // documento, no de las notas: así sale una sola vez y en cualquier tamaño
    // de papel que elija el usuario.
    final pendingNcfNotice = printPendingNcfNotice(data);
    // Una cotización o una cuenta guardada no entregan el comprobante que
    // rotula esta fila: se emitirá después.
    final receiptTypeRowLabel =
        data.documentType == PrintDocumentType.quote || data.isPendingAccount
            ? 'Se facturará como:'
            : 'Tipo comprobante:';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // ── 1) Encabezado centrado: logo + empresa + dirección + teléfono ──
        if (logoBytes != null)
          pw.Center(
            child: pw.SizedBox(
              width: 60,
              height: 60,
              child: pw.Image(pw.MemoryImage(logoBytes)),
            ),
          ),
        if (logoBytes != null) pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            data.branch.name.toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: big,
          ),
        ),
        if (_hasText(data.branch.address))
          pw.Center(
            child: pw.Text(
              data.branch.address!,
              textAlign: pw.TextAlign.center,
              style: base,
            ),
          ),
        if (_hasText(data.branch.phone))
          pw.Center(
            child: pw.Text(
              data.branch.phone!,
              textAlign: pw.TextAlign.center,
              style: base,
            ),
          ),
        if (_hasText(data.branch.taxId))
          pw.Center(
            child: pw.Text(
              'RNC ${data.branch.taxId}',
              textAlign: pw.TextAlign.center,
              style: base,
            ),
          ),
        _thermalDashedDivider(),

        // ── 2) Título del documento ───────────────────────────────────────
        // El ticket no tiene banda de título como el A4; sin esta línea una
        // cotización o una cuenta guardada se leerían como factura.
        pw.Center(
          child: pw.Text(
            printDocumentTitle(data),
            textAlign: pw.TextAlign.center,
            style: big,
          ),
        ),
        _thermalDashedDivider(),

        // ── 3) Fecha centrada ─────────────────────────────────────────────
        pw.Center(
          child: pw.Text(
            formatDateTime(data.issuedAt),
            style: base,
          ),
        ),
        _thermalDashedDivider(),

        // ── 4) Metadata centrada: serie, caja, tipo precio, empleado, NCF ─
        _thermalMetaRow('Serie y Número:', data.documentNumber, bold: bold, base: base),
        if (_hasText(data.cashRegisterName))
          _thermalMetaRow('Caja registradora:', data.cashRegisterName!, bold: bold, base: base),
        if (_hasText(data.priceTierLabel))
          _thermalMetaRow('Tipo de precio:', data.priceTierLabel!, bold: bold, base: base),
        if (_hasText(data.cashierName))
          _thermalMetaRow('Empleado:', data.cashierName!, bold: bold, base: base),
        if (_hasText(data.ncf))
          _thermalMetaRow('NCF:', data.ncf!, bold: bold, base: base),
        if (data.ncfValidUntil != null)
          _thermalMetaRow(
            'NCF válido hasta:',
            formatDate(data.ncfValidUntil!),
            bold: bold,
            base: base,
          ),
        if (pendingNcfNotice != null)
          pw.Center(
            child: pw.Text(
              pendingNcfNotice,
              textAlign: pw.TextAlign.center,
              style: bold,
            ),
          ),
        if (_hasText(data.receiptTypeLabel))
          _thermalMetaRow(
            receiptTypeRowLabel,
            data.receiptTypeLabel!,
            bold: bold,
            base: base,
          ),

        // ── 5) Bloque cliente ─────────────────────────────────────────────
        if (data.customer != null) ...[
          _thermalDashedDivider(),
          pw.Text(
            data.documentType == PrintDocumentType.quote || data.isPendingAccount
                ? 'Datos del cliente:'
                : 'Factura a:',
            style: bold,
          ),
          pw.SizedBox(height: 2),
          pw.Text('Cliente: ${data.customer!.name}', style: base),
          if (_hasText(data.customer!.address))
            pw.Text('Dirección : ${data.customer!.address}', style: base),
          if (_hasText(data.customer!.document))
            pw.Text('Doc: ${data.customer!.document}', style: base),
          if (_hasText(data.customer!.phone))
            pw.Text('Teléfono : ${data.customer!.phone}', style: base),
        ],

        // ── 6) Tabla de items ─────────────────────────────────────────────
        _thermalDashedDivider(),
        _thermalItemsTable(data, base: base, bold: bold, muted: muted),

        // ── 7) Totales alineados a la derecha ─────────────────────────────
        _thermalDashedDivider(),
        _thermalTotals(data, base: base, bold: bold),

        // ── 8) Notas / footer / barcode ───────────────────────────────────
        if (_hasText(data.notes)) ...[
          _thermalDashedDivider(),
          pw.Text('Notas: ${data.notes}', style: muted),
        ],
        if (_hasText(data.footerMessage)) ...[
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              data.footerMessage!,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontStyle: pw.FontStyle.italic,
                color: mutedColor,
              ),
            ),
          ),
        ],
        // ── 9) e-CF: QR DGII + código de seguridad (Norma 01-2020) ────────
        if (data.ecf != null) ...[
          _thermalDashedDivider(),
          ..._thermalEcfBlock(data.ecf!, base: base, bold: bold, muted: muted),
        ],
        if (data.showBarcode) ...[
          _thermalDashedDivider(),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: data.documentNumber,
              width: 180,
              height: 40,
              drawText: true,
              textStyle: const pw.TextStyle(fontSize: 8),
            ),
          ),
        ],
      ],
    );
  }

  /// Bloque e-CF de la representación impresa: QR de verificación DGII,
  /// código de seguridad y fecha de firma digital. Si el documento aún no
  /// tiene QR (Alanube no respondió a tiempo o DGII lo rechazó), imprime el
  /// mensaje de estado en su lugar.
  List<pw.Widget> _thermalEcfBlock(
    PrintEcfData ecf, {
    required pw.TextStyle base,
    required pw.TextStyle bold,
    required pw.TextStyle muted,
  }) {
    if (!ecf.hasQr) {
      return [
        pw.Center(
          child: pw.Text(
            ecf.statusMessage ?? 'e-CF en proceso DGII',
            textAlign: pw.TextAlign.center,
            style: bold,
          ),
        ),
      ];
    }

    return [
      pw.Center(
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: ecf.qrUrl!,
          width: 96,
          height: 96,
        ),
      ),
      pw.SizedBox(height: 3),
      if (_hasText(ecf.securityCode))
        pw.Center(
          child: pw.Text(
            'Código de Seguridad: ${ecf.securityCode}',
            textAlign: pw.TextAlign.center,
            style: base,
          ),
        ),
      if (ecf.signedAt != null)
        pw.Center(
          child: pw.Text(
            'Fecha de Firma Digital: ${formatDateTime(ecf.signedAt!)}',
            textAlign: pw.TextAlign.center,
            style: muted,
          ),
        ),
    ];
  }

  /// Separador discontinuo estilo ticket térmico clásico (- - - - -).
  /// Se renderiza como texto plano para no depender de `BorderStyle.dashed`
  /// (que no existe en `pdf ^3.12`).
  pw.Widget _thermalDashedDivider() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Text(
        '- ' * 32,
        textAlign: pw.TextAlign.center,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(
          fontSize: 7,
          color: PdfColors.grey600,
        ),
      ),
    );
  }

  pw.Widget _thermalMetaRow(
    String label,
    String value, {
    required pw.TextStyle bold,
    required pw.TextStyle base,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Center(
        child: pw.RichText(
          textAlign: pw.TextAlign.center,
          text: pw.TextSpan(
            children: [
              pw.TextSpan(text: '$label  ', style: bold),
              pw.TextSpan(text: value, style: base),
            ],
          ),
        ),
      ),
    );
  }

  pw.Widget _thermalItemsTable(
    PrintDocumentData data, {
    required pw.TextStyle base,
    required pw.TextStyle bold,
    required pw.TextStyle muted,
  }) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1),   // Nombre (toma el espacio restante)
        1: pw.FixedColumnWidth(42), // Precio (los montos ya no traen moneda)
        2: pw.FixedColumnWidth(28), // Cant. — centrado, con aire a los lados
        3: pw.FixedColumnWidth(48), // Total
      },
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey700, width: 0.5),
            ),
          ),
          children: [
            _thermalCell('Nombre', style: bold),
            _thermalCell('Precio', style: bold, align: pw.Alignment.centerRight),
            _thermalCell('Cant.', style: bold, align: pw.Alignment.center),
            _thermalCell('Total', style: bold, align: pw.Alignment.centerRight),
          ],
        ),
        for (final item in data.items)
          pw.TableRow(
            children: [
              _thermalCell(item.description, style: base),
              _thermalCell(
                moneyPlain(item.unitPrice),
                style: base,
                align: pw.Alignment.centerRight,
              ),
              _thermalCell(
                _qty(item.quantity),
                style: base,
                align: pw.Alignment.center,
              ),
              _thermalCell(
                moneyPlain(item.lineTotal),
                style: base,
                align: pw.Alignment.centerRight,
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _thermalCell(
    String text, {
    required pw.TextStyle style,
    pw.Alignment align = pw.Alignment.centerLeft,
  }) {
    return pw.Padding(
      // Padding interno mayor: separa visualmente columnas (antes 1pt
      // hacía que "2" tocara "RD$ 1,100.00").
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      child: pw.Align(
        alignment: align,
        child: pw.Text(text, style: style),
      ),
    );
  }

  pw.Widget _thermalTotals(
    PrintDocumentData data, {
    required pw.TextStyle base,
    required pw.TextStyle bold,
  }) {
    pw.Widget line(String label, String value, {bool emphasized = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text(label, style: emphasized ? bold : base),
            pw.SizedBox(width: 12),
            pw.SizedBox(
              width: 80,
              child: pw.Text(
                value,
                textAlign: pw.TextAlign.right,
                style: emphasized ? bold : base,
              ),
            ),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        line('Subtotal', moneyPlain(data.totals.subtotal)),
        if (data.totals.discount > 0)
          line('Descuento', '-${moneyPlain(data.totals.discount)}'),
        if (data.totals.serviceCharge > 0)
          line('Servicio', moneyPlain(data.totals.serviceCharge)),
        if (data.totals.tax > 0) line('ITBIS', moneyPlain(data.totals.tax)),
        line('Total', moneyPlain(data.totals.total), emphasized: true),
        if (data.changeAmount != null && data.changeAmount! >= 0)
          line('Cambio', moneyPlain(data.changeAmount!)),
        if (data.totals.balance > 0)
          line('Pendiente', moneyPlain(data.totals.balance), emphasized: true),
        for (final payment in data.payments)
          line(payment.method, moneyPlain(payment.amount)),
      ],
    );
  }

  /// Encabezado del A4: logo a un lado y los datos de la empresa —nombre,
  /// dirección, correo, teléfono y RNC— centrados en la hoja, como la factura
  /// de referencia del cliente.
  ///
  /// `data.logoOnLeft` (espejo de `app_settings.invoice_logo_position`) decide
  /// de qué lado va el logo. El lado opuesto lleva un hueco del mismo ancho
  /// para que el bloque de la empresa quede centrado respecto a la hoja y no
  /// respecto al espacio sobrante.
  ///
  /// El número de documento y el bloque fiscal (tipo de comprobante + NCF) ya
  /// no viven aquí: bajaron junto al bloque del cliente ([_clientBlock]).
  pw.Widget _header(PrintDocumentData data, Uint8List? logoBytes) {
    final logoSlot = pw.SizedBox(
      width: _kLogoSlotWidth,
      child: logoBytes == null
          ? null
          : pw.Image(
              pw.MemoryImage(logoBytes),
              height: 62,
              alignment: data.logoOnLeft
                  ? pw.Alignment.topLeft
                  : pw.Alignment.topRight,
              fit: pw.BoxFit.contain,
            ),
    );
    final company = pw.Expanded(child: _companyBlock(data));

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: data.logoOnLeft
          ? [logoSlot, company, pw.SizedBox(width: _kLogoSlotWidth)]
          : [pw.SizedBox(width: _kLogoSlotWidth), company, logoSlot],
    );
  }

  /// Datos de la empresa centrados: nombre comercial, dirección, correo,
  /// teléfono y RNC.
  pw.Widget _companyBlock(PrintDocumentData data) {
    pw.Widget line(
      String text, {
      double fontSize = 9.5,
      PdfColor? color = PdfColors.grey700,
      bool bold = false,
    }) {
      return pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? pw.FontWeight.bold : null,
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          data.branch.name,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 15,
            fontWeight: pw.FontWeight.bold,
            color: _kNavy,
          ),
        ),
        pw.SizedBox(height: 3),
        for (final l in _lines(data.branch.address)) line(l),
        if (_hasText(data.branch.email)) line(data.branch.email!),
        if (_hasText(data.branch.phone)) line('Teléfono: ${data.branch.phone}'),
        if (_hasText(data.branch.taxId))
          line(
            'RNC: ${data.branch.taxId}',
            fontSize: 10,
            color: null,
            bold: true,
          ),
      ],
    );
  }

  /// Número de documento + bloque fiscal (tipo de comprobante, NCF y su
  /// vigencia), alineado a la derecha del bloque del cliente.
  pw.Widget _fiscalBlock(PrintDocumentData data) {
    return pw.ConstrainedBox(
      constraints: const pw.BoxConstraints(maxWidth: 210),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            data.documentNumber,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: _kNavy,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            printReceiptHeadline(data),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (_hasText(data.ncf))
            pw.Text(
              'NCF: ${data.ncf}',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          // Cotización / cuenta guardada: no hay NCF que imprimir, se avisa.
          if (printPendingNcfNotice(data) != null)
            pw.Text(
              printPendingNcfNotice(data)!,
              textAlign: pw.TextAlign.right,
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfColors.grey600,
              ),
            ),
          if (data.ncfValidUntil != null)
            pw.Text(
              'NCF válido hasta ${formatDate(data.ncfValidUntil!)}',
              textAlign: pw.TextAlign.right,
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfColors.grey600,
              ),
            ),
        ],
      ),
    );
  }

  /// Banda central con líneas punteadas y el título según el comprobante.
  pw.Widget _titleBand(PrintDocumentData data) {
    return pw.Column(
      children: [
        _dottedLine(),
        pw.SizedBox(height: 7),
        pw.Center(
          child: pw.Text(
            printDocumentTitle(data),
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _kNavy,
              letterSpacing: 0.5,
            ),
          ),
        ),
        pw.SizedBox(height: 7),
        _dottedLine(),
      ],
    );
  }

  pw.Widget _dottedLine() {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
            color: PdfColors.grey500,
            width: 0.8,
            style: pw.BorderStyle.dotted,
          ),
        ),
      ),
      child: pw.SizedBox(width: double.infinity, height: 0),
    );
  }

  pw.Widget _clientBlock(PrintDocumentData data) {
    final c = data.customer;
    pw.Widget row(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 96,
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
            ),
          ],
        ),
      );
    }

    // Etiqueta del documento según su prefijo (RNC / Cédula / etc.).
    final docRaw = (c?.document ?? '').toLowerCase();
    final docLabel = docRaw.contains('céd') || docRaw.contains('ced')
        ? 'Cédula:'
        : docRaw.contains('pasa')
            ? 'Pasaporte:'
            : 'RNC:';

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              row('Cliente:', c?.name ?? 'Consumidor Final'),
              row(docLabel, _docNumberOnly(c?.document) ?? 'N/A'),
              if (_hasText(c?.address)) row('Dirección:', c!.address!),
              if (_hasText(c?.phone)) row('Teléfono:', c!.phone!),
              if (_hasText(c?.email)) row('Email:', c!.email!),
              row('Fecha:', formatDate(data.issuedAt)),
              if (_hasText(data.paymentTermsLabel))
                row('Forma de pago:', data.paymentTermsLabel!),
              if (_hasText(data.referenceNumber)) row('', data.referenceNumber!),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        // Número de documento + NCF: bajaron del encabezado a esta fila para
        // dejar la marca sola arriba, como en la factura de referencia.
        _fiscalBlock(data),
      ],
    );
  }

  /// Detalle del documento: PRODUCTO/SERVICIO · PRECIO · CANTIDAD ·
  /// [%DESC] · SUBTOTAL · [ITBIS] · VALOR TOTAL.
  ///
  /// El rótulo de la primera columna se adapta a lo que se factura — ver
  /// [printItemsColumnLabel].
  ///
  /// SUBTOTAL es la base imponible de la línea (precio × cantidad menos
  /// descuento, sin ITBIS), de modo que VALOR TOTAL = SUBTOTAL + ITBIS.
  pw.Widget _itemsTable(
    pw.Context context,
    PrintDocumentData data,
    double contentWidth,
  ) {
    const right = pw.Alignment.centerRight;
    final showTax = data.showTax;
    // %DESC solo aparece si alguna línea trae descuento. Una factura sin
    // descuentos no debe cargar una columna llena de guiones.
    final showDiscount = data.items.any((it) => it.hasDiscount);

    // Ancho útil del A4 con margen 36 ≈ 523pt. Las columnas numéricas ya no
    // cargan el símbolo de moneda, así que van estrechas; PRODUCTO/SERVICIO
    // toma todo lo que sobre, de modo que al ocultar %DESC o ITBIS la
    // descripción gana ese espacio.
    final numericWidths = <double>[
      58, // PRECIO
      48, // CANTIDAD
      if (showDiscount) 50, // %DESC
      64, // SUBTOTAL
      if (showTax) 56, // ITBIS
      68, // VALOR TOTAL
    ];
    final columnWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1), // PRODUCTO/SERVICIO
      for (var i = 0; i < numericWidths.length; i++)
        i + 1: pw.FixedColumnWidth(numericWidths[i]),
    };
    // Lo que sobra tras las columnas fijas es lo que le toca a la descripción
    // (menos el padding horizontal de la celda).
    final descriptionWidth = contentWidth -
        numericWidths.fold<double>(0, (sum, w) => sum + w) -
        4;

    pw.Widget hCell(String text, {pw.Alignment align = pw.Alignment.centerLeft}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: pw.Align(
          alignment: align,
          child: _oneLine(
            text,
            align: align,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
        ),
      );
    }

    pw.Widget cell(
      String text, {
      pw.Alignment align = pw.Alignment.centerLeft,
      bool bold = false,
    }) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: pw.Align(
          alignment: align,
          child: _oneLine(
            text,
            align: align,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : null,
            ),
          ),
        ),
      );
    }

    // Descripción + nota de la línea dentro de la MISMA celda (no rompe el
    // conteo de columnas de pw.Table).
    //
    // La descripción va en un solo renglón para que nombre, cantidad y precio
    // queden en la misma fila: si no entra a 9pt se achica lo justo, hasta el
    // piso legible de [_kMinItemFontSize]. Solo un nombre desmedido llega a
    // ese piso, y ahí sí se permite un segundo renglón antes que imprimirlo
    // ilegible o cortado.
    pw.Widget descriptionCell(PrintDocumentItem it) {
      final size = _fitFontSize(
        context,
        it.description,
        maxWidth: descriptionWidth,
        baseFontSize: 9,
      );
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              it.description,
              style: pw.TextStyle(fontSize: size),
              maxLines: size > _kMinItemFontSize ? 1 : 2,
              softWrap: size <= _kMinItemFontSize,
            ),
            if (_hasText(it.notes))
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 1),
                child: _oneLine(
                  it.notes!,
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return pw.Table(
      columnWidths: columnWidths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey700, width: 0.8),
              bottom: pw.BorderSide(color: PdfColors.grey700, width: 0.8),
            ),
          ),
          children: [
            hCell(printItemsColumnLabel(data.items)),
            hCell('PRECIO', align: right),
            hCell('CANTIDAD', align: pw.Alignment.center),
            if (showDiscount) hCell('%DESC', align: right),
            hCell('SUBTOTAL', align: right),
            if (showTax) hCell('ITBIS', align: right),
            hCell('VALOR TOTAL', align: right),
          ],
        ),
        for (final it in data.items)
          pw.TableRow(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
              ),
            ),
            children: [
              descriptionCell(it),
              cell(moneyPlain(it.unitPrice), align: right),
              cell(_qty(it.quantity), align: pw.Alignment.center),
              if (showDiscount)
                cell(
                  it.hasDiscount ? _percent(it.discountPercent) : '-',
                  align: right,
                ),
              cell(moneyPlain(it.lineSubtotal), align: right),
              if (showTax)
                cell(
                  it.lineTax > 0.0049 ? moneyPlain(it.lineTax) : '-',
                  align: right,
                ),
              cell(moneyPlain(it.lineTotal), align: right, bold: true),
            ],
          ),
      ],
    );
  }

  /// Datos bancarios + nota legal (izquierda) y "TOTAL A PAGAR" en rojo
  /// (derecha).
  pw.Widget _bankAndTotal(PrintDocumentData data) {
    final bankLines = _lines(data.branch.bankInfo);
    final legalLines = _legalFooterLines(data.legalFooterText);
    final legalTitle = data.documentType == PrintDocumentType.quote
        ? 'Términos y condiciones:'
        : 'Nota:';
    // El ITBIS solo se desglosa si el documento lleva impuesto (data.showTax).
    final showBreakdown = (data.showTax && data.totals.tax > 0.0049) ||
        data.totals.discount > 0.0049 ||
        data.totals.serviceCharge > 0.0049;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final line in bankLines)
                pw.Text(
                  line,
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey800,
                  ),
                ),
              if (legalLines.isNotEmpty) ...[
                pw.SizedBox(height: bankLines.isEmpty ? 0 : 8),
                pw.Text(
                  legalTitle,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                  ),
                ),
                for (final line in legalLines)
                  pw.Text(
                    line,
                    style: const pw.TextStyle(
                      fontSize: 8.5,
                      color: PdfColors.grey700,
                    ),
                  ),
              ],
            ],
          ),
        ),
        pw.SizedBox(width: 16),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if (showBreakdown) ...[
              _miniTotal('Subtotal', moneyPlain(data.totals.subtotal)),
              if (data.totals.discount > 0.0049)
                _miniTotal('Descuento', '-${moneyPlain(data.totals.discount)}'),
              if (data.totals.serviceCharge > 0.0049)
                _miniTotal('Ley / Servicio', moneyPlain(data.totals.serviceCharge)),
              if (data.showTax && data.totals.tax > 0.0049)
                _miniTotal('ITBIS', moneyPlain(data.totals.tax)),
              pw.SizedBox(height: 3),
            ],
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'TOTAL A\nPAGAR',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Text(
                  moneyPlain(data.totals.total),
                  style: pw.TextStyle(
                    fontSize: 17,
                    fontWeight: pw.FontWeight.bold,
                    color: _kRed,
                  ),
                ),
              ],
            ),
            if (data.totals.balance > 0.0049)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: _miniTotal(
                  'Balance pendiente',
                  moneyPlain(data.totals.balance),
                ),
              ),
          ],
        ),
      ],
    );
  }

  pw.Widget _miniTotal(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            '$label:',
            style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey600),
          ),
          pw.SizedBox(width: 8),
          pw.Text(value, style: const pw.TextStyle(fontSize: 9.5)),
        ],
      ),
    );
  }

  /// Firma del emisor + bloque OBSERVACION (formulario del receptor) + QR.
  pw.Widget _signatureAndObservation(
    PrintDocumentData data,
    Uint8List? qrBytes,
  ) {
    pw.Widget formLine(String label) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          '$label _______________________',
          style: const pw.TextStyle(fontSize: 9.5),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (_hasText(data.branch.signatoryName)) ...[
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Column(
              children: [
                pw.Container(
                  width: 220,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(color: PdfColors.grey500, width: 0.8),
                    ),
                  ),
                  padding: const pw.EdgeInsets.only(top: 3),
                  child: pw.Text(
                    data.branch.signatoryName!,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ),
                if (_hasText(data.branch.signatoryTitle))
                  pw.Text(
                    data.branch.signatoryTitle!,
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey600,
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
        ],
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'OBSERVACION:',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (_hasText(data.observation))
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Text(
                        data.observation!,
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ),
                  formLine('Nombre del representante:'),
                  formLine('Cédula o ID:'),
                  formLine('Firma:'),
                  formLine('Fecha:'),
                ],
              ),
            ),
            // e-CF: el QR de verificación DGII (Norma 01-2020) tiene
            // prioridad sobre el QR decorativo de la empresa.
            if (data.ecf?.hasQr ?? false) ...[
              pw.SizedBox(width: 16),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: data.ecf!.qrUrl!,
                    width: 92,
                    height: 92,
                  ),
                  if (_hasText(data.ecf!.securityCode))
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 3),
                      child: pw.Text(
                        'Código de Seguridad: ${data.ecf!.securityCode}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ),
                  if (data.ecf!.signedAt != null)
                    pw.Text(
                      'Firma Digital: ${formatDateTime(data.ecf!.signedAt!)}',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey600,
                      ),
                    ),
                ],
              ),
            ] else if (data.ecf?.statusMessage != null) ...[
              pw.SizedBox(width: 16),
              pw.Text(
                data.ecf!.statusMessage!,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ] else if (qrBytes != null) ...[
              pw.SizedBox(width: 16),
              pw.Image(pw.MemoryImage(qrBytes), width: 92, height: 92),
            ],
          ],
        ),
      ],
    );
  }
}

/// Título del documento en mayúsculas, según el comprobante seleccionado. Para
/// venta usa el `receiptTypeLabel`; para cotización siempre "COTIZACIÓN".
/// Público porque la vista previa A4 debe mostrar exactamente lo mismo.
String printDocumentTitle(PrintDocumentData data) {
  // Cuenta guardada: la venta sigue pendiente, no consumió NCF y no puede
  // entregarse como factura. Manda sobre cualquier tipo de comprobante.
  if (data.isPendingAccount) return 'CUENTA GUARDADA - DOCUMENTO NO FISCAL';
  if (data.documentType == PrintDocumentType.quote) return 'COTIZACIÓN';
  if (data.documentType == PrintDocumentType.paymentReceipt) {
    return 'RECIBO DE ABONO';
  }
  if (data.documentType == PrintDocumentType.expenseVoucher) {
    return 'COMPROBANTE DE GASTO';
  }
  if (data.documentType == PrintDocumentType.purchaseOrder) {
    return 'ORDEN DE COMPRA';
  }
  if (data.documentType == PrintDocumentType.creditNote) {
    return 'NOTA DE CRÉDITO';
  }
  final label = (data.receiptTypeLabel ?? '').toLowerCase();
  // e-CF: la representación impresa debe identificar el documento electrónico.
  final electronic = (data.ncf ?? '').startsWith('E');
  if (label.contains('sin comprobante')) return 'NOTA DE VENTA';
  if (label.contains('consumidor')) {
    return electronic
        ? 'FACTURA DE CONSUMO ELECTRÓNICA'
        : 'FACTURA PARA CONSUMIDOR FINAL';
  }
  if (label.contains('crédito') ||
      label.contains('credito') ||
      label.contains('fiscal')) {
    return electronic
        ? 'FACTURA DE CRÉDITO FISCAL ELECTRÓNICA'
        : 'FACTURA CON CRÉDITO FISCAL';
  }
  if (label.contains('gubernamental')) {
    return electronic ? 'FACTURA GUBERNAMENTAL ELECTRÓNICA' : 'FACTURA GUBERNAMENTAL';
  }
  if (label.contains('especial')) {
    return electronic ? 'FACTURA RÉGIMEN ESPECIAL ELECTRÓNICA' : 'FACTURA RÉGIMEN ESPECIAL';
  }
  if (label.contains('exporta')) {
    return electronic ? 'FACTURA DE EXPORTACIÓN ELECTRÓNICA' : 'FACTURA DE EXPORTACIÓN';
  }
  return electronic ? 'FACTURA ELECTRÓNICA' : 'FACTURA';
}

/// Rótulo de la primera columna del detalle según lo que se está facturando:
/// `PRODUCTO` si todas las líneas son productos, `SERVICIO` si todas son
/// servicios y `PRODUCTO/SERVICIO` si hay de los dos.
///
/// También cae en `PRODUCTO/SERVICIO` cuando alguna línea no sabe qué es
/// (`isService == null`): los documentos que no salen del catálogo —recibo de
/// abono, comprobante de gasto, orden de compra— no traen el dato, y rotularlos
/// como una cosa u otra sería inventar.
///
/// Público porque la vista previa A4 debe mostrar exactamente lo mismo.
String printItemsColumnLabel(List<PrintDocumentItem> items) {
  if (items.isEmpty) return 'PRODUCTO/SERVICIO';
  if (items.every((it) => it.isService == false)) return 'PRODUCTO';
  if (items.every((it) => it.isService == true)) return 'SERVICIO';
  return 'PRODUCTO/SERVICIO';
}

/// Etiqueta del bloque fiscal del encabezado A4, en texto largo capitalizado
/// ("Factura de Crédito Fiscal").
///
/// En la cotización imprime el comprobante que se emitirá al facturar
/// (`receiptTypeLabel`), no la palabra "Cotización": el cliente pidió ver el
/// tipo de comprobante. El título central sigue siendo "COTIZACIÓN".
///
/// En una cuenta guardada nunca rotula "Factura …": el documento no es fiscal.
String printReceiptHeadline(PrintDocumentData data) {
  if (data.isPendingAccount) return 'Cuenta guardada — documento no fiscal';
  if (data.documentType == PrintDocumentType.quote) {
    final label = (data.receiptTypeLabel ?? '').trim();
    return label.isEmpty ? 'Cotización' : label;
  }
  return _titleCase(printDocumentTitle(data));
}

/// Aviso que reemplaza al NCF cuando el documento todavía no consumió una
/// secuencia: la cotización lo hace al facturarse y la cuenta guardada al
/// cobrarse. Devuelve null cuando no aplica (o cuando ya trae NCF real).
String? printPendingNcfNotice(PrintDocumentData data) {
  if (_hasText(data.ncf)) return null;
  if (data.isPendingAccount) return 'NCF: se asigna al cobrar';
  if (data.documentType != PrintDocumentType.quote) return null;
  return 'NCF: se asigna al facturar';
}

/// Conectores que se mantienen en minúscula al capitalizar el título.
const _kLowercaseWords = {'de', 'del', 'la', 'las', 'el', 'los', 'para', 'con', 'y'};

String _titleCase(String value) {
  final words = value.toLowerCase().split(' ');
  return [
    for (var i = 0; i < words.length; i++)
      if (words[i].isEmpty)
        words[i]
      else if (i > 0 && _kLowercaseWords.contains(words[i]))
        words[i]
      else
        '${words[i][0].toUpperCase()}${words[i].substring(1)}',
  ].join(' ');
}

/// Divide un texto multilínea en líneas no vacías (para dirección / banco).
List<String> _lines(String? text) {
  if (text == null) return const [];
  return text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);
}

/// Acota la nota legal al pie: el A4 es una sola página con un `Spacer`, así
/// que un texto largo desbordaría. Máximo [maxLines] líneas y [maxChars]
/// caracteres en total; lo que sobra se corta con puntos suspensivos.
List<String> _legalFooterLines(
  String? text, {
  int maxLines = 8,
  int maxChars = 600,
}) {
  final source = _lines(text);
  if (source.isEmpty) return const [];

  final result = <String>[];
  var used = 0;
  for (final line in source.take(maxLines)) {
    final remaining = maxChars - used;
    if (remaining <= 0) break;
    if (line.length <= remaining) {
      result.add(line);
      used += line.length;
    } else {
      result.add('${line.substring(0, remaining).trimRight()}…');
      break;
    }
  }
  return result;
}

/// Quita el prefijo "RNC:"/"CÉDULA:" del documento del cliente y deja el número.
String? _docNumberOnly(String? doc) {
  if (!_hasText(doc)) return null;
  final idx = doc!.indexOf(':');
  return idx >= 0 ? doc.substring(idx + 1).trim() : doc.trim();
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

String _qty(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}

/// Porcentaje de descuento como se imprime en la columna %DESC: sin decimales
/// cuando es redondo (`10%`) y con hasta dos cuando no (`12.5%`).
String _percent(double value) {
  final rounded = (value * 100).roundToDouble() / 100;
  if (rounded == rounded.roundToDouble()) {
    return '${rounded.toStringAsFixed(0)}%';
  }
  final text = rounded.toStringAsFixed(2);
  return '${text.endsWith('0') ? text.substring(0, text.length - 1) : text}%';
}
