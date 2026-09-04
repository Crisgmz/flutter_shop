import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../data/sales_history_repository.dart';
import '../data/sales_repository.dart';
import '../domain/sale_checkout_service.dart'
    show fromCents, grossCents, taxCents, toCents;
import '../../cash_register/presentation/cash_register_providers.dart';
import '../../cobros/presentation/cobros_providers.dart';
import 'sales_history_providers.dart';
import 'sales_providers.dart';

/// Línea editable del carrito (estado mutable mientras se edita la venta).
class _EditCartItem {
  _EditCartItem({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    required this.discountAmount,
    List<String> imeis = const <String>[],
  }) : imeis = List<String>.from(imeis);

  final SalesProduct product;
  double quantity;
  double unitPrice;

  /// Descuento de la línea en MONTO, el mismo criterio que usa el backend
  /// (`sale_items.discount_amount`). Trabajar en porcentaje aquí perdía plata:
  /// el porcentaje se reconstruía desde `line_subtotal`, que en productos con
  /// ITBIS incluido ya viene sin impuesto, así que el ITBIS se leía como
  /// descuento y el total caía solo con abrir y guardar.
  double discountAmount;

  /// Equipos serializados de la línea. Mientras no esté vacía, la cantidad
  /// queda atada a su tamaño: el RPC de edición devuelve estos IMEIs al
  /// inventario y solo los vuelve a sacar con los que reciba de vuelta.
  final List<String> imeis;

  bool get hasImeis => imeis.isNotEmpty;

  /// Quita un equipo de la línea y baja la cantidad en consecuencia.
  void removeImei(String imei) {
    if (!imeis.remove(imei)) return;
    quantity = imeis.length.toDouble();
  }

  /// Misma fórmula que el RPC (migraciones 76 y 77) y que
  /// `SaleCheckoutService.normalize`: bruto → descuento acotado → neto, y el
  /// ITBIS se agrega encima (exclusivo) o se extrae del neto (incluido). Si
  /// esta matemática se separa de la del SQL, la pantalla muestra un total y
  /// se guarda otro.
  // Toda la aritmética va en CENTAVOS ENTEROS con los helpers compartidos: es
  // lo único que reproduce el redondeo de `numeric` de Postgres. Con doubles,
  // 18.0/100 vale 0.17999… y el medio centavo cae para el lado contrario que
  // en el RPC, así que la pantalla mostraría un total y se guardaría otro.
  double get _grossCents => grossCents(quantity, unitPrice);

  double get _discountCents =>
      toCents(discountAmount).clamp(0, _grossCents).toDouble();

  double get _netCents => _grossCents - _discountCents;

  double get lineGross => fromCents(_grossCents);

  double get lineDiscount => fromCents(_discountCents);

  /// Tasa efectiva: un producto exento factura sin ITBIS aunque tenga tasa
  /// cargada, que es lo que hace el RPC (`case when is_tax_exempt then 0`).
  double get _rate => product.isTaxExempt ? 0 : product.taxRate;

  bool get _taxIncluded => product.priceIncludesTax && _rate > 0;

  double get _taxCents => taxCents(_netCents, _rate, inclusive: _taxIncluded);

  double get lineTax => fromCents(_taxCents);

  double get lineSubtotal =>
      fromCents(_taxIncluded ? _netCents - _taxCents : _netCents);

  double get lineTotal =>
      fromCents(_taxIncluded ? _netCents : _netCents + _taxCents);

  Map<String, dynamic> toRpcItem() => {
        'product_id': product.id,
        'description': product.name,
        'quantity': quantity,
        'unit_price': unitPrice,
        // MONTO, no porcentaje: es el criterio del backend desde la 77.
        'discount_amount': lineDiscount,
        // Sin esto el RPC deja los equipos liberados en el inventario tras la
        // edición y se le pueden vender a otro cliente.
        'imeis': List<String>.from(imeis),
      };
}

/// Una línea de cobro editable (monto + método), equivalente a las filas del
/// diálogo "Completar venta" del POS.
class _PayLine {
  _PayLine({required this.method, double amount = 0})
      : amount = TextEditingController(text: _fmtAmount(amount));

  String method;
  final TextEditingController amount;

  double get value =>
      double.tryParse(amount.text.trim().replaceAll(',', '')) ?? 0;

  void dispose() => amount.dispose();

