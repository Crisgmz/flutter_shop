import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/ncf_stock_banner.dart';
import '../../../shared/widgets/print_receipt_dialog.dart';
import '../../../shared/widgets/role_gate.dart';
import '../../settings/presentation/app_settings_providers.dart';
import '../data/sales_repository.dart';
import 'sales_providers.dart';

class SalesPage extends ConsumerStatefulWidget {
  const SalesPage({super.key});

  @override
  ConsumerState<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends ConsumerState<SalesPage> {
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();
  final _saleNumberController = TextEditingController();

  final List<SaleCartItem> _cart = [];

  bool _isSubmitting = false;
  bool _showCart = false;
  String _receiptType = 'consumer_final';
  // El usuario debe elegir explícitamente entre Efectivo / Tarjeta /
  // Transferencia antes de poder presionar COMPLETAR VENTA.
  String? _paymentMethod;
  String? _clientId;

  int get _cartLines => _cart.length;
  double get _cartSubtotal => _cart.fold<double>(0, (sum, item) => sum + item.lineSubtotal);
  double get _cartTax => _cart.fold<double>(0, (sum, item) => sum + item.lineTax);
  double get _cartTotal => _cartSubtotal + _cartTax;

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    _saleNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(salesProductsProvider);
    final categoriesAsync = ref.watch(salesCategoriesProvider);
    final clientsAsync = ref.watch(salesClientsProvider);
    final query = ref.watch(salesSearchProvider).trim().toLowerCase();
    final selectedCategoryId = ref.watch(salesSelectedCategoryProvider);
    final posMode = ref.watch(posModeProvider);
    final isMobile = ResponsiveLayout.isMobile(context);
    final padding = adaptivePadding(context);

    if (isMobile && _showCart) {
      return Scaffold(
        appBar: AppBar(
          title: Text(posMode == PosMode.sale
              ? 'Carrito de Venta'
              : 'Carrito de Devolución'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _showCart = false),
          ),
        ),
        body: _buildCartPanel(clientsAsync),
      );
    }

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Punto de Venta',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    posMode == PosMode.sale
                        ? 'Registrar nueva venta'
                        : 'Registrar devolución',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              if (isMobile && _cartLines > 0)
                Badge(
                  label: Text('$_cartLines'),
                  child: IconButton(
                    icon: const Icon(Icons.shopping_cart_outlined),
                    onPressed: () => setState(() => _showCart = true),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTokens.s12),
          const NcfStockBanner(),
          Row(
            children: [
              _PosModeToggle(
                mode: posMode,
                onChange: _changePosMode,
              ),
              const Spacer(),
              if (posMode == PosMode.returnMode)
                TextButton.icon(
                  onPressed: () => context.push('/devoluciones'),
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text('Historial'),
                ),
            ],
          ),
          const SizedBox(height: AppTokens.s20),
          
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      _buildSearchBar(categoriesAsync, selectedCategoryId),
                      const SizedBox(height: AppTokens.s12),
                      Expanded(
                        child: _buildProductGrid(
                          productsAsync,
                          query,
                          selectedCategoryId,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isMobile) const SizedBox(width: AppTokens.s24),
                if (!isMobile)
                  Expanded(
                    flex: 3,
                    child: _buildCartPanel(clientsAsync),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(AsyncValue<List<SalesCategory>> categoriesAsync, String? selectedCategoryId) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTokens.radius),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 20),
                const SizedBox(width: AppTokens.s12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => ref.read(salesSearchProvider.notifier).state = v,
                    decoration: const InputDecoration(
                      hintText: 'Buscar producto...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppTokens.s10),
        categoriesAsync.when(
          data: (categories) => Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: selectedCategoryId,
                hint: const Text('Categoría', style: TextStyle(fontSize: 13)),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todas')),
                  ...categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                ],
                onChanged: (v) => ref.read(salesSelectedCategoryProvider.notifier).state = v,
              ),
            ),
          ),
          loading: () => const SizedBox(width: 48, height: 48, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          error: (_, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildProductGrid(
    AsyncValue<List<SalesProduct>> productsAsync,
    String query,
    String? selectedCategoryId,
  ) {
    return productsAsync.when(
      data: (products) {
        final filtered = _filterProducts(products, query: query, selectedCategoryId: selectedCategoryId);
        if (filtered.isEmpty) return const Center(child: Text('No hay productos.'));

        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 165).floor().clamp(2, 8);
            return GridView.builder(
              padding: const EdgeInsets.only(bottom: 20),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) => _ProductCard(
                product: filtered[index],
                onTap: () => _addProductToCart(filtered[index]),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildCartPanel(AsyncValue<List<SalesClient>> clientsAsync) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppTokens.s16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Carrito ($_cartLines)',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _receiptType,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                          items: const [
                            DropdownMenuItem(
                              value: 'consumer_final',
                              child: Text('Consumidor Final (B02)'),
                            ),
                            DropdownMenuItem(
                              value: 'fiscal_credit',
                              child: Text('Crédito Fiscal (B01)'),
                            ),
                            DropdownMenuItem(
                              value: 'governmental',
                              child: Text('Gubernamental (B15)'),
                            ),
                            DropdownMenuItem(
                              value: 'special',
                              child: Text('Régimen Especial (B14)'),
                            ),
                            DropdownMenuItem(
                              value: 'export',
                              child: Text('Exportación (B16)'),
                            ),
                          ],
                          onChanged: (v) => setState(() => _receiptType = v!),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                clientsAsync.when(
                  data: (clients) => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _clientId,
                        hint: const Text('Seleccionar Cliente', style: TextStyle(fontSize: 13)),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Cliente General (Contado)')),
                          ...clients.map((c) => DropdownMenuItem(value: c.id, child: Text(c.fullName))),
                        ],
                        onChanged: _onClientChanged,
                      ),
                    ),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text('Error al cargar clientes'),
                ),
                if (ref.watch(posModeProvider) == PosMode.returnMode) ...[
                  const SizedBox(height: 12),
                  _SaleNumberSearch(
                    controller: _saleNumberController,
                    isLoading: _isSubmitting,
                    onSearch: _loadSaleIntoReturn,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _cart.isEmpty
                ? const Center(child: Text('Carrito vacío', style: TextStyle(color: Color(0xFF94A3B8))))
                : ListView.builder(
                    padding: const EdgeInsets.all(AppTokens.s12),
                    itemCount: _cart.length,
                    itemBuilder: (context, i) => _CartLineTile(
                      item: _cart[i],
                      onDecrease: () => _changeQty(i, -1),
                      onIncrease: () => _changeQty(i, 1),
                      onRemove: () => _removeItem(i),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s16, vertical: 8),
            child: TextField(
              controller: _notesController,
              decoration: InputDecoration(
                hintText: 'Notas de venta...',
                hintStyle: const TextStyle(fontSize: 12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppTokens.s20),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              children: [
                _totalLine('Subtotal', money(_cartSubtotal)),
                const SizedBox(height: 4),
                _totalLine('ITBIS (18%)', money(_cartTax)),
                const SizedBox(height: 12),
                Builder(builder: (context) {
                  final isReturn =
                      ref.watch(posModeProvider) == PosMode.returnMode;
                  final totalColor = isReturn
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF2563EB);
                  final totalLabel = isReturn
                      ? '- ${money(_cartTotal)}'
                      : money(_cartTotal);
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                      Text(totalLabel,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: totalColor)),
                    ],
                  );
                }),
                const SizedBox(height: 20),
                Builder(builder: (context) {
                  final isReturn =
                      ref.watch(posModeProvider) == PosMode.returnMode;
                  return Column(
                    children: [
                      // Selector de método de pago (sólo en venta normal,
                      // no en devolución).
                      if (!isReturn) ...[
                        _PaymentMethodPicker(
                          selected: _paymentMethod,
                          onChange: (m) =>
                              setState(() => _paymentMethod = m),
                          isLocked: _isSubmitting,
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: isReturn
                                ? const Color(0xFFEF4444)
                                : (_paymentMethod == null
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF22C55E)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _isSubmitting ||
                                  (!isReturn && _paymentMethod == null)
                              ? null
                              : () => isReturn
                                  ? _processReturn()
                                  : _confirmAndCheckout(asCredit: false),
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : Icon(
                                  isReturn
                                      ? Icons.assignment_return_outlined
                                      : Icons.check_circle_outline,
                                  size: 18),
                          label: Text(
                              isReturn
                                  ? 'PROCESAR DEVOLUCIÓN'
                                  : 'COMPLETAR VENTA',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          // CRÉDITO sólo en modo Venta (no aplica en devolución).
                          if (!isReturn) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: _isSubmitting
                                    ? null
                                    : () => _checkout(asCredit: true),
                                icon:
                                    const Icon(Icons.access_time_rounded, size: 18),
                                label: const Text('CRÉDITO',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: const BorderSide(
                                        color: Color(0xFFF1F5F9))),
                              ),
                              onPressed: _isSubmitting ? null : _clearCart,
                              icon: const Icon(Icons.cancel_outlined,
                                  size: 18, color: Color(0xFFEF4444)),
                              label: const Text('CANCELAR',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFEF4444))),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalLine(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w500)),
        Text(value, style: const TextStyle(color: Color(0xFF1E293B), fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    );
  }

  /// Tier de precio del cliente actualmente seleccionado. Null si no hay
  /// cliente o si la lista de clientes aún no se cargó.
  String? _currentClientTier() {
    if (_clientId == null) return null;
    final clients = ref.read(salesClientsProvider).valueOrNull;
    if (clients == null) return null;
    for (final c in clients) {
      if (c.id == _clientId) return c.priceTier;
    }
    return null;
  }

  void _addProductToCart(SalesProduct product) {
    final index = _cart.indexWhere((item) => item.product.id == product.id);
    if (index != -1 && _cart[index].quantity + 1 > product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sin stock suficiente')));
      return;
    }
    final tier = _currentClientTier();
    final price = product.priceFor(tier);
    setState(() {
      if (index == -1) {
        _cart.add(SaleCartItem(
          product: product,
          quantity: 1,
          unitPrice: price,
        ));
      } else {
        final current = _cart[index];
        _cart[index] = SaleCartItem(
          product: current.product,
          quantity: current.quantity + 1,
          unitPrice: current.unitPrice,
        );
      }
    });
  }

  void _changeQty(int index, int delta) {
    final item = _cart[index];
    final next = item.quantity + delta;
    if (next <= 0) { _removeItem(index); return; }
    if (next > item.product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sin stock suficiente')));
      return;
    }
    setState(() => _cart[index] = SaleCartItem(
      product: item.product,
      quantity: next,
      unitPrice: item.unitPrice,
    ));
  }

  /// Cuando cambia el cliente, re-precia las líneas del carrito según el
  /// nuevo tier. Si el nuevo cliente es null o "retail", vuelve al precio
  /// base de cada producto.
  void _onClientChanged(String? newId) {
    setState(() {
      _clientId = newId;
      if (_cart.isEmpty) return;
      String? tier;
      if (newId != null) {
        final clients = ref.read(salesClientsProvider).valueOrNull;
        if (clients != null) {
          for (final c in clients) {
            if (c.id == newId) {
              tier = c.priceTier;
              break;
            }
          }
        }
      }
      for (var i = 0; i < _cart.length; i++) {
        final item = _cart[i];
        _cart[i] = SaleCartItem(
          product: item.product,
          quantity: item.quantity,
          unitPrice: item.product.priceFor(tier),
        );
      }
    });
  }

  void _removeItem(int index) => setState(() => _cart.removeAt(index));

  void _clearCart() => setState(() {
    _cart.clear();
    _notesController.clear();
    _clientId = null;
    _paymentMethod = null;
    _searchController.clear();
    ref.read(salesSearchProvider.notifier).state = '';
  });

  List<SalesProduct> _filterProducts(List<SalesProduct> products, {required String query, required String? selectedCategoryId}) {
    return products.where((p) => 
      p.isActive && 
      p.stock > 0 && 
      (selectedCategoryId == null || p.categoryId == selectedCategoryId) && 
      (p.name.toLowerCase().contains(query) || (p.sku?.toLowerCase().contains(query) ?? false) || (p.barcode?.toLowerCase().contains(query) ?? false))
    ).toList();
  }

  /// Muestra un diálogo de confirmación con el resumen antes de enviar
  /// la venta a checkout. Si el usuario confirma, llama a `_checkout`.
  Future<void> _confirmAndCheckout({required bool asCredit}) async {
    if (_cart.isEmpty) return;
    final methodLabel = _paymentMethodLabel(_paymentMethod);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Completar venta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Artículos: $_cartLines',
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text('Método de pago: $methodLabel',
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                Text(
                  money(_cartTotal),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF22C55E)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E)),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _checkout(asCredit: asCredit);
    }
  }

  String _paymentMethodLabel(String? m) {
    switch (m) {
      case 'cash':
        return 'Efectivo';
      case 'card':
        return 'Tarjeta';
      case 'transfer':
        return 'Transferencia';
      default:
        return '—';
    }
  }

  Future<void> _checkout({required bool asCredit}) async {
    if (_cart.isEmpty) return;
    if (asCredit && _clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Para ventas a crédito debe seleccionar un cliente.')));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final settings = ref.read(appSettingsProvider).valueOrNull;
      final result = await repo.checkoutSale(SaleCheckoutInput(
        items: List.from(_cart),
        receiptType: _receiptType,
        asCredit: asCredit,
        paymentMethod: asCredit ? null : _paymentMethod,
        clientId: _clientId,
        notes: _notesController.text.trim(),
        disallowNoStock: settings?.invDisallowNoStock ?? false,
        customerRequiredForSale:
            settings?.customerRequiredForSale ?? false,
        creditAllowSales: settings?.creditAllowSales ?? true,
      ));

      _clearCart();
      ref.invalidate(salesProductsProvider);

      if (!mounted) return;

      final printJob = result.preparedPrintJob;
      final printAfterSale = settings?.receiptPrintAfterSale ?? true;
      final disableConfirmation =
          settings?.saleDisableCompleteConfirmation ?? true;

      // Auto-imprimir si app_settings.receipt_print_after_sale = true.
      if (printJob != null && printAfterSale) {
        await PrintReceiptDialog.show(context, printJob);
        if (!mounted) return;
      }

      // Si app_settings.sale_disable_complete_confirmation = true, mostrar
      // solo un toast y no bloquear con un diálogo.
      if (disableConfirmation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTokens.success,
            content: Text(
              'Venta #${result.saleNumber} registrada.',
              style:
                  const TextStyle(color: AppTokens.successForeground),
            ),
          ),
        );
      } else {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('¡Venta exitosa!'),
            content: Text(
              'Venta #${result.saleNumber} registrada correctamente.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
              if (printJob != null && !printAfterSale)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    PrintReceiptDialog.show(context, printJob);
                  },
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Ver recibo'),
                ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al procesar venta: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Cambia entre modo Venta y Devolución.
  /// Si el carrito tiene items, pide confirmación antes de descartarlo.
  Future<void> _changePosMode(PosMode next) async {
    final current = ref.read(posModeProvider);
    if (current == next) return;

    if (_cart.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Descartar carrito'),
          content: Text(
            'Tienes $_cartLines artículo(s) en el carrito. '
            'Cambiar de modo descartará el carrito actual. ¿Continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Descartar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      _clearCart();
    }

    ref.read(posModeProvider.notifier).state = next;
  }

  /// Busca una venta por número y precarga sus items en el carrito (devolución).
  Future<void> _loadSaleIntoReturn(String saleNumber) async {
    final cleaned = saleNumber.trim();
    if (cleaned.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final result = await repo.fetchSaleForReturn(cleaned);
      if (!mounted) return;

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se encontró la venta "$cleaned" en esta sucursal.'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
        return;
      }
      if (result.items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La venta no tiene items recuperables '
              '(¿productos inactivos o eliminados?).',
            ),
          ),
        );
        return;
      }

      setState(() {
        _cart
          ..clear()
          ..addAll(result.items);
        // Cliente original si aplica
        if (result.clientId != null && result.clientId!.isNotEmpty) {
          _clientId = result.clientId;
        }
        // Notas con referencia a la venta original
        _notesController.text =
            'Devolución de venta ${result.saleNumber}';
        _saleNumberController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF22C55E),
          content: Text(
            'Venta ${result.saleNumber} cargada · '
            '${result.items.length} línea(s).',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar la venta: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Procesa una devolución a partir del carrito actual.
  Future<void> _processReturn() async {
    if (_cart.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final result = await repo.processReturn(ReturnInput(
        items: List.from(_cart),
        clientId: _clientId,
        notes: _notesController.text.trim(),
      ));

      _clearCart();
      ref.invalidate(salesProductsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text(
            'Devolución #${result.returnNumber} registrada · '
            '${result.itemsCount} artículo(s)'
            '${result.creditBalanceAdjusted ? " · saldo de cliente ajustado" : ""}.',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al procesar devolución: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class _PaymentMethodPicker extends StatelessWidget {
  const _PaymentMethodPicker({
    required this.selected,
    required this.onChange,
    required this.isLocked,
  });

  final String? selected;
  final ValueChanged<String> onChange;
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PaymentChip(
            label: 'Efectivo',
            icon: Icons.payments_outlined,
            color: const Color(0xFF22C55E),
            isActive: selected == 'cash',
            isLocked: isLocked,
            onTap: () => onChange('cash'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _PaymentChip(
            label: 'Tarjeta',
            icon: Icons.credit_card_outlined,
            color: const Color(0xFF2563EB),
            isActive: selected == 'card',
            isLocked: isLocked,
            onTap: () => onChange('card'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _PaymentChip(
            label: 'Transferencia',
            icon: Icons.account_balance_outlined,
            color: const Color(0xFF7C3AED),
            isActive: selected == 'transfer',
            isLocked: isLocked,
            onTap: () => onChange('transfer'),
          ),
        ),
      ],
    );
  }
}

class _PaymentChip extends StatelessWidget {
  const _PaymentChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.isActive,
    required this.isLocked,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool isActive;
  final bool isLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? color : color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isLocked ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: isActive ? color : color.withValues(alpha: 0.3),
              width: isActive ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18, color: isActive ? Colors.white : color),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isActive ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosModeToggle extends ConsumerWidget {
  const _PosModeToggle({required this.mode, required this.onChange});

  final PosMode mode;
  final Future<void> Function(PosMode next) onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(roleAccessProvider);
    return Row(
      children: [
        _ModePill(
          label: 'Venta',
          icon: Icons.shopping_cart_outlined,
          color: const Color(0xFF22C55E),
          isActive: mode == PosMode.sale,
          onTap: () => onChange(PosMode.sale),
        ),
        if (access.canVoidSale) ...[
          const SizedBox(width: AppTokens.s10),
          _ModePill(
            label: 'Devolución',
            icon: Icons.assignment_return_outlined,
            color: const Color(0xFFEF4444),
            isActive: mode == PosMode.returnMode,
            onTap: () => onChange(PosMode.returnMode),
          ),
        ],
      ],
    );
  }
}

class _SaleNumberSearch extends StatelessWidget {
  const _SaleNumberSearch({
    required this.controller,
    required this.isLoading,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool isLoading;
  final Future<void> Function(String saleNumber) onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_return_outlined,
              size: 18, color: Color(0xFFEF4444)),
          const SizedBox(width: AppTokens.s8),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !isLoading,
              textInputAction: TextInputAction.search,
              onSubmitted: onSearch,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Número de venta original (ej: FA-00123)',
                hintStyle: TextStyle(fontSize: 13),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded,
                color: Color(0xFFEF4444), size: 20),
            tooltip: 'Cargar items de la venta',
            onPressed:
                isLoading ? null : () => onSearch(controller.text),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.icon,
    required this.color,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? color : color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s16,
            vertical: AppTokens.s10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18, color: isActive ? Colors.white : color),
              const SizedBox(width: AppTokens.s8),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});
  final SalesProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = product.name.isNotEmpty ? product.name[0].toUpperCase() : '?';
    final isLowStock = product.stock <= 5;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text(initial, style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w800))),
            ),
            const SizedBox(height: 10),
            Text(product.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
            const SizedBox(height: 6),
            Text(money(product.price), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF2563EB))),
            if (isLowStock) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(4)),
                child: const Text('Bajo stock', style: TextStyle(fontSize: 9, color: Color(0xFFB91C1C), fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({required this.item, required this.onDecrease, required this.onIncrease, required this.onRemove});
  final SaleCartItem item;
  final VoidCallback onDecrease, onIncrease, onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isReturn = ref.watch(posModeProvider) == PosMode.returnMode;
    final qtyDisplay = isReturn
        ? '↩ -${item.quantity.toInt()}'
        : item.quantity.toInt().toString();
    final qtyColor =
        isReturn ? const Color(0xFFEF4444) : const Color(0xFF1E293B);
    final bgColor =
        isReturn ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B))),
                Text(money(item.product.price), style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              ],
            ),
          ),
          Row(
            children: [
              _QtySmallBtn(icon: Icons.remove, onTap: onDecrease),
              SizedBox(
                width: isReturn ? 56 : 24,
                child: Center(
                  child: Text(
                    qtyDisplay,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: qtyColor,
                    ),
                  ),
                ),
              ),
              _QtySmallBtn(icon: Icons.add, onTap: onIncrease),
              const SizedBox(width: 8),
              IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFF87171)), visualDensity: VisualDensity.compact),
            ],
          ),
        ],
      ),
    );
  }
}

class _QtySmallBtn extends StatelessWidget {
  const _QtySmallBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 24, height: 24,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, size: 14, color: const Color(0xFF64748B)),
      ),
    );
  }
}
