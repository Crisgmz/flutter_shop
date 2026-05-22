import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../../inventory/data/file_io_helper.dart';
import '../data/purchases_excel_service.dart';
import '../data/purchases_repository.dart';
import 'purchases_providers.dart';

class PurchasesPage extends ConsumerStatefulWidget {
  const PurchasesPage({super.key});

  @override
  ConsumerState<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends ConsumerState<PurchasesPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(purchasesListProvider);
    final query = ref.watch(purchasesSearchProvider).trim().toLowerCase();

    return ModulePage(
      title: 'Compras',
      description: 'Registro de facturas de proveedor y entrada de inventario.',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(purchasesListProvider);
            ref.invalidate(purchaseSuppliersProvider);
            ref.invalidate(purchaseProductsProvider);
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
        const SizedBox(width: AppTokens.s8),
        _buildExportMenu(),
        const SizedBox(width: AppTokens.s8),
        FilledButton.icon(
          onPressed: _onNewPurchase,
          icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
          label: const Text('Nueva compra'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) =>
                ref.read(purchasesSearchProvider.notifier).state = value,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Buscar por número, proveedor o factura',
            ),
          ),
          const SizedBox(height: AppTokens.s24),
          purchasesAsync.when(
            data: (purchases) {
              final filtered = purchases
                  .where((purchase) {
                    if (query.isEmpty) return true;
                    final searchable = [
                      purchase.purchaseNumber ?? '',
                      purchase.invoiceNumber ?? '',
                      purchase.supplierName,
                      purchase.status,
                    ].join(' ').toLowerCase();
                    return searchable.contains(query);
                  })
                  .toList(growable: false);

              final monthTotal = filtered.fold<double>(
                0,
                (sum, item) => sum + item.totalAmount,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KpisGrid(count: filtered.length, total: monthTotal),
                  const SizedBox(height: AppTokens.s24),
                  DataTableShell(
                    title: 'Compras (${filtered.length})',
                    child: filtered.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(AppTokens.s20),
                            child: Text(
                              'No hay compras registradas.',
                              style: TextStyle(color: AppTokens.mutedForeground),
                            ),
                          )
                        : DataTable(
                            columns: const [
                              DataColumn(label: Text('Fecha')),
                              DataColumn(label: Text('Compra')),
                              DataColumn(label: Text('Factura')),
                              DataColumn(label: Text('Proveedor')),
                              DataColumn(label: Text('Estado')),
                              DataColumn(label: Text('Pago')),
                              DataColumn(label: Text('Recepción')),
                              DataColumn(label: Text('Total'), numeric: true),
                            ],
                            rows: filtered
                                .map(
                                  (purchase) => DataRow(
                                    cells: [
                                      DataCell(Text(formatDate(purchase.purchaseDate))),
                                      DataCell(Text(purchase.purchaseNumber ?? '-')),
                                      DataCell(Text(purchase.invoiceNumber ?? '-')),
                                      DataCell(Text(
                                        purchase.supplierName,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      )),
                                      DataCell(StatusBadge(
                                        label: _pretty(purchase.status),
                                        status: purchase.status,
                                      )),
                                      DataCell(StatusBadge(
                                        label: _prettyPayment(purchase.paymentStatus),
                                        status: _paymentStatusKey(purchase.paymentStatus),
                                      )),
                                      DataCell(_ReceiptProgress(purchase: purchase)),
                                      DataCell(Text(
                                        money(purchase.totalAmount),
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      )),
                                    ],
                                  ),
                                )
                                .toList(growable: false),
                          ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorCard(
              message: 'No se pudieron cargar compras: $error',
              onRetry: () => ref.invalidate(purchasesListProvider),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onNewPurchase() async {
    List<PurchaseSupplier> suppliers;
    List<PurchaseProduct> products;

    try {
      suppliers = await ref.read(purchaseSuppliersProvider.future);
      products = await ref.read(purchaseProductsProvider.future);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir formulario: $error')),
      );
      return;
    }

    if (!mounted) return;

    final input = await showDialog<PurchaseCreateInput>(
      context: context,
      builder: (_) =>
          _NewPurchaseDialog(suppliers: suppliers, products: products),
    );

    if (input == null || !mounted) return;

    final repository = ref.read(purchasesRepositoryProvider);

    try {
      await repository.createPurchase(input);
      if (!mounted) return;

      ref.invalidate(purchasesListProvider);
      ref.invalidate(purchaseProductsProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compra registrada exitosamente.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar compra: $error')),
      );
    }
  }

  Widget _buildExportMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Exportar reporte',
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value == 'export_excel') {
          _onExportPurchasesExcel();
        } else if (value == 'export_pdf') {
          _onExportPurchasesPdf();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'export_excel',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.table_chart_outlined, size: 18),
            title: Text('Exportar a Excel'),
          ),
        ),
        PopupMenuItem(
          value: 'export_pdf',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.picture_as_pdf_outlined, size: 18),
            title: Text('Exportar a PDF'),
          ),
        ),
      ],
      child: OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.ios_share_rounded, size: 18),
        label: const Text('Exportar'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTokens.foreground,
          disabledForegroundColor: AppTokens.foreground,
        ),
      ),
    );
  }

  Future<void> _onExportPurchasesExcel() async {
    final List<PurchaseSummary> purchases;
    try {
      purchases = await ref.read(purchasesListProvider.future);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar compras: $e')),
      );
      return;
    }
    if (!mounted) return;
    if (purchases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay compras para exportar.')),
      );
      return;
    }

    try {
      final bytes = PurchasesExcelService().buildExport(purchases: purchases);
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: 'compras_${_timestamp()}.xlsx',
        dialogTitle: 'Guardar Compras Excel',
        extension: 'xlsx',
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Compras exportadas a Excel (${purchases.length} compras)'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar a Excel: $error')),
      );
    }
  }

  Future<void> _onExportPurchasesPdf() async {
    final List<PurchaseSummary> purchases;
    try {
      purchases = await ref.read(purchasesListProvider.future);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar compras: $e')),
      );
      return;
    }
    if (!mounted) return;
    if (purchases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay compras para exportar.')),
      );
      return;
    }

    try {
      final bytes = await _buildPurchasesPdf(purchases);
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: 'compras_${_timestamp()}.pdf',
        dialogTitle: 'Guardar Reporte de Compras',
        extension: 'pdf',
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reporte PDF exportado (${purchases.length} compras)'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar a PDF: $error')),
      );
    }
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
  }

  Future<Uint8List> _buildPurchasesPdf(List<PurchaseSummary> purchases) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.robotoRegular(),
        bold: await PdfGoogleFonts.robotoBold(),
        italic: await PdfGoogleFonts.robotoItalic(),
      ),
    );

    final accent = PdfColor.fromInt(0xFF0D6EFD); // AppTokens.primary
    final muted = PdfColor.fromInt(0xFF66798E);  // AppTokens.mutedForeground
    final borderCol = PdfColor.fromInt(0xFFE9ECEF);

    final totalAmount = purchases.fold<double>(0, (sum, p) => sum + p.totalAmount);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'REPORTE DE COMPRAS',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: accent,
                  ),
                ),
                pw.Text(
                  _fmtDateTime(DateTime.now()),
                  style: pw.TextStyle(fontSize: 10, color: muted),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Busi Pos Web — Sistema de Gestión Comercial',
              style: pw.TextStyle(fontSize: 9, color: muted),
            ),
            pw.SizedBox(height: 12),
            pw.Divider(height: 1, color: borderCol),
            pw.SizedBox(height: 16),
          ],
        ),
        footer: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Divider(height: 1, color: borderCol),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Busi Pos Web — Reporte generado automáticamente',
                  style: pw.TextStyle(fontSize: 8, color: muted),
                ),
                pw.Text(
                  'Pág. ${context.pageNumber} de ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, color: muted),
                ),
              ],
            ),
          ],
        ),
        build: (context) => [
          // KPI summary
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            margin: const pw.EdgeInsets.only(bottom: 20),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF8F9FA),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildPdfKpi('Transacciones', purchases.length.toString(), accent),
                _buildPdfKpi('Total Compras', money(totalAmount), accent),
              ],
            ),
          ),

          // Table
          pw.Table(
            border: pw.TableBorder(
              bottom: pw.BorderSide(color: borderCol, width: 0.5),
              horizontalInside: pw.BorderSide(color: borderCol, width: 0.5),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.2), // Fecha
              1: pw.FlexColumnWidth(2.0), // Código Compra
              2: pw.FlexColumnWidth(1.8), // Factura
              3: pw.FlexColumnWidth(2.5), // Proveedor
              4: pw.FlexColumnWidth(1.2), // Estado
              5: pw.FlexColumnWidth(1.2), // Pago
              6: pw.FlexColumnWidth(1.5), // Total
            },
            children: [
              // Header
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF8F9FA),
                ),
                children: [
                  _pdfHeaderCell('Fecha'),
                  _pdfHeaderCell('Compra'),
                  _pdfHeaderCell('Factura'),
                  _pdfHeaderCell('Proveedor'),
                  _pdfHeaderCell('Estado'),
                  _pdfHeaderCell('Pago'),
                  _pdfHeaderCell('Total', alignRight: true),
                ],
              ),
              // Rows
              ...purchases.map(
                (p) => pw.TableRow(
                  children: [
                    _pdfCell(p.purchaseDate.toIso8601String().split('T').first),
                    _pdfCell(p.purchaseNumber ?? '-'),
                    _pdfCell(p.invoiceNumber ?? '-'),
                    _pdfCell(p.supplierName, bold: true),
                    _pdfCell(_statusLabel(p.status)),
                    _pdfCell(_paymentStatusLabel(p.paymentStatus)),
                    _pdfCell(money(p.totalAmount), alignRight: true),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildPdfKpi(String label, String value, PdfColor color) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromInt(0xFF66798E),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfHeaderCell(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      ),
    );
  }

  pw.Widget _pdfCell(String text, {bool bold = false, bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      ),
    );
  }

  String _fmtDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return 'Borrador';
      case 'ordered':
        return 'Pedido';
      case 'posted':
        return 'Registrado';
      case 'received':
        return 'Recibido';
      case 'cancelled':
        return 'Cancelado';
      default:
        return status;
    }
  }

  String _paymentStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pendiente';
      case 'partial':
        return 'Parcial';
      case 'paid':
        return 'Pagado';
      case 'overdue':
        return 'Vencido';
      default:
        return status;
    }
  }
}