  static String _fmtAmount(double v) {
    if (v <= 0) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  }
}

/// Métodos que se pueden cobrar. `credit` no está: lo que no cubran estas
/// líneas queda automáticamente como saldo pendiente, que es lo mismo pero
/// sin pedirle al usuario que cuadre dos veces el mismo número.
const List<MapEntry<String, String>> _payMethods = [
  MapEntry('cash', 'Efectivo'),
  MapEntry('transfer', 'Transferencia'),
  MapEntry('card', 'Tarjeta'),
  MapEntry('mobile', 'Pago móvil'),
  MapEntry('other', 'Otro'),
];

class SalesEditPage extends ConsumerStatefulWidget {
  const SalesEditPage({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<SalesEditPage> createState() => _SalesEditPageState();
}

class _SalesEditPageState extends ConsumerState<SalesEditPage> {
  /// Esta pantalla solo edita VENTAS; el historial unificado necesita saber
  /// que el detalle se busca en `sales` y no en `returns`.
  SalesHistoryDetailKey get _detailKey =>
      (id: widget.saleId, isReturn: false);

  final List<_EditCartItem> _items = [];
  final _notesCtrl = TextEditingController();
  String? _clientId;
  bool _initialized = false;
  bool _submitting = false;

  /// Cómo quedó cobrada la venta. Se hidrata con las filas reales de
  /// `payments` y se reescribe entera al guardar si el usuario la tocó.
  final List<_PayLine> _payLines = [];

  /// Mientras nadie toque la forma de cobro no se manda nada al backend: el
  /// RPC de edición ya ajusta solo el pago de una venta pagada cuando cambia
  /// el total, y así una venta con abonos no se pisa por abrir el editor.
  bool _paymentsTouched = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final line in _payLines) {
      line.dispose();
    }
    super.dispose();
  }

  /// Total ya cobrado según las líneas de pago.
  double get _paid =>
      _payLines.fold<double>(0, (s, l) => s + (l.value > 0 ? l.value : 0));

  /// Lo que queda debiendo: pasa a Cuentas por cobrar al guardar.
  double get _pending {
    final diff = _round2(_total - _paid);
    return diff > 0 ? diff : 0;
  }

  bool get _overpaid => _round2(_paid) > _round2(_total);

  void _addPayLine() => setState(() {
        _paymentsTouched = true;
        // La línea nueva arranca con lo que falta por cobrar: es el reparto
        // que el cajero quiere el 90% de las veces.
        _payLines.add(_PayLine(method: 'cash', amount: _pending));
      });

  void _removePayLine(int i) => setState(() {
        _paymentsTouched = true;
        _payLines.removeAt(i).dispose();
      });

  /// Deja la venta entera a crédito: sin líneas de cobro, todo el total queda
  /// pendiente. Es el caso que reportó el usuario (se facturó en efectivo por
  /// error y en realidad se fio).
  void _allOnCredit() => setState(() {
        _paymentsTouched = true;
        for (final line in _payLines) {
          line.dispose();
        }
        _payLines.clear();
      });

  /// Marca la venta como cobrada por completo en un solo método.
  void _markFullyPaid() => setState(() {
        _paymentsTouched = true;
        final method = _payLines.isEmpty ? 'cash' : _payLines.first.method;
        for (final line in _payLines) {
          line.dispose();
        }
        _payLines
          ..clear()
          ..add(_PayLine(method: method, amount: _total));
      });

  double get _subtotal =>
      _items.fold<double>(0, (s, it) => s + it.lineSubtotal);
  double get _discount =>
      _items.fold<double>(0, (s, it) => s + it.lineDiscount);
  double get _tax => _items.fold<double>(0, (s, it) => s + it.lineTax);
  double get _total => _subtotal + _tax;

