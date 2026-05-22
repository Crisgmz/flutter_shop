import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/ncf_stock_banner.dart';
import '../../../shared/widgets/print_receipt_dialog.dart';
import '../../../shared/widgets/role_gate.dart';
import '../../cash_register/data/cash_register_repository.dart';
import '../../cash_register/presentation/cash_register_providers.dart';
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
              Expanded(
                child: Column(
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
              ),
              const _ActiveCashRegisterChip(),
              if (isMobile && _cartLines > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Badge(
                    label: Text('$_cartLines'),
                    child: IconButton(
                      icon: const Icon(Icons.shopping_cart_outlined),
                      onPressed: () => setState(() => _showCart = true),
                    ),
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
                childAspectRatio: 1, // cuadrado perfecto
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
                      key: ValueKey(_cart[i].product.id),
                      item: _cart[i],
                      onRemove: () => _removeItem(i),
                      onPriceChanged: (value) => _setUnitPrice(i, value),
                      onQuantityChanged: (value) => _setQty(i, value),
                      onDiscountChanged: (value) => _setDiscountPct(i, value),
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
                                    : _confirmCreditCheckout,
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

  /// Si el setting global "No permitir venta sin stock" está apagado, el
  /// cliente NO bloquea ventas por falta de stock — deja que el RPC lo
  /// valide (o lo permita). Si está prendido, refuerza la validación en UI
  /// para evitar viajes innecesarios al servidor.
  bool get _stockEnforced =>
      ref.read(appSettingsProvider).valueOrNull?.invDisallowNoStock ?? false;

  void _addProductToCart(SalesProduct product) {
    final index = _cart.indexWhere((item) => item.product.id == product.id);
    if (_stockEnforced &&
        index != -1 &&
        _cart[index].quantity + 1 > product.stock) {
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
          discountPct: current.discountPct,
        );
      }
    });
  }

  /// Setea la cantidad a un valor específico (desde el input del cart line).
  /// Si es <= 0 elimina el item.
  void _setQty(int index, double value) {
    if (value <= 0) {
      _removeItem(index);
      return;
    }
    final item = _cart[index];
    if (_stockEnforced && value > item.product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sin stock suficiente')),
      );
      return;
    }
    setState(() => _cart[index] = SaleCartItem(
          product: item.product,
          quantity: value,
          unitPrice: item.unitPrice,
          discountPct: item.discountPct,
        ));
  }

  /// Setea el precio unitario de una línea (override manual).
  void _setUnitPrice(int index, double value) {
    if (value < 0) return;
    final item = _cart[index];
    setState(() => _cart[index] = SaleCartItem(
          product: item.product,
          quantity: item.quantity,
          unitPrice: value,
          discountPct: item.discountPct,
        ));
  }

  /// Setea el descuento porcentual de una línea (0-100).
  void _setDiscountPct(int index, double value) {
    final clamped = value.clamp(0, 100).toDouble();
    final item = _cart[index];
    setState(() => _cart[index] = SaleCartItem(
          product: item.product,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          discountPct: clamped,
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
          discountPct: item.discountPct,
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

  /// Abre un diálogo que pide los días de plazo (default desde settings) y
  /// luego ejecuta el checkout a crédito.
  Future<void> _confirmCreditCheckout() async {
    if (_cart.isEmpty) return;
    if (_clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Para ventas a crédito debe seleccionar un cliente.'),
      ));
      return;
    }
    final settings = ref.read(appSettingsProvider).valueOrNull;
    final defaultDays = settings?.creditDefaultDays ?? 30;
    final controller = TextEditingController(text: defaultDays.toString());
    final today = DateTime.now();

    int parseDays() {
      final raw = int.tryParse(controller.text.trim()) ?? defaultDays;
      return raw.clamp(1, 365);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final days = parseDays();
          final due = today.add(Duration(days: days));
          return AlertDialog(
            title: const Text('Venta a crédito'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total: ${money(_cartTotal)}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Días de plazo',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setLocal(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vence: ${due.day.toString().padLeft(2, '0')}/'
                  '${due.month.toString().padLeft(2, '0')}/${due.year}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTokens.mutedForeground,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Confirmar'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      await _checkout(asCredit: true, creditDueDays: parseDays());
    }
    controller.dispose();
  }

  Future<void> _checkout({
    required bool asCredit,
    int? creditDueDays,
  }) async {
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
        creditDueDays: creditDueDays,
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
      // Stack para superponer el badge de stock en la esquina superior
      // derecha sin alterar el layout interior de la tarjeta.
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Tarjeta plana: borde gris visible, fondo blanco, contenido
          // centrado (inicial grande, nombre y precio).
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: const Color(0xFFF1F5F9),
                    child: product.imageUrl != null &&
                            product.imageUrl!.trim().isNotEmpty
                        ? Image.network(
                            product.imageUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Center(
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: Color(0xFF2563EB),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  product.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  money(product.price),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2563EB),
                  ),
                ),
                if (isLowStock) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Bajo stock',
                      style: TextStyle(
                        fontSize: 9,
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _StockBadge(stock: product.stock),
          ),
        ],
      ),
    );
  }
}

