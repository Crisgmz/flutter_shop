import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/formatters/formatters.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/print_receipt_dialog.dart';
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

  final List<SaleCartItem> _cart = [];

  bool _isSubmitting = false;
  bool _showCart = false;
  String _receiptType = 'consumer_final';
  final String _paymentMethod = 'cash';
  String? _clientId;

  int get _cartLines => _cart.length;
  double get _cartSubtotal => _cart.fold<double>(0, (sum, item) => sum + item.lineSubtotal);
  double get _cartTax => _cart.fold<double>(0, (sum, item) => sum + item.lineTax);
  double get _cartTotal => _cartSubtotal + _cartTax;

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(salesProductsProvider);
    final categoriesAsync = ref.watch(salesCategoriesProvider);
    final clientsAsync = ref.watch(salesClientsProvider);
    final query = ref.watch(salesSearchProvider).trim().toLowerCase();
    final selectedCategoryId = ref.watch(salesSelectedCategoryProvider);
    final isMobile = ResponsiveLayout.isMobile(context);
    final padding = adaptivePadding(context);

    if (isMobile && _showCart) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Carrito de Venta'),
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
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Punto de Venta',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    'Registrar nueva venta',
                    style: TextStyle(
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
                            DropdownMenuItem(value: 'consumer_final', child: Text('Consumidor Final')),
                            DropdownMenuItem(value: 'fiscal_credit', child: Text('Fiscal')),
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
                        onChanged: (v) => setState(() => _clientId = v),
                      ),
                    ),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text('Error al cargar clientes'),
                ),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text(money(_cartTotal), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF2563EB))),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isSubmitting ? null : () => _checkout(asCredit: false),
                    icon: _isSubmitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.wallet_rounded, size: 18),
                    label: const Text('COBRAR CONTADO', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isSubmitting ? null : () => _checkout(asCredit: true),
                        icon: const Icon(Icons.access_time_rounded, size: 18),
                        label: const Text('CRÉDITO', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFFF1F5F9))),
                        ),
                        onPressed: _isSubmitting ? null : _clearCart,
                        icon: const Icon(Icons.cancel_outlined, size: 18, color: Color(0xFFEF4444)),
                        label: const Text('CANCELAR', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFEF4444))),
                      ),
                    ),
                  ],
                ),
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

  void _addProductToCart(SalesProduct product) {
    final index = _cart.indexWhere((item) => item.product.id == product.id);
    if (index != -1 && _cart[index].quantity + 1 > product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sin stock suficiente')));
      return;
    }
    setState(() {
      if (index == -1) {
        _cart.add(SaleCartItem(product: product, quantity: 1));
      } else {
        final current = _cart[index];
        _cart[index] = SaleCartItem(product: current.product, quantity: current.quantity + 1);
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
    setState(() => _cart[index] = SaleCartItem(product: item.product, quantity: next));
  }

  void _removeItem(int index) => setState(() => _cart.removeAt(index));

  void _clearCart() => setState(() { 
    _cart.clear(); 
    _notesController.clear(); 
    _clientId = null; 
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

  Future<void> _checkout({required bool asCredit}) async {
    if (_cart.isEmpty) return;
    if (asCredit && _clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Para ventas a crédito debe seleccionar un cliente.')));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final result = await repo.checkoutSale(SaleCheckoutInput(
        items: List.from(_cart),
        receiptType: _receiptType,
        asCredit: asCredit,
        paymentMethod: asCredit ? null : _paymentMethod,
        clientId: _clientId,
        notes: _notesController.text.trim(),
      ));

      _clearCart();
      ref.invalidate(salesProductsProvider);

      if (mounted) {
        final printJob = result.preparedPrintJob;
        showDialog(
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
              if (printJob != null)
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

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({required this.item, required this.onDecrease, required this.onIncrease, required this.onRemove});
  final SaleCartItem item;
  final VoidCallback onDecrease, onIncrease, onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10)),
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
              SizedBox(width: 24, child: Center(child: Text(item.quantity.toInt().toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
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
