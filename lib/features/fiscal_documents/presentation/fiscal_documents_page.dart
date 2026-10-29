import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/role_gate.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../../inventory/data/file_io_helper.dart';
import '../../settings/presentation/app_settings_providers.dart';
import '../../shell/presentation/shell_providers.dart'
    show shellCurrentBranchNameProvider;
import '../data/fiscal_consumo_summary.dart';
import '../data/fiscal_documents_repository.dart';
import '../data/fiscal_labels.dart';
import '../export/fiscal_documents_export.dart';
import 'fiscal_consumo_summary_panel.dart';
import 'fiscal_documents_providers.dart';

const _statusColors = <String, Color>{
  'pending': Color(0xFFF59E0B),
  'sent': Color(0xFF3B82F6),
  'approved': Color(0xFF22C55E),
  'rejected': Color(0xFFEF4444),
};

/// Estados del documento electrónico (e-CF vía Alanube/DGII).
const _ecfStatusLabels = <String, String>{
  'pending': 'e-CF pendiente',
  'sent': 'e-CF en proceso',
  'accepted': 'e-CF aceptado',
  'rejected': 'e-CF rechazado',
  'uncertain': 'e-CF sin confirmar',
};

const _ecfStatusColors = <String, Color>{
  'pending': Color(0xFFF59E0B),
  'sent': Color(0xFF3B82F6),
  'accepted': Color(0xFF22C55E),
  'rejected': Color(0xFFEF4444),
  'uncertain': AppTokens.warning,
};

const _receiptTypes = <String>[
  'consumer_final',
  'fiscal_credit',
  'governmental',
  'special',
  'export',
];

const _statusOptions = <String>[
  'pending',
  'sent',
  'approved',
  'rejected',
];

/// Filas que se pintan en pantalla. Un mes puede tener miles de comprobantes
/// y la tabla los construye todos de una vez; el PDF y el Excel llevan todo.
const _maxVisibleRows = 500;

class FiscalDocumentsPage extends ConsumerWidget {
  const FiscalDocumentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(fiscalViewProvider);
    final statusFilter = ref.watch(fiscalStatusFilterProvider);
    final receiptTypeFilter = ref.watch(fiscalReceiptTypeFilterProvider);
    final dateFrom = ref.watch(fiscalDateFromProvider);
    final dateTo = ref.watch(fiscalDateToProvider);
    final isSummary = view == FiscalDocumentsView.summary;

    return ModulePage(
      title: 'Comprobantes Fiscales',
      description: 'Documentos fiscales emitidos (NCF) por sucursal.',
      actions: [
        _DateRangeButton(
          dateFrom: dateFrom,
          dateTo: dateTo,
          onClear: () {
            ref.read(fiscalDateFromProvider.notifier).state = null;
            ref.read(fiscalDateToProvider.notifier).state = null;
          },
          onPick: (from, to) {
            ref.read(fiscalDateFromProvider.notifier).state = from;
            ref.read(fiscalDateToProvider.notifier).state = to;
          },
        ),
        // El resumen es siempre de facturas de consumo: tipo y estado no
        // aplican.
        if (!isSummary) _ReceiptTypeChip(selected: receiptTypeFilter),
        if (!isSummary) _StatusChip(selected: statusFilter),
        const _ExportButtons(),
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(fiscalDocumentsProvider);
            ref.invalidate(fiscalConsumoSummaryProvider);
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      child: isSummary ? const _SummaryView() : const _DetailView(),
    );
  }
}

class _ViewToggle extends ConsumerWidget {
  const _ViewToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<FiscalDocumentsView>(
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 13),
      ),
      segments: const [
        ButtonSegment(
          value: FiscalDocumentsView.summary,
          icon: Icon(Icons.summarize_outlined, size: 16),
          label: Text('Resumen'),
        ),
        ButtonSegment(
          value: FiscalDocumentsView.detail,
          icon: Icon(Icons.list_alt_outlined, size: 16),
          label: Text('Detallado'),
        ),
      ],
      selected: {ref.watch(fiscalViewProvider)},
      onSelectionChanged: (s) =>
          ref.read(fiscalViewProvider.notifier).state = s.first,
      showSelectedIcon: false,
    );
  }
}