/// Badge circular con la cantidad en existencia. Color según nivel:
///   - rojo si 0
///   - ámbar si ≤ 5
///   - verde si > 5
class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.stock});

  final double stock;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (stock) {
      <= 0 => (const Color(0xFFDC2626), Colors.white),
      <= 5 => (const Color(0xFFF59E0B), Colors.white),
      _ => (const Color(0xFF16A34A), Colors.white),
    };
    // Formato: entero si es redondo, una decimal si no.
    final label = stock == stock.roundToDouble()
        ? stock.toInt().toString()
        : stock.toStringAsFixed(1);

    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Línea del carrito con campos editables: Precio, Cantidad, Descuento y
/// Total calculado. Cada campo es un mini-TextField. Total se actualiza al
/// salir del foco de cualquiera de los inputs.
class _CartLineTile extends ConsumerStatefulWidget {
  const _CartLineTile({
    super.key,
    required this.item,
    required this.onRemove,
    required this.onPriceChanged,
    required this.onQuantityChanged,
    required this.onDiscountChanged,
  });

  final SaleCartItem item;
  final VoidCallback onRemove;
  final ValueChanged<double> onPriceChanged;
  final ValueChanged<double> onQuantityChanged;
  final ValueChanged<double> onDiscountChanged;

  @override
  ConsumerState<_CartLineTile> createState() => _CartLineTileState();
}