  /// Carga inicial de los items de la venta en el estado local.
  void _hydrate(SalesHistoryDetail detail, List<SalesProduct> products) {
    if (_initialized) return;
    _initialized = true;

    final byId = {for (final p in products) p.id: p};
    for (final si in detail.items) {
      final pid = si.productId;
      if (pid == null) continue;
      final product = byId[pid];
      if (product == null) continue;
      // El descuento se toma tal cual está guardado en la línea. Antes se
      // reconstruía un porcentaje con (bruto − line_subtotal): en productos
      // con ITBIS incluido eso leía el impuesto como descuento y bajaba el
      // total con solo abrir y guardar.
      _items.add(_EditCartItem(
        product: product,
        quantity: si.quantity,
        unitPrice: si.unitPrice,
        discountAmount: si.discountAmount,
        imeis: si.imeis,
      ));
    }
    _clientId = detail.sale.clientId;
    _notesCtrl.text = detail.sale.notes ?? '';

    // Forma de cobro: una línea por cada fila real de `payments`. Una venta a
    // crédito no tiene ninguna, y así arranca con todo pendiente.
    for (final payment in detail.payments) {
      _payLines.add(
        _PayLine(
          method: _payMethods.any((m) => m.key == payment.method)
              ? payment.method
              : 'other',
          amount: payment.amount,
        ),
      );
    }
  }

  Future<void> _addProduct() async {
    final productsAsync = ref.read(salesProductsProvider);
    final products = productsAsync.valueOrNull ?? const [];
    final picked = await showDialog<SalesProduct>(
      context: context,
      builder: (_) => _ProductPickerDialog(products: products),
    );
    if (picked == null || !mounted) return;

    final existing = _items.indexWhere((it) => it.product.id == picked.id);
    // Línea con IMEIs: subir la cantidad dejaría unidades sin equipo asignado
    // (la invariante es cantidad == IMEIs). Los equipos se asignan en el POS.
    if (existing >= 0 && _items[existing].hasImeis) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esta línea lleva IMEIs: su cantidad la definen los equipos. '
            'Para agregar otro equipo, hazlo desde el POS.',
          ),
        ),
      );
      return;
    }
    setState(() {
      if (existing >= 0) {
        _items[existing].quantity += 1;
      } else {
        _items.add(_EditCartItem(
          product: picked,
          quantity: 1,
          unitPrice: picked.price,
          discountAmount: 0,
        ));
      }
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La venta debe tener al menos un item.'),
        ),
      );
      return;
    }

    // La cantidad de una línea serializada la mandan sus IMEIs. Si sobran
    // equipos respecto de la cantidad, el RPC sacaría del inventario más de
    // lo vendido; si faltan, quedarían liberados y vendibles a otro cliente.
    for (final it in _items) {
      if (it.imeis.length != it.quantity && it.hasImeis) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${it.product.name}": ${it.imeis.length} IMEI(s) para '
              '${it.quantity.toStringAsFixed(0)} unidad(es). La cantidad debe '
              'coincidir con los equipos de la línea.',
            ),
          ),
        );
        return;
      }
    }

    // Cobrar de más no tiene forma de guardarse: el vuelto se maneja en el
    // POS al facturar, no corrigiendo una venta ya hecha.
    if (_overpaid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Los pagos (${money(_paid)}) superan el total de la venta '
            '(${money(_total)}).',
          ),
        ),
      );
      return;
    }

    // Un saldo pendiente hay que poder cobrárselo a alguien.
    if (_paymentsTouched && _pending > 0 && _clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Una venta con saldo pendiente necesita un cliente. Selecciona el '
            'cliente o cobra el total.',
          ),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final repo = ref.read(salesHistoryRepositoryProvider);
      final result = await repo.editSale(
        saleId: widget.saleId,
        items: _items.map((it) => it.toRpcItem()).toList(),
        clientId: _clientId,
        clearClient: _clientId == null,
        notes: _notesCtrl.text,
        clearNotes: _notesCtrl.text.trim().isEmpty,
      );

      // La forma de cobro va en una segunda llamada: `editSale` recalcula
      // items y totales, pero no sabe nada de cómo se cobró. Este RPC reescribe
      // los pagos y con ellos el estado, el balance y el saldo del cliente —
      // por eso una venta que pasa a crédito ahora sí cae en Cuentas por cobrar.
      SalePaymentsResult? paymentsResult;
      if (_paymentsTouched) {
        paymentsResult = await repo.setSalePayments(
          saleId: widget.saleId,
          payments: [
            for (final line in _payLines)
              if (line.value > 0)
                SalePaymentLine(method: line.method, amount: line.value),
          ],
        );
      }
      if (!mounted) return;
      ref.invalidate(salesHistoryPageProvider);
      ref.invalidate(salesHistoryDetailProvider(_detailKey));
      ref.invalidate(salesProductsProvider);
      // El saldo cambió: Cuentas por cobrar y la caja tienen que releer.
      if (_paymentsTouched) {
        ref.invalidate(cobrosReceivablesProvider);
        ref.invalidate(cobrosPaymentsProvider);
        ref.invalidate(cashRegisterDataProvider);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTokens.success,
          content: Text(
            paymentsResult != null && paymentsResult.isCredit
                ? 'Venta actualizada · Total ${money(result.totalAmount)} · '
                    'Pendiente ${money(paymentsResult.balanceDue)} en Cuentas '
                    'por cobrar'
                : 'Venta actualizada · Total ${money(result.totalAmount)}',
            style: const TextStyle(color: AppTokens.successForeground),
          ),
        ),
      );
      context.go('/ventas/historial');
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, 'No se pudo guardar', e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(salesHistoryDetailProvider(_detailKey));
    final productsAsync = ref.watch(salesProductsProvider);
    final clientsAsync = ref.watch(salesClientsProvider);

    return ModulePage(
      title: 'Editar venta',
      description: 'Modifica items, precios, descuentos, cliente y notas.',
      actions: [
        OutlinedButton.icon(
          onPressed: _submitting ? null : () => context.pop(),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _save,
          icon: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 18),
          label: Text(_submitting ? 'Guardando…' : 'Guardar cambios'),
        ),
      ],
      child: detailAsync.when(
        loading: () =>
            const Center(child: Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(),
            )),
        error: (e, _) => ErrorCard(
          message: 'No se pudo cargar la venta: $e',
          onRetry: () => ref.invalidate(salesHistoryDetailProvider(_detailKey)),
        ),
        data: (detail) {
          if (detail == null) {
            return const _SaleNotFound();
          }
          return productsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => ErrorCard(
              message: 'No se pudieron cargar productos: $e',
              onRetry: () => ref.invalidate(salesProductsProvider),
            ),
            data: (products) {
              _hydrate(detail, products);
              return _EditForm(
                detail: detail,
                items: _items,
                clientId: _clientId,
                notesCtrl: _notesCtrl,
                payLines: _payLines,
                paid: _paid,
                pending: _pending,
                clientsAsync: clientsAsync,
                subtotal: _subtotal,
                discount: _discount,
                tax: _tax,
                total: _total,
                onClientChanged: (v) => setState(() => _clientId = v),
                onAddPayLine: _addPayLine,
                onRemovePayLine: _removePayLine,
                onPaymentsChanged: () => setState(() {
                  _paymentsTouched = true;
                }),
                onAllOnCredit: _allOnCredit,
                onFullyPaid: _markFullyPaid,
                onAddProduct: _addProduct,
                onRemoveItem: (i) => setState(() => _items.removeAt(i)),
                onItemChanged: () => setState(() {}),
              );
            },
          );
        },
      ),
    );
  }
}