/// PDF y Excel de la vista activa: el resumen DGII o el detallado con los
/// filtros aplicados.
class _ExportButtons extends ConsumerStatefulWidget {
  const _ExportButtons();

  @override
  ConsumerState<_ExportButtons> createState() => _ExportButtonsState();
}

class _ExportButtonsState extends ConsumerState<_ExportButtons> {
  bool _busy = false;

  Future<void> _export({required bool pdf}) async {
    setState(() => _busy = true);
    try {
      final exporter = FiscalDocumentsExport(
        settings: await ref.read(appSettingsProvider.future),
        branchName: ref.read(shellCurrentBranchNameProvider).valueOrNull,
      );
      final String fileName;
      final Uint8List bytes;

      if (ref.read(fiscalViewProvider) == FiscalDocumentsView.summary) {
        final summary = await ref.read(fiscalConsumoSummaryProvider.future);
        fileName = 'resumen_facturas_consumo_${summary.period}';
        bytes = pdf
            ? await exporter.summaryPdf(summary)
            : exporter.summaryXlsx(summary);
      } else {
        final docs = await ref.read(fiscalDocumentsProvider.future);
        final from = ref.read(fiscalDateFromProvider);
        final to = ref.read(fiscalDateToProvider);
        final filterLabel =
            _detailFilterLabel(ref, hasRange: from != null || to != null);
        fileName = 'comprobantes_detallado_${_stamp(DateTime.now())}';
        bytes = pdf
            ? await exporter.detailPdf(docs,
                from: from, to: to, filterLabel: filterLabel)
            : exporter.detailXlsx(docs,
                from: from, to: to, filterLabel: filterLabel);
      }

      final extension = pdf ? 'pdf' : 'xlsx';
      final saved = await FileIoHelper.saveBytes(
        bytes: bytes,
        fileName: '$fileName.$extension',
        extension: extension,
        dialogTitle: 'Guardar comprobantes fiscales',
      );
      if (!mounted || !saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(pdf ? 'PDF exportado.' : 'Excel exportado.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppTokens.s8,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _export(pdf: true),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('PDF'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _export(pdf: false),
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.grid_on_outlined, size: 18),
          label: const Text('Excel'),
        ),
      ],
    );
  }
}

/// Filtros del detallado en palabras, para el encabezado del archivo.
String? _detailFilterLabel(WidgetRef ref, {required bool hasRange}) {
  final type = ref.read(fiscalReceiptTypeFilterProvider);
  final status = ref.read(fiscalStatusFilterProvider);
  final parts = [
    if (type != null) fiscalReceiptLabel(type),
    if (status != null) fiscalStatusLabels[status] ?? status,
    if (!hasRange) 'Últimos 100 comprobantes',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String _stamp(DateTime d) => '${d.year}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';

class _DateRangeButton extends StatelessWidget {
  const _DateRangeButton({
    required this.dateFrom,
    required this.dateTo,
    required this.onClear,
    required this.onPick,
  });

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final VoidCallback onClear;
  final void Function(DateTime from, DateTime to) onPick;

  bool get _hasFilter => dateFrom != null || dateTo != null;

  @override
  Widget build(BuildContext context) {
    final label = _hasFilter
        ? '${dateFrom != null ? formatDate(dateFrom!) : '…'} – ${dateTo != null ? formatDate(dateTo!) : '…'}'
        : 'Rango fechas';

    return OutlinedButton.icon(
      onPressed: () async {
        if (_hasFilter) {
          onClear();
          return;
        }
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
          initialDateRange: dateFrom != null && dateTo != null
              ? DateTimeRange(start: dateFrom!, end: dateTo!)
              : null,
        );
        if (range == null) return;
        onPick(range.start, range.end);
      },
      icon: Icon(
        _hasFilter ? Icons.close : Icons.date_range_outlined,
        size: 18,
      ),
      label: Text(label),
    );
  }
}

class _ReceiptTypeChip extends ConsumerWidget {
  const _ReceiptTypeChip({required this.selected});

  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: selected,
        hint: const Text('Tipo comprobante'),
        isDense: true,
        borderRadius: BorderRadius.circular(AppTokens.radiusS),
        items: [
          const DropdownMenuItem(value: null, child: Text('Todos los tipos')),
          ..._receiptTypes.map(
            (type) => DropdownMenuItem(
              value: type,
              child: Text(fiscalReceiptLabel(type)),
            ),
          ),
        ],
        onChanged: (value) {
          ref.read(fiscalReceiptTypeFilterProvider.notifier).state = value;
        },
      ),
    );
  }
}

