import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/theme/tokens.dart';
import '../../features/printing/data/account_statement.dart';
import '../../features/printing/data/account_statement_pdf_builder.dart';
import '../formatters/formatters.dart';
import 'date_range_filter_button.dart';

/// Estado de cuenta de un cliente o proveedor. Lo carga con el rango de
/// fechas elegido, muestra el resumen y deja imprimirlo o bajarlo en PDF
/// para mandárselo (en el celular abre Compartir: WhatsApp, correo...).
class AccountStatementDialog extends StatefulWidget {
  const AccountStatementDialog({
    super.key,
    required this.partyName,
    required this.load,
    this.initialRange,
  });

  final String partyName;

  /// Arma el estado de cuenta para el rango (null = todas las pendientes).
  final Future<AccountStatement> Function(DateTimeRange? range) load;
  final DateTimeRange? initialRange;

  @override
  State<AccountStatementDialog> createState() => _AccountStatementDialogState();
}

class _AccountStatementDialogState extends State<AccountStatementDialog> {
  late DateTimeRange? _range = widget.initialRange;
  late Future<AccountStatement> _future = widget.load(_range);

  /// En Android/iOS `sharePdf` abre el menú de compartir; en web y escritorio
  /// descarga el archivo.
  bool get _shares =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  void _setRange(DateTimeRange? range) => setState(() {
        _range = range;
        _future = widget.load(range);
      });

  String _fileName(AccountStatement s) {
    final slug = s.party.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final d = s.generatedAt;
    final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return 'estado-de-cuenta-${slug.isEmpty ? 'cliente' : slug}-$date';
  }

  /// El PDF se arma dentro de `onLayout` para que en web la ventana de
  /// impresión salga con el mismo clic.
  Future<void> _print(AccountStatement s) async {
    try {
      await Printing.layoutPdf(
        name: _fileName(s),
        onLayout: (_) => const AccountStatementPdfBuilder().buildStatement(s),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo imprimir: $error')),
      );
    }
  }

  Future<void> _download(AccountStatement s) async {
    try {
      final bytes = await const AccountStatementPdfBuilder().buildStatement(s);
      await Printing.sharePdf(bytes: bytes, filename: '${_fileName(s)}.pdf');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el PDF: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AccountStatement>(
      future: _future,
      builder: (context, snap) {
        final statement =
            snap.connectionState == ConnectionState.done ? snap.data : null;
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.request_page_outlined, color: AppTokens.primary),
              const SizedBox(width: AppTokens.s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Estado de cuenta'),
                    Text(
                      widget.partyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTokens.mutedForeground),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: DateRangeFilterButton(
                    range: _range,
                    helpText: 'Facturas desde – hasta',
                    onChanged: _setRange,
                  ),
                ),
                const SizedBox(height: AppTokens.s12),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppTokens.s24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snap.hasError)
                  Text(
                    'No se pudo cargar el estado de cuenta: ${snap.error}',
                    style: const TextStyle(color: AppTokens.destructive),
                  )
                else ...[
                  _SummaryLine(
                    'Facturas pendientes',
                    '${statement!.documents.length}',
                  ),
                  _SummaryLine('Total facturado', money(statement.totalAmount)),
                  _SummaryLine('Abonado', money(statement.totalPaid)),
                  _SummaryLine(
                    'Saldo pendiente',
                    money(statement.totalBalance),
                    emphasized: true,
                  ),
                  _SummaryLine(
                    'Vencido',
                    money(statement.overdueBalance),
                    danger: statement.overdueBalance > 0,
                  ),
                  if (statement.documents.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: AppTokens.s8),
                      child: Text(
                        'No hay facturas pendientes en esas fechas.',
                        style: TextStyle(color: AppTokens.mutedForeground),
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
            OutlinedButton.icon(
              onPressed: statement == null ? null : () => _download(statement),
              icon: Icon(
                _shares ? Icons.share_outlined : Icons.download_outlined,
                size: 18,
              ),
              label: Text(_shares ? 'Compartir PDF' : 'Descargar PDF'),
            ),
            FilledButton.icon(
              onPressed: statement == null ? null : () => _print(statement),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Imprimir'),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine(
    this.label,
    this.value, {
    this.emphasized = false,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool emphasized;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppTokens.mutedForeground),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w700,
              fontSize: emphasized ? 16 : 14,
              color: emphasized || danger ? AppTokens.destructive : null,
            ),
          ),
        ],
      ),
    );
  }
}