class _SaleNotFound extends StatelessWidget {
  const _SaleNotFound();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off,
              size: 48,
              color: AppTokens.mutedForeground,
            ),
            const SizedBox(height: 12),
            const Text('Venta no encontrada.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/ventas/historial'),
              child: const Text('Volver al historial'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditForm extends StatelessWidget {
  const _EditForm({
    required this.detail,
    required this.items,
    required this.clientId,
    required this.notesCtrl,
    required this.payLines,
    required this.paid,
    required this.pending,
    required this.clientsAsync,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.onClientChanged,
    required this.onAddPayLine,
    required this.onRemovePayLine,
    required this.onPaymentsChanged,
    required this.onAllOnCredit,
    required this.onFullyPaid,
    required this.onAddProduct,
    required this.onRemoveItem,
    required this.onItemChanged,
  });

  final SalesHistoryDetail detail;
  final List<_EditCartItem> items;
  final String? clientId;
  final TextEditingController notesCtrl;

  /// Líneas de cobro (pago mixto). Vacío = la venta queda entera a crédito.
  final List<_PayLine> payLines;

  final double paid;
  final double pending;
  final AsyncValue<List<SalesClient>> clientsAsync;
  final double subtotal;

  /// Suma de los descuentos de línea. El subtotal ya viene neto, así que el
  /// resumen muestra el BRUTO arriba y esta fila debajo para que
  /// subtotal bruto − descuento + ITBIS = total.
  final double discount;

  final double tax;
  final double total;
  final ValueChanged<String?> onClientChanged;
  final VoidCallback onAddPayLine;
  final ValueChanged<int> onRemovePayLine;
  final VoidCallback onPaymentsChanged;
  final VoidCallback onAllOnCredit;
  final VoidCallback onFullyPaid;
  final VoidCallback onAddProduct;
  final ValueChanged<int> onRemoveItem;
  final VoidCallback onItemChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(detail: detail),
        const SizedBox(height: AppTokens.s16),
        _ClientSelector(
          clientId: clientId,
          clientsAsync: clientsAsync,
          onChanged: onClientChanged,
        ),
        const SizedBox(height: AppTokens.s16),
        _PaymentLinesCard(
          lines: payLines,
          total: total,
          paid: paid,
          pending: pending,
          onAdd: onAddPayLine,
          onRemove: onRemovePayLine,
          onChanged: onPaymentsChanged,
          onAllOnCredit: onAllOnCredit,
          onFullyPaid: onFullyPaid,
        ),
        const SizedBox(height: AppTokens.s16),
        Row(
          children: [
            const Text(
              'Items',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onAddProduct,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Agregar producto'),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.s8),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppTokens.s20),
            decoration: BoxDecoration(
              border: Border.all(color: AppTokens.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'La venta no tiene items. Agrega al menos uno antes de guardar.',
              style: TextStyle(color: AppTokens.mutedForeground),
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < items.length; i++)
                _EditableLineTile(
                  key: ValueKey('${items[i].product.id}-$i'),
                  item: items[i],
                  onRemove: () => onRemoveItem(i),
                  onChanged: onItemChanged,
                ),
            ],
          ),
        const SizedBox(height: AppTokens.s16),
        TextField(
          controller: notesCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Notas',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppTokens.s16),
        _Totals(
          subtotal: subtotal,
          discount: discount,
          tax: tax,
          total: total,
          // En ventas PAGADAS el pago sigue al total (queda saldada), igual
          // que hace el RPC al guardar. En crédito se conserva lo pagado y el
          // pendiente se recalcula contra el nuevo total.
          paid: detail.sale.status == 'completed'
              ? total
              : detail.sale.paidAmount,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail});

  final SalesHistoryDetail detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTokens.border),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 6,
        children: [
          _KV('Número', detail.sale.saleNumber),
          _KV('Fecha', formatDateTime(detail.sale.saleDate)),
          if (detail.sale.ncf != null) _KV('NCF', detail.sale.ncf!),
          _KV('Estado', _statusLabel(detail.sale.status)),
          _KV('Pagado', money(detail.sale.paidAmount)),
        ],
      ),
    );
  }

  static String _statusLabel(String s) {
    switch (s) {
      case 'completed':
        return 'Pagada';
      case 'credit':
        return 'Crédito';
      case 'pending':
        return 'Pendiente';
      default:
        return s;
    }
  }
}