class _StatusChip extends ConsumerWidget {
  const _StatusChip({required this.selected});

  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: selected,
        hint: const Text('Estado'),
        isDense: true,
        borderRadius: BorderRadius.circular(AppTokens.radiusS),
        items: [
          const DropdownMenuItem(value: null, child: Text('Todos los estados')),
          ..._statusOptions.map(
            (status) => DropdownMenuItem(
              value: status,
              child: Text(fiscalStatusLabels[status] ?? status),
            ),
          ),
        ],
        onChanged: (value) {
          ref.read(fiscalStatusFilterProvider.notifier).state = value;
        },
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No se pudieron cargar los comprobantes: $error'),
            const SizedBox(height: AppTokens.s12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Detallado ────────────────────────────────────────────────────────────

class _DetailView extends ConsumerWidget {
  const _DetailView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(fiscalDocumentsProvider);
    final hasRange = ref.watch(fiscalDateFromProvider) != null ||
        ref.watch(fiscalDateToProvider) != null;

    return docsAsync.when(
      data: (docs) {
        final title = !hasRange && docs.length >= 100
            ? 'Documentos fiscales (últimos ${docs.length})'
            : 'Documentos fiscales (${docs.length})';
        if (docs.isEmpty) {
          return DataTableShell(
            title: title,
            trailing: const _ViewToggle(),
            scrollable: false,
            child: const EmptyStateCard(
              icon: Icons.receipt_long_outlined,
              message:
                  'No se encontraron documentos fiscales para los filtros seleccionados.',
            ),
          );
        }
        return _DocsList(docs: docs, title: title);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _LoadError(
        error: error,
        onRetry: () => ref.invalidate(fiscalDocumentsProvider),
      ),
    );
  }
}

class _DocsList extends ConsumerWidget {
  const _DocsList({required this.docs, required this.title});

  final List<FiscalDocument> docs;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = docs.length > _maxVisibleRows
        ? docs.sublist(0, _maxVisibleRows)
        : docs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DataTableShell(
          title: title,
          trailing: const _ViewToggle(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: AppTokens.s16,
              columns: const [
                DataColumn(label: Text('NCF')),
                DataColumn(label: Text('Tipo')),
                DataColumn(label: Text('Estado')),
                DataColumn(label: Text('RNC')),
                DataColumn(label: Text('Cliente')),
                DataColumn(label: Text('Método de pago')),
                DataColumn(label: Text('Emisión')),
                DataColumn(label: Text('Total'), numeric: true),
                DataColumn(label: Text('ITBIS'), numeric: true),
              ],
              rows: visible
                  .map((doc) => _buildRow(context, doc, ref))
                  .toList(growable: false),
            ),
          ),
        ),
        if (visible.length < docs.length)
          Padding(
            padding: const EdgeInsets.only(top: AppTokens.s8),
            child: Text(
              'Mostrando ${visible.length} de ${docs.length}. '
              'El PDF y el Excel llevan todos.',
              style: const TextStyle(
                fontSize: 12,
                color: AppTokens.mutedForeground,
              ),
            ),
          ),
      ],
    );
  }

  DataRow _buildRow(BuildContext context, FiscalDocument doc, WidgetRef ref) {
    final statusColor = doc.isCancelled
        ? AppTokens.destructive
        : _statusColors[doc.fiscalStatus] ?? AppTokens.mutedForeground;
    final rnc = doc.customerDocumentNumber?.trim() ?? '';

    return DataRow(
      cells: [
        DataCell(
          GestureDetector(
            onTap: () => _showDetail(context, doc, ref),
            child: Text(
              doc.ncf,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        DataCell(Text(
          fiscalReceiptLabel(doc.receiptType),
          style: const TextStyle(fontSize: 13),
        )),
        DataCell(
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusS),
                ),
                child: Text(
                  fiscalStatusLabel(doc),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              if (doc.isElectronic && doc.ecfStatus != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.s8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (_ecfStatusColors[doc.ecfStatus] ??
                            AppTokens.mutedForeground)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTokens.radiusS),
                  ),
                  child: Text(
                    _ecfStatusLabels[doc.ecfStatus] ?? doc.ecfStatus!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _ecfStatusColors[doc.ecfStatus] ??
                          AppTokens.mutedForeground,
                    ),
                  ),
                ),
            ],
          ),
        ),
        DataCell(Text(
          rnc.isEmpty ? '—' : rnc,
          style: const TextStyle(fontSize: 13),
        )),
        DataCell(Text(
          doc.customerName ?? '—',
          style: const TextStyle(fontSize: 13),
          overflow: TextOverflow.ellipsis,
        )),
        DataCell(Text(
          fiscalPaymentLabel(doc),
          style: const TextStyle(fontSize: 13),
        )),
        DataCell(Text(
          formatDate(doc.issuedAt),
          style: const TextStyle(fontSize: 13),
        )),
        DataCell(Text(
          money(doc.totalAmount),
          style: const TextStyle(fontWeight: FontWeight.w700),
        )),
        DataCell(Text(money(doc.taxAmount))),
      ],
    );
  }

  void _showDetail(BuildContext context, FiscalDocument doc, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => _FiscalDocDetailDialog(doc: doc, listRef: ref),
    );
  }
}

