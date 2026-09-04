import 'package:flutter/material.dart';

class NavItem {
  const NavItem({
    required this.path,
    required this.label,
    required this.icon,
    this.allowedRoles = const {'admin', 'supervisor', 'cashier', 'accountant'},
    this.permissionCode,
  });

  final String path;
  final String label;
  final IconData icon;
  final Set<String> allowedRoles;

  /// Código del catálogo `permissions` asociado al módulo. Si es `null`, el
  /// item solo se filtra por rol. Los overrides del dueño mandan sobre
  /// `allowedRoles` en ambos sentidos.
  final String? permissionCode;

  bool allows(String role) => allowedRoles.contains(role);

  /// Visibilidad efectiva: el override explícito del usuario manda; si no hay
  /// override (caso normal), decide `allowedRoles` igual que siempre.
  bool allowsWith(String role, Map<String, bool> overrides) {
    final code = permissionCode;
    if (code == null) return allows(role);
    return overrides[code] ?? allows(role);
  }
}

class NavSection {
  const NavSection({required this.label, required this.items});

  final String label;
  final List<NavItem> items;

  NavSection visibleFor(
    String role, {
    Map<String, bool> overrides = const <String, bool>{},
  }) {
    return NavSection(
      label: label,
      items: items
          .where((item) => item.allowsWith(role, overrides))
          .toList(growable: false),
    );
  }
}

const dashboardNavItem = NavItem(
  path: '/panel',
  label: 'Panel',
  icon: Icons.grid_view_rounded,
  permissionCode: 'dashboard.view',
);
const salesNavItem = NavItem(
  path: '/ventas',
  label: 'Ventas',
  icon: Icons.receipt_long_outlined,
  permissionCode: 'sales.create',
);
const salesHistoryNavItem = NavItem(
  path: '/ventas/historial',
  label: 'Historial de ventas',
  icon: Icons.history,
  allowedRoles: {'admin', 'supervisor', 'cashier', 'accountant'},
  permissionCode: 'sales.view',
);
const quotationsNavItem = NavItem(
  path: '/cotizaciones',
  label: 'Cotizaciones',
  icon: Icons.request_quote_outlined,
  allowedRoles: {'admin', 'supervisor', 'cashier', 'accountant'},
);
const cobrosNavItem = NavItem(
  path: '/cuentas-por-cobrar',
  label: 'Cuentas por cobrar',
  icon: Icons.request_page_outlined,
  allowedRoles: {'admin', 'supervisor', 'cashier', 'accountant'},
  permissionCode: 'clients.credit',
);
const payablesNavItem = NavItem(
  path: '/cuentas-por-pagar',
  label: 'Cuentas por pagar',
  icon: Icons.payments_outlined,
  allowedRoles: {'admin', 'supervisor', 'accountant'},
);
const inventoryNavItem = NavItem(
  path: '/inventario',
  label: 'Inventario',
  icon: Icons.inventory_2_outlined,
  allowedRoles: {'admin', 'supervisor'},
  permissionCode: 'inventory.view',
);
const purchasesNavItem = NavItem(
  path: '/compras',
  label: 'Compras',
  icon: Icons.shopping_cart_outlined,
  allowedRoles: {'admin', 'supervisor', 'accountant'},
  permissionCode: 'purchases.view',
);
const clientsNavItem = NavItem(
  path: '/clientes',
  label: 'Clientes',
  icon: Icons.people_outline,
  allowedRoles: {'admin', 'supervisor', 'cashier', 'accountant'},
  permissionCode: 'clients.view',
);
const suppliersNavItem = NavItem(
  path: '/proveedores',
  label: 'Proveedores',
  icon: Icons.local_shipping_outlined,
  allowedRoles: {'admin', 'supervisor', 'accountant'},
);
const reportsNavItem = NavItem(
  path: '/reportes',
  label: 'Reportes',
  icon: Icons.bar_chart_outlined,
  allowedRoles: {'admin', 'supervisor', 'accountant'},
  permissionCode: 'reports.view',
);
const expensesNavItem = NavItem(
  path: '/gastos',
  label: 'Gastos',
  icon: Icons.wallet_outlined,
  allowedRoles: {'admin', 'supervisor', 'cashier', 'accountant'},
  permissionCode: 'expenses.view',
);
const cashRegisterNavItem = NavItem(
  path: '/caja',
  label: 'Cierre de Caja',
  icon: Icons.account_balance_outlined,
  allowedRoles: {'admin', 'supervisor', 'cashier', 'accountant'},
  permissionCode: 'cash.close',
);
const pettyCashNavItem = NavItem(
  path: '/caja-chica',
  label: 'Caja chica',
  icon: Icons.savings_outlined,
  allowedRoles: {'admin', 'supervisor', 'cashier', 'accountant'},
  permissionCode: 'cash.manage',
);
const fiscalDocumentsNavItem = NavItem(
  path: '/comprobantes',
  label: 'Comprobantes',
  icon: Icons.receipt_outlined,
  allowedRoles: {'admin', 'supervisor', 'accountant'},
  permissionCode: 'ncf.view',
);
const taxesNavItem = NavItem(
  path: '/impuestos',
  label: 'Impuestos',
  icon: Icons.calculate_outlined,
  allowedRoles: {'admin', 'accountant'},
);
const branchesNavItem = NavItem(
  path: '/sucursales',
  label: 'Sucursales',
  icon: Icons.apartment_outlined,
  allowedRoles: {'admin'},
);
const usersNavItem = NavItem(
  path: '/usuarios',
  label: 'Usuarios',
  icon: Icons.badge_outlined,
  allowedRoles: {'admin'},
);
const settingsNavItem = NavItem(
  path: '/configuracion',
  label: 'Configuración',
  icon: Icons.settings_outlined,
  allowedRoles: {'admin', 'supervisor'},
  permissionCode: 'settings.view',
);

const navItems = [
  dashboardNavItem,
  salesNavItem,
  salesHistoryNavItem,
  quotationsNavItem,
  cobrosNavItem,
  payablesNavItem,
  inventoryNavItem,
  purchasesNavItem,
  clientsNavItem,
  suppliersNavItem,
  reportsNavItem,
  cashRegisterNavItem,
  pettyCashNavItem,
  expensesNavItem,
  fiscalDocumentsNavItem,
  taxesNavItem,
  branchesNavItem,
  usersNavItem,
  settingsNavItem,
];

const navSections = [
  NavSection(
    label: 'Operación',
    items: [
      dashboardNavItem,
      salesNavItem,
      salesHistoryNavItem,
      quotationsNavItem,
      cashRegisterNavItem,
      pettyCashNavItem,
      expensesNavItem,
    ],
  ),
  NavSection(
    label: 'Contabilidad',
    items: [
      cobrosNavItem,
      payablesNavItem,
    ],
  ),
  NavSection(
    label: 'Catálogo',
    items: [
      inventoryNavItem,
      purchasesNavItem,
      clientsNavItem,
      suppliersNavItem,
    ],
  ),
  NavSection(
    label: 'Control',
    items: [reportsNavItem, fiscalDocumentsNavItem, taxesNavItem],
  ),
  NavSection(
    label: 'Administración',
    items: [branchesNavItem, usersNavItem, settingsNavItem],
  ),
];

List<NavSection> visibleNavSectionsForRole(
  String role, {
  Map<String, bool> overrides = const <String, bool>{},
}) {
  return navSections
      .map((section) => section.visibleFor(role, overrides: overrides))
      .where((section) => section.items.isNotEmpty)
      .toList(growable: false);
}