class _KV extends StatelessWidget {
  const _KV(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$k: ',
          style: const TextStyle(
            fontSize: 12,
            color: AppTokens.mutedForeground,
          ),
        ),
        Text(
          v,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ClientSelector extends StatelessWidget {
  const _ClientSelector({
    required this.clientId,
    required this.clientsAsync,
    required this.onChanged,
  });

  final String? clientId;
  final AsyncValue<List<SalesClient>> clientsAsync;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return clientsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Error al cargar clientes: $e'),
      data: (clients) => DropdownButtonFormField<String?>(
        initialValue: clientId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Cliente',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(
            value: null,
            child: Text('Cliente General'),
          ),
          ...clients.map(
            (c) => DropdownMenuItem(
              value: c.id,
              child: Text(c.fullName),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _EditableLineTile extends StatefulWidget {
  const _EditableLineTile({
    super.key,
    required this.item,
    required this.onRemove,
    required this.onChanged,
  });

  final _EditCartItem item;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  State<_EditableLineTile> createState() => _EditableLineTileState();
}

class _EditableLineTileState extends State<_EditableLineTile> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _discCtrl;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: _fmt(widget.item.quantity));
    _priceCtrl = TextEditingController(text: _fmt(widget.item.unitPrice));
    _discCtrl = TextEditingController(text: _fmt(widget.item.discountAmount));
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _discCtrl.dispose();
    super.dispose();
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  void _commitQty(String v) {
    // Línea con IMEIs: la cantidad la mandan los equipos, no el teclado. Se
    // baja quitando chips; el campo vuelve a su valor real.
    if (widget.item.hasImeis) {
      _qtyCtrl.text = _fmt(widget.item.quantity);
      return;
    }
    final n = double.tryParse(v) ?? widget.item.quantity;
    widget.item.quantity = n.clamp(0.001, 999999).toDouble();
    widget.onChanged();
  }

  void _removeImei(String imei) {
    // Quitar el último equipo dejaría la línea en cantidad 0: eso es borrar
    // la línea completa.
    if (widget.item.imeis.length <= 1) {
      widget.onRemove();
      return;
    }
    setState(() => widget.item.removeImei(imei));
    _qtyCtrl.text = _fmt(widget.item.quantity);
    widget.onChanged();
  }

  void _commitPrice(String v) {
    final n = double.tryParse(v) ?? widget.item.unitPrice;
    widget.item.unitPrice = n.clamp(0, 9999999).toDouble();
    widget.onChanged();
  }

  /// Descuento en MONTO. Se acota al bruto de la línea (precio × cantidad):
  /// más que eso dejaría el total en negativo y el backend lo recortaría
  /// igual, así que el campo muestra desde ya lo que se va a guardar.
  void _commitDisc(String v) {
    final n = double.tryParse(v) ?? widget.item.discountAmount;
    widget.item.discountAmount = n.clamp(0, widget.item.lineGross).toDouble();
    _discCtrl.text = _fmt(widget.item.discountAmount);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  widget.item.product.tracksStock
                      ? 'Stock: ${_fmt(widget.item.product.stock)}'
                      : 'Servicio',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTokens.mutedForeground,
                  ),
                ),
                // Equipos de la línea: el supervisor ve qué está editando y
                // puede sacar uno (la cantidad baja con él).
                if (widget.item.hasImeis)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final imei in widget.item.imeis)
                          InkWell(
                            onTap: () => _removeImei(imei),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'IMEI $imei',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.close_rounded,
                                    size: 11,
                                    color: Color(0xFF2563EB),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniField(
              label: 'Cant.',
              controller: _qtyCtrl,
              onSubmit: _commitQty,
              // Con IMEIs la cantidad no se teclea: sale de los equipos.
              readOnly: widget.item.hasImeis,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _MiniField(
              label: 'Precio',
              controller: _priceCtrl,
              suffix: r'$',
              onSubmit: _commitPrice,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _MiniField(
              label: 'Desc',
              controller: _discCtrl,
              suffix: r'$',
              onSubmit: _commitDisc,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTokens.mutedForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  money(widget.item.lineTotal),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: widget.onRemove,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: Color(0xFFF87171),
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _MiniField extends StatefulWidget {
  const _MiniField({
    required this.label,
    required this.controller,
    required this.onSubmit,
    this.suffix,
    this.readOnly = false,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final String? suffix;

  /// Solo lectura: el valor lo calcula otra cosa (ej. cantidad por IMEIs).
  final bool readOnly;

  @override
  State<_MiniField> createState() => _MiniFieldState();
}

class _MiniFieldState extends State<_MiniField> {
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (!_focus.hasFocus) widget.onSubmit(widget.controller.text);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 10,
            color: AppTokens.mutedForeground,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          readOnly: widget.readOnly,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          onSubmitted: widget.onSubmit,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            suffixText: widget.suffix,
            suffixStyle: const TextStyle(
              fontSize: 11,
              color: AppTokens.mutedForeground,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            filled: true,
            fillColor: widget.readOnly
                ? const Color(0xFFF1F5F9)
                : Colors.white,
          ),
        ),
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.paid,
  });

  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double paid;

  @override
  Widget build(BuildContext context) {
    final balance = (total - paid).clamp(0, double.infinity);
    // El subtotal calculado ya viene NETO de descuento. Para que el resumen
    // cuadre a la vista (bruto − descuento + ITBIS = total) se muestra el
    // bruto y el descuento aparte, igual que en el recibo impreso.
    final grossSubtotal = subtotal + discount;
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row('Subtotal', money(grossSubtotal)),
            if (discount > 0) _row('Descuento', '-${money(discount)}'),
            _row('ITBIS', money(tax)),
            const Divider(),
            _row('Total', money(total), bold: true),
            const SizedBox(height: 8),
            _row('Pagado', money(paid)),
            if (balance > 0)
              _row('Pendiente', money(balance.toDouble()),
                  bold: true, danger: true),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 14 : 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: AppTokens.mutedForeground,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: danger
                  ? AppTokens.destructive
                  : (bold
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Dialogo para elegir un producto a agregar
// ─────────────────────────────────────────────────────────────────────────

class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({required this.products});

  final List<SalesProduct> products;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = widget.products.where((p) {
      if (q.isEmpty) return p.isActive;
      if (!p.isActive) return false;
      return p.name.toLowerCase().contains(q) ||
          (p.sku ?? '').toLowerCase().contains(q) ||
          (p.barcode ?? '').toLowerCase().contains(q);
    }).take(50).toList(growable: false);

    return AlertDialog(
      title: const Text('Agregar producto'),
      content: SizedBox(
        width: 480,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Buscar por nombre, SKU o código de barras',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              inputFormatters: [
                LengthLimitingTextInputFormatter(60),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'Sin coincidencias.',
                        style:
                            TextStyle(color: AppTokens.mutedForeground),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        return ListTile(
                          dense: true,
                          title: Text(p.name),
                          subtitle: Text(
                            p.tracksStock
                                ? 'Precio: ${money(p.price)} · Stock: ${p.stock}'
                                : 'Precio: ${money(p.price)} · Servicio',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(Icons.add_circle_outline,
                              size: 18),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

double _round2(double value) => (value * 100).roundToDouble() / 100;

/// Editor de la forma de cobro: una fila por método, igual que el diálogo
/// "Completar venta" del POS. La diferencia es que acá lo que no se cobra no
/// es vuelto sino saldo pendiente, y eso es lo que manda la venta a Cuentas
/// por cobrar.
class _PaymentLinesCard extends StatelessWidget {
  const _PaymentLinesCard({
    required this.lines,
    required this.total,
    required this.paid,
    required this.pending,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
    required this.onAllOnCredit,
    required this.onFullyPaid,
  });

  final List<_PayLine> lines;
  final double total;
  final double paid;
  final double pending;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final VoidCallback onChanged;
  final VoidCallback onAllOnCredit;
  final VoidCallback onFullyPaid;

  @override
  Widget build(BuildContext context) {
    final overpaid = _round2(paid) > _round2(total);

    return Container(
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTokens.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Forma de cobro',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onFullyPaid,
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Cobrada completa'),
              ),
              TextButton.icon(
                onPressed: onAllOnCredit,
                icon: const Icon(Icons.schedule, size: 16),
                label: const Text('Todo a crédito'),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s8),
          if (lines.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppTokens.s12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Sin cobros registrados: la venta queda completa a crédito y '
                'pasa a Cuentas por cobrar.',
                style: TextStyle(fontSize: 12),
              ),
            )
          else
            for (var i = 0; i < lines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.s8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: TextField(
                        controller: lines[i].amount,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Monto',
                          isDense: true,
                          border: OutlineInputBorder(),
                          prefixText: 'RD\$ ',
                        ),
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                    const SizedBox(width: AppTokens.s8),
                    Expanded(
                      flex: 4,
                      child: DropdownButtonFormField<String>(
                        initialValue: lines[i].method,
                        decoration: const InputDecoration(
                          labelText: 'Método',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final m in _payMethods)
                            DropdownMenuItem(
                              value: m.key,
                              child: Text(m.value),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          lines[i].method = v;
                          onChanged();
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Quitar método',
                      onPressed: () => onRemove(i),
                      icon: const Icon(Icons.close, size: 18),
                      color: AppTokens.error,
                    ),
                  ],
                ),
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Agregar método de pago'),
            ),
          ),
          const Divider(height: AppTokens.s20),
          _PayKV('Total de la venta', money(total)),
          _PayKV('Cobrado', money(paid)),
          if (overpaid)
            _PayKV(
              'Sobra',
              money(_round2(paid - total)),
              color: AppTokens.error,
              bold: true,
            )
          else if (pending > 0)
            _PayKV(
              'Pendiente (a crédito)',
              money(pending),
              color: AppTokens.warning,
              bold: true,
            ),
        ],
      ),
    );
  }
}

class _PayKV extends StatelessWidget {
  const _PayKV(this.label, this.value, {this.color, this.bold = false});

  final String label;
  final String value;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      color: color,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color ?? AppTokens.mutedForeground,
            ),
          ),
          Text(value, style: style),
        ],
      ),
    );
  }
}