// ─── Resumen ──────────────────────────────────────────────────────────────

/// "Resumen Facturas Consumo" en pantalla, con las mismas líneas que el
/// formulario de la DGII (y que el PDF/Excel).
class _SummaryView extends ConsumerWidget {
  const _SummaryView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(fiscalConsumoSummaryProvider);
    final hasRange = ref.watch(fiscalDateFromProvider) != null ||
        ref.watch(fiscalDateToProvider) != null;

    return DataTableShell(
      title: FiscalConsumoSummary.title,
      trailing: const _ViewToggle(),
      scrollable: false,
      child: summaryAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppTokens.s32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppTokens.s20),
          child: _LoadError(
            error: error,
            onRetry: () => ref.invalidate(fiscalConsumoSummaryProvider),
          ),
        ),
        data: (summary) => FiscalConsumoSummaryPanel(
          summary: summary,
          rangeNote: hasRange ? null : 'mes en curso',
        ),
      ),
    );
  }
}

class _FiscalDocDetailDialog extends ConsumerStatefulWidget {
  const _FiscalDocDetailDialog({required this.doc, required this.listRef});

  final FiscalDocument doc;
  final WidgetRef listRef;

  @override
  ConsumerState<_FiscalDocDetailDialog> createState() =>
      _FiscalDocDetailDialogState();
}