class _CartLineTileState extends ConsumerState<_CartLineTile> {
  late final TextEditingController _priceCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _discountCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(text: _fmtNum(widget.item.unitPrice));
    _qtyCtrl = TextEditingController(text: _fmtNum(widget.item.quantity));
    _discountCtrl =
        TextEditingController(text: _fmtNum(widget.item.discountPct));
  }

  @override
  void didUpdateWidget(covariant _CartLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sincronizamos los controllers cuando el padre cambia el item desde
    // afuera (ej. tier-change re-pricia, suma de cantidad por re-add, etc.).
    if (oldWidget.item.unitPrice != widget.item.unitPrice) {
      _priceCtrl.text = _fmtNum(widget.item.unitPrice);
    }
    if (oldWidget.item.quantity != widget.item.quantity) {
      _qtyCtrl.text = _fmtNum(widget.item.quantity);
    }
    if (oldWidget.item.discountPct != widget.item.discountPct) {
      _discountCtrl.text = _fmtNum(widget.item.discountPct);
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  static String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isReturn = ref.watch(posModeProvider) == PosMode.returnMode;
    final bgColor =
        isReturn ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Fila superior: nombre + botón quitar ──
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      'Inventario: ${_fmtNum(item.product.stock)}'
                      '${item.product.sku != null ? '  ·  SKU: ${item.product.sku}' : ''}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Color(0xFFF87171),
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── Fila inferior: 4 campos (Precio, Cant, Desc, Total) ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _CartField(
                  label: 'Precio',
                  controller: _priceCtrl,
                  suffix: r'$',
                  onSubmit: (raw) {
                    final v = double.tryParse(raw) ?? item.unitPrice;
                    widget.onPriceChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CartField(
                  label: 'Cantidad',
                  controller: _qtyCtrl,
                  onSubmit: (raw) {
                    final v = double.tryParse(raw) ?? item.quantity;
                    widget.onQuantityChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CartField(
                  label: 'Descuento',
                  controller: _discountCtrl,
                  suffix: '%',
                  onSubmit: (raw) {
                    final v = double.tryParse(raw) ?? item.discountPct;
                    widget.onDiscountChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        money(item.lineTotal),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isReturn
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF2563EB),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mini-input usado dentro de la línea del carrito (Precio / Cant / Desc).
/// Tiene label arriba y commitea el valor al perder el foco o al presionar
/// enter para que setState del padre se dispare una sola vez por edición.
class _CartField extends StatefulWidget {
  const _CartField({
    required this.label,
    required this.controller,
    required this.onSubmit,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final String? suffix;

  @override
  State<_CartField> createState() => _CartFieldState();
}

class _CartFieldState extends State<_CartField> {
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
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          onSubmitted: widget.onSubmit,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            suffixText: widget.suffix,
            suffixStyle: const TextStyle(
              fontSize: 11,
              color: Color(0xFF94A3B8),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

/// Chip mostrando la caja sobre la que el cajero está vendiendo y un botón
/// para cerrarla. Se oculta si todavía no hay sesión / caja resueltas
/// (provider en loading o sin caja asociada — p.ej. sesiones legacy).
class _ActiveCashRegisterChip extends ConsumerWidget {
  const _ActiveCashRegisterChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameAsync = ref.watch(currentOpenCashRegisterNameProvider);
    final name = nameAsync.valueOrNull;
    if (name == null || name.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(left: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.point_of_sale,
              size: 16, color: Color(0xFF1D4ED8)),
          const SizedBox(width: 6),
          Text(
            'Caja: $name',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Color(0xFF1D4ED8),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => _confirmCloseCaja(context, ref),
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.logout_rounded,
                  size: 16, color: Color(0xFF1D4ED8)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCloseCaja(BuildContext context, WidgetRef ref) async {
    final input = await showDialog<CloseCashInput>(
      context: context,
      builder: (_) => const _CloseCajaDialog(),
    );
    if (input == null) return;
    if (!context.mounted) return;

    try {
      await ref.read(cashRegisterRepositoryProvider).closeSession(input);
      ref.invalidate(cashRegisterDataProvider);
      ref.invalidate(allOpenCashSessionsProvider);
      if (!context.mounted) return;
      AppSnackBar.success(context, 'Caja cerrada correctamente');
    } catch (error) {
      if (!context.mounted) return;
      AppSnackBar.error(context, 'No se pudo cerrar la caja', error);
    }
  }
}

class _CloseCajaDialog extends StatefulWidget {
  const _CloseCajaDialog();

  @override
  State<_CloseCajaDialog> createState() => _CloseCajaDialogState();
}

class _CloseCajaDialogState extends State<_CloseCajaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _closingController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _closingController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cerrar caja'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _closingController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto contado al cierre',
                  prefixText: r'RD$ ',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  if (parsed == null || parsed < 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              CloseCashInput(
                closingAmount: double.parse(_closingController.text),
                notes: _notesController.text,
              ),
            );
          },
          icon: const Icon(Icons.lock_outline, size: 18),
          label: const Text('Cerrar'),
        ),
      ],
    );
  }
}