class _NewPurchaseDialog extends StatefulWidget {
  const _NewPurchaseDialog({required this.suppliers, required this.products});

  final List<PurchaseSupplier> suppliers;
  final List<PurchaseProduct> products;

  @override
  State<_NewPurchaseDialog> createState() => _NewPurchaseDialogState();
}

class _NewPurchaseDialogState extends State<_NewPurchaseDialog> {
  final _formKey = GlobalKey<FormState>();

  final _invoiceController = TextEditingController();
  final _notesController = TextEditingController();
  final _categoryController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _costController = TextEditingController(text: '0');
  final _taxController = TextEditingController(text: '0');

  String? _supplierId;
  DateTime _purchaseDate = DateTime.now();
  DateTime? _expectedAt;
  String _paymentStatus = 'paid';

  String? _lineProductId;
  final List<PurchaseLineInput> _lines = [];

  @override
  void initState() {
    super.initState();
    // El producto se elige escribiendo en el autocomplete — sin preselección.
  }

  @override
  void dispose() {
    _invoiceController.dispose();
    _notesController.dispose();
    _categoryController.dispose();
    _qtyController.dispose();
    _costController.dispose();
    _taxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = _round2(
      _lines.fold<double>(0, (sum, line) => sum + line.lineSubtotal),
    );
    final taxAmount = _round2(
      _lines.fold<double>(0, (sum, line) => sum + line.lineTax),
    );
    final total = _round2(subtotal + taxAmount);
    final dialogMobile = ResponsiveLayout.isMobile(context);

    return AlertDialog(
      title: const Text('Nueva compra'),
      content: SizedBox(
        width: dialogMobile ? double.maxFinite : 760,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _supplierId,
                  decoration: const InputDecoration(labelText: 'Proveedor'),
                  items: widget.suppliers
                      .map(
                        (supplier) => DropdownMenuItem<String>(
                          value: supplier.id,
                          child: Text(supplier.name),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => setState(() => _supplierId = value),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Selecciona proveedor';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _invoiceController,
                        decoration: const InputDecoration(
                          labelText: 'Número factura (opcional)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Fecha',
                          suffixIcon: IconButton(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_month_outlined),
                          ),
                        ),
                        controller: TextEditingController(
                          text: formatDate(_purchaseDate),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _paymentStatus,
                        decoration: const InputDecoration(labelText: 'Estado de pago'),
                        items: const [
                          DropdownMenuItem(value: 'pending', child: Text('Pendiente')),
                          DropdownMenuItem(value: 'partial', child: Text('Parcial')),
                          DropdownMenuItem(value: 'paid', child: Text('Pagado')),
                        ],
                        onChanged: (v) => setState(() => _paymentStatus = v ?? 'paid'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Fecha esperada (opcional)',
                          hintText: _expectedAt == null ? 'Sin fecha' : formatDate(_expectedAt!),
                          suffixIcon: IconButton(
                            onPressed: _pickExpectedDate,
                            icon: const Icon(Icons.calendar_month_outlined),
                          ),
                        ),
                        controller: TextEditingController(
                          text: _expectedAt == null ? '' : formatDate(_expectedAt!),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(
                    labelText: 'Categoría (opcional)',
                    hintText: 'Ej: mercancía, suministros, servicios',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notas'),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Agregar item',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (dialogMobile)
                  Column(
                    children: [
                      _ProductAutocomplete(
                        products: widget.products,
                        selectedId: _lineProductId,
                        onSelected: (product) {
                          setState(() {
                            _lineProductId = product.id;
                            _costController.text = product.cost.toStringAsFixed(
                              2,
                            );
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _qtyController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Cantidad',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _costController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Costo unitario',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _taxController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'ITBIS %',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: _addLine,
                          child: const Text('Agregar'),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _ProductAutocomplete(
                          products: widget.products,
                          selectedId: _lineProductId,
                          onSelected: (product) {
                            setState(() {
                              _lineProductId = product.id;
                              _costController.text = product.cost
                                  .toStringAsFixed(2);
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _qtyController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Cantidad',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _costController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Costo unitario',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _taxController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'ITBIS %',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _addLine,
                        child: const Text('Agregar'),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                if (_lines.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No hay items agregados.'),
                  )
                else
                  Column(
                    children: _lines
                        .asMap()
                        .entries
                        .map((entry) {
                          final index = entry.key;
                          final line = entry.value;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(line.product.name),
                            subtitle: Text(
                              'Cant: ${line.quantity.toStringAsFixed(2)} | Costo: ${money(line.unitCost)} | ITBIS: ${line.taxRate.toStringAsFixed(2)}%',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  money(line.lineTotal),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _removeLine(index),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                const Divider(height: 20),
                _totalRow('Subtotal', money(subtotal)),
                const SizedBox(height: 4),
                _totalRow('ITBIS', money(taxAmount)),
                const SizedBox(height: 4),
                _totalRow('Total', money(total), emphasized: true),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Registrar compra')),
      ],
    );
  }

  Widget _totalRow(String label, String value, {bool emphasized = false}) {
    final style = emphasized
        ? Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyMedium;

    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _purchaseDate = picked);
  }

  Future<void> _pickExpectedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedAt ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _expectedAt = picked);
  }

  void _addLine() {
    final productId = _lineProductId;
    if (productId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un producto.')));
      return;
    }

    final qty = double.tryParse(_qtyController.text);
    final cost = double.tryParse(_costController.text);
    final tax = double.tryParse(_taxController.text);

    if (qty == null || qty <= 0 || cost == null || cost < 0 || tax == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Datos de ítem inválidos.')));
      return;
    }

    final product = widget.products.firstWhere((item) => item.id == productId);

    setState(() {
      _lines.add(
        PurchaseLineInput(
          product: product,
          quantity: qty,
          unitCost: cost,
          taxRate: tax,
        ),
      );

      _qtyController.text = '1';
    });
  }

  void _removeLine(int index) {
    setState(() => _lines.removeAt(index));
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (_lines.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Agrega al menos un item.')));
      return;
    }

    final supplierId = _supplierId;
    if (supplierId == null || supplierId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona proveedor.')));
      return;
    }

    Navigator.of(context).pop(
      PurchaseCreateInput(
        supplierId: supplierId,
        purchaseDate: _purchaseDate,
        items: List<PurchaseLineInput>.from(_lines),
        invoiceNumber: _invoiceController.text,
        notes: _notesController.text,
        paymentStatus: _paymentStatus,
        purchaseCategory: _categoryController.text,
        expectedAt: _expectedAt,
      ),
    );
  }
}

class _KpisGrid extends StatelessWidget {
  const _KpisGrid({required this.count, required this.total});

  final int count;
  final double total;

  @override
  Widget build(BuildContext context) {
    final cards = [
      KPICard(
        label: 'Transacciones',
        value: count.toString(),
        icon: Icons.shopping_bag_outlined,
        trend: 'Compras registradas',
      ),
      KPICard(
        label: 'Total listado',
        value: money(total),
        icon: Icons.attach_money_rounded,
        trend: 'Monto total',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppTokens.breakpointCompact) {
          return Column(
            children: [cards[0], const SizedBox(height: AppTokens.s12), cards[1]],
          );
        }
        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[1]),
          ],
        );
      },
    );
  }
}

String _pretty(String value) {
  if (value.isEmpty) return '-';
  return value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

String _prettyPayment(String value) {
  switch (value) {
    case 'pending':
      return 'Pendiente';
    case 'partial':
      return 'Parcial';
    case 'paid':
      return 'Pagado';
    default:
      return _pretty(value);
  }
}

String _paymentStatusKey(String value) {
  switch (value) {
    case 'paid':
      return 'active';
    case 'partial':
      return 'partial';
    case 'pending':
    default:
      return 'inactive';
  }
}

double _round2(double value) => (value * 100).roundToDouble() / 100;

class _ReceiptProgress extends StatelessWidget {
  const _ReceiptProgress({required this.purchase});

  final PurchaseSummary purchase;

  @override
  Widget build(BuildContext context) {
    if (purchase.linesCount == 0) {
      return const Text('-', style: TextStyle(color: AppTokens.mutedForeground));
    }

    final pct = purchase.receiptProgress;
    final label =
        '${purchase.receivedQuantity.toStringAsFixed(0)}/${purchase.itemsQuantity.toStringAsFixed(0)}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 48,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusS),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              color: pct >= 1 ? AppTokens.success : AppTokens.warning,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

/// Campo de selección de producto con búsqueda por nombre.
/// Reemplaza al Dropdown para que el usuario pueda tipear y filtrar.
class _ProductAutocomplete extends StatefulWidget {
  const _ProductAutocomplete({
    required this.products,
    required this.selectedId,
    required this.onSelected,
  });

  final List<PurchaseProduct> products;
  final String? selectedId;
  final ValueChanged<PurchaseProduct> onSelected;

  @override
  State<_ProductAutocomplete> createState() => _ProductAutocompleteState();
}

class _ProductAutocompleteState extends State<_ProductAutocomplete> {
  @override
  Widget build(BuildContext context) {
    return Autocomplete<PurchaseProduct>(
      initialValue: widget.selectedId == null
          ? const TextEditingValue()
          : TextEditingValue(
              text: widget.products
                  .firstWhere(
                    (p) => p.id == widget.selectedId,
                    orElse: () => widget.products.first,
                  )
                  .name,
            ),
      displayStringForOption: (product) => product.name,
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return widget.products.take(20);
        return widget.products.where(
          (product) => product.name.toLowerCase().contains(query),
        );
      },
      onSelected: widget.onSelected,
      fieldViewBuilder: (
        context,
        controller,
        focusNode,
        onFieldSubmitted,
      ) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Producto',
            hintText: 'Escribí para buscar…',
            suffixIcon: controller.text.isEmpty
                ? const Icon(Icons.search, size: 18)
                : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      controller.clear();
                      focusNode.requestFocus();
                    },
                  ),
          ),
          onFieldSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 420),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final product = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(product),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              product.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            money(product.cost),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTokens.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