class _FiscalDocDetailDialogState
    extends ConsumerState<_FiscalDocDetailDialog> {
  bool _voiding = false;
  bool _emitting = false;
  bool _resolving = false;

  /// Re-dispara la emisión del e-CF (Edge Function `emit-document`). Útil
  /// cuando quedó pendiente (proveedor caído, empresa sin registrar) o para
  /// refrescar el estado tras corregir la causa de un rechazo.
  Future<void> _onEmit() async {
    setState(() => _emitting = true);
    try {
      final repo = ref.read(fiscalDocumentsRepositoryProvider);
      final updated = await repo.emitElectronicDocument(widget.doc.id);
      if (!mounted) return;
      widget.listRef.invalidate(fiscalDocumentsProvider);
      Navigator.of(context).pop();
      final status = updated?.ecfStatus;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == null
                ? 'Emisión disparada; el estado se actualizará en breve.'
                : 'Estado e-CF: ${_ecfStatusLabels[status] ?? status}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _emitting = false);
    }
  }

  /// Un envío incierto (migración 101) pudo llegar a Alanube: no se reenvía
  /// solo. Quien administra comprobantes lo busca en Alanube por su e-NCF y
  /// dice si está (con su id) o no (se reenvía con el mismo e-NCF).
  Future<void> _onResolveUncertain() async {
    final idController = TextEditingController();
    final noteController = TextEditingController();

    final found = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolver envío sin confirmar'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No se sabe si Alanube recibió el ${widget.doc.ncf}. Búscalo en '
                'el portal de Alanube por ese e-NCF antes de decidir: '
                'reenviarlo si ya está lo duplicaría ante la DGII.',
                style: const TextStyle(color: AppTokens.mutedForeground),
              ),
              const SizedBox(height: AppTokens.s12),
              TextField(
                controller: idController,
                decoration: const InputDecoration(
                  labelText: 'ID del documento en Alanube',
                  helperText: 'Solo si lo encontraste.',
                ),
              ),
              const SizedBox(height: AppTokens.s12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No está: reenviar'),
          ),
          FilledButton(
            onPressed: () {
              if (idController.text.trim().isEmpty) return;
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Sí está en Alanube'),
          ),
        ],
      ),
    );

    if (found == null || !mounted) return;
    final alanubeId = idController.text.trim();
    final note = noteController.text.trim();

    setState(() => _resolving = true);
    try {
      final repo = ref.read(fiscalDocumentsRepositoryProvider);
      await repo.resolveUncertainEmission(
        fiscalDocumentId: widget.doc.id,
        foundInAlanube: found,
        alanubeDocumentId: found ? alanubeId : null,
        note: note.isEmpty ? null : note,
      );
      // Confirmado que no está: se reenvía ya, no al próximo cron.
      if (!found) await repo.emitElectronicDocument(widget.doc.id);
      if (!mounted) return;
      widget.listRef.invalidate(fiscalDocumentsProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            found
                ? 'Comprobante conciliado con Alanube.'
                : 'Comprobante reenviado con el mismo e-NCF.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _resolving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo resolver: $error')),
      );
    }
  }

  Future<void> _onVoid() async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Anular comprobante'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Esta acción es irreversible. El NCF ${widget.doc.ncf} quedará marcado como anulado.',
                style: const TextStyle(color: AppTokens.mutedForeground),
              ),
              const SizedBox(height: AppTokens.s12),
              TextField(
                controller: reasonController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Razón de anulación *',
                  hintText: 'Ej: Error en monto, duplicado, etc.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTokens.destructive,
            ),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.of(context).pop(true);
            },
            child: const Text('Anular'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final reason = reasonController.text.trim();
    if (reason.isEmpty) return;

    setState(() => _voiding = true);
    try {
      final repo = ref.read(fiscalDocumentsRepositoryProvider);
      await repo.voidDocument(id: widget.doc.id, reason: reason);
      if (!mounted) return;
      widget.listRef.invalidate(fiscalDocumentsProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comprobante anulado.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _voiding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo anular: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final statusColor = doc.isCancelled
        ? AppTokens.destructive
        : _statusColors[doc.fiscalStatus] ?? AppTokens.mutedForeground;
    final statusLabel = fiscalStatusLabel(doc);
    final receiptLabel = fiscalReceiptLabel(doc.receiptType);
    final access = ref.watch(roleAccessProvider);
    // Incierto: podría existir ante la DGII; la base tampoco deja anularlo.
    final canVoid = !doc.isVoided &&
        doc.fiscalStatus != 'voided' &&
        doc.ecfStatus != 'uncertain' &&
        access.canVoidSale;
    final canResolve = doc.isElectronic &&
        !doc.isVoided &&
        doc.ecfStatus == 'uncertain' &&
        ref.watch(canManageNcfProvider);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 20),
          const SizedBox(width: AppTokens.s8),
          Expanded(
            child: Text(
              doc.ncf,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s8,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTokens.radiusS),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailSection(
                title: 'Comprobante',
                rows: [
                  _DetailRow('Tipo', receiptLabel),
                  _DetailRow('NCF', doc.ncf),
                  if (doc.sequenceNumber != null)
                    _DetailRow('Secuencia #', doc.sequenceNumber.toString()),
                  _DetailRow('Emisión', formatDateTime(doc.issuedAt)),
                  if (doc.saleStatus != null)
                    _DetailRow('Método de pago', fiscalPaymentLabel(doc)),
                  if (doc.expiresOn != null)
                    _DetailRow('Vence', formatDate(doc.expiresOn)),
                  if (doc.isVoided) ...[
                    _DetailRow('Anulado', formatDateTime(doc.voidedAt)),
                    if (doc.voidReason != null)
                      _DetailRow('Razón anulación', doc.voidReason!),
                  ],
                ],
              ),
              if (doc.customerName != null ||
                  doc.customerDocumentNumber != null) ...[
                const SizedBox(height: AppTokens.s16),
                _DetailSection(
                  title: 'Cliente',
                  rows: [
                    if (doc.customerName != null)
                      _DetailRow('Nombre', doc.customerName!),
                    if (doc.customerDocumentType != null &&
                        doc.customerDocumentNumber != null)
                      _DetailRow(
                        doc.customerDocumentType!.toUpperCase(),
                        doc.customerDocumentNumber!,
                      ),
                    if (doc.customerAddress != null)
                      _DetailRow('Dirección', doc.customerAddress!),
                  ],
                ),
              ],
              if (doc.issuerName != null) ...[
                const SizedBox(height: AppTokens.s16),
                _DetailSection(
                  title: 'Emisor',
                  rows: [
                    if (doc.issuerName != null)
                      _DetailRow('Nombre', doc.issuerName!),
                    if (doc.issuerTaxId != null)
                      _DetailRow('RNC', doc.issuerTaxId!),
                    if (doc.issuerAddress != null)
                      _DetailRow('Dirección', doc.issuerAddress!),
                  ],
                ),
              ],
              if (doc.isElectronic) ...[
                const SizedBox(height: AppTokens.s16),
                _DetailSection(
                  title: 'Facturación electrónica (DGII)',
                  rows: [
                    _DetailRow(
                      'Estado',
                      _ecfStatusLabels[doc.ecfStatus] ??
                          doc.ecfStatus ??
                          'Sin emitir',
                    ),
                    if (doc.ecfTrackingNumber != null)
                      _DetailRow('Track ID', doc.ecfTrackingNumber!),
                    if (doc.ecfSecurityCode != null)
                      _DetailRow('Código seguridad', doc.ecfSecurityCode!),
                    if (doc.ecfSignedAt != null)
                      _DetailRow(
                        'Firma digital',
                        formatDateTime(doc.ecfSignedAt),
                      ),
                    if (doc.submittedAt != null)
                      _DetailRow('Enviado', formatDateTime(doc.submittedAt)),
                    if (doc.acceptedAt != null)
                      _DetailRow('Aceptado', formatDateTime(doc.acceptedAt)),
                    if (doc.lastError != null && doc.lastError!.isNotEmpty)
                      _DetailRow('Último error', doc.lastError!),
                  ],
                ),
              ],
              const SizedBox(height: AppTokens.s16),
              _DetailSection(
                title: 'Montos',
                rows: [
                  _DetailRow('Subtotal', money(doc.subtotal)),
                  if (doc.discountAmount > 0)
                    _DetailRow('Descuento', money(doc.discountAmount)),
                  if (doc.taxableAmount > 0)
                    _DetailRow('Monto gravable', money(doc.taxableAmount)),
                  if (doc.exemptAmount > 0)
                    _DetailRow('Exento', money(doc.exemptAmount)),
                  _DetailRow('ITBIS', money(doc.taxAmount)),
                  if (doc.serviceChargeAmount > 0)
                    _DetailRow('Serv./Ley', money(doc.serviceChargeAmount)),
                  _DetailRow('Total', money(doc.totalAmount), bold: true),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (doc.isElectronic &&
            !doc.isVoided &&
            (doc.ecfStatus == 'pending' || doc.ecfStatus == 'rejected'))
          TextButton.icon(
            onPressed: _emitting ? null : _onEmit,
            icon: _emitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined, size: 16),
            label: const Text('Emitir a DGII'),
          ),
        if (canResolve)
          TextButton.icon(
            onPressed: _resolving ? null : _onResolveUncertain,
            icon: _resolving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.help_outline, size: 16),
            label: const Text('Resolver envío'),
          ),
        if (canVoid)
          TextButton.icon(
            onPressed: _voiding ? null : _onVoid,
            icon: _voiding
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.block_outlined, size: 16),
            label: const Text('Anular'),
            style: TextButton.styleFrom(foregroundColor: AppTokens.destructive),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.rows});

  final String title;
  final List<_DetailRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTokens.mutedForeground,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppTokens.s8),
        Container(
          decoration: BoxDecoration(
            color: AppTokens.card,
            borderRadius: BorderRadius.circular(AppTokens.radiusS),
            border: Border.all(color: AppTokens.border),
          ),
          child: Column(
            children: rows.map((row) => row.build(context)).toList(),
          ),
        ),
      ],
    );
  }
}

class _DetailRow {
  const _DetailRow(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s12,
        vertical: AppTokens.s8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTokens.mutedForeground,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
