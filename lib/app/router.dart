import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/env.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/branches/presentation/branches_page.dart';
import '../features/cash_register/presentation/cash_register_page.dart';
import '../features/clients/presentation/clients_page.dart';
import '../features/cobros/presentation/cobros_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/expenses/presentation/expenses_page.dart';
import '../features/fiscal_documents/presentation/fiscal_documents_page.dart';
import '../features/inventory/presentation/inventory_page.dart';
import '../features/purchases/presentation/purchases_page.dart';
import '../features/quotations/presentation/quotation_create_page.dart';
import '../features/quotations/presentation/quotations_page.dart';
import '../features/reports/presentation/reports_page.dart';
import '../features/sales/presentation/sales_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/setup/presentation/setup_page.dart';
import '../features/shell/presentation/app_shell.dart';
import '../features/suppliers/presentation/suppliers_page.dart';
import '../features/taxes/presentation/taxes_page.dart';
import '../features/users/presentation/users_page.dart';
import 'router_refresh_stream.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // ── Supabase not configured → show setup wizard ───────────────────────────
  if (!Env.isSupabaseConfigured) {
    return GoRouter(
      initialLocation: '/setup',
      routes: [GoRoute(path: '/setup', builder: (_, _) => const SetupPage())],
    );
  }

  // ── Normal app flow ───────────────────────────────────────────────────────
  final authRepo = ref.watch(authRepositoryProvider);
  final refreshStream = GoRouterRefreshStream(authRepo.authStateChanges);
  ref.onDispose(refreshStream.dispose);

  return GoRouter(
    initialLocation: '/panel',
    refreshListenable: refreshStream,
    redirect: (_, state) {
      final loggedIn = authRepo.currentSession != null;
      final inLogin = state.matchedLocation == '/login';

      if (!loggedIn && !inLogin) return '/login';
      if (loggedIn && inLogin) return '/panel';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),

      // All authenticated module routes share the AppShell via ShellRoute.
      ShellRoute(
        builder: (_, _, child) => AppShell(child: child),
        routes: [
          _page('/panel', const DashboardPage()),
          _page('/ventas', const SalesPage()),
          _page('/cotizaciones', const QuotationsPage()),
          GoRoute(
            path: '/cotizaciones/nueva',
            pageBuilder: (_, _) => const NoTransitionPage(
              child: QuotationCreatePage(),
            ),
          ),
          GoRoute(
            path: '/cotizaciones/:quoteId',
            pageBuilder: (_, state) => NoTransitionPage(
              child: QuotationCreatePage(
                quoteId: state.pathParameters['quoteId'],
              ),
            ),
          ),
          _page('/cobros', const CobrosPage()),
          _page('/gastos', const ExpensesPage()),
          _page('/inventario', const InventoryPage()),
          _page('/compras', const PurchasesPage()),
          _page('/clientes', const ClientsPage()),
          _page('/proveedores', const SuppliersPage()),
          _page('/caja', const CashRegisterPage()),
          _page('/reportes', const ReportsPage()),
          _page('/comprobantes', const FiscalDocumentsPage()),
          _page('/impuestos', const TaxesPage()),
          _page('/sucursales', const BranchesPage()),
          _page('/usuarios', const UsersPage()),
          _page('/configuracion', const SettingsPage()),
        ],
      ),
    ],
  );
});

/// Helper that creates a [GoRoute] with [NoTransitionPage] (avoids flicker
/// when switching between shell children).
GoRoute _page(String path, Widget child) {
  return GoRoute(
    path: path,
    pageBuilder: (_, _) => NoTransitionPage(child: child),
  );
}
