// F17 — Gates de acción por rol.
//
// La navegación ya se filtra por `allowedRoles` en cada NavItem (ver
// shell_nav_items.dart). Esto cubre el acceso a pantallas. Pero dentro de
// una pantalla hay acciones sensibles que un cashier no debería ver/usar:
// anular ventas, eliminar productos/clientes, editar precios, sellar Z,
// borrar movimientos de caja chica, etc.
//
// `RoleGate` envuelve un widget y lo oculta para roles no autorizados.
// `RoleAccess` da helpers semánticos para checks inline en `onPressed`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/permissions/presentation/permissions_providers.dart';
import '../../features/shell/presentation/shell_providers.dart';

/// Código del permiso "Ver ganancia" en el catálogo (`permissions.code`).
const kReportsProfitPermission = 'reports.profit';

/// Snapshot inmutable del rol del usuario actual, con helpers semánticos.
class RoleAccess {
  const RoleAccess({
    required this.roleCode,
    this.permissionOverrides = const <String, bool>{},
  });

  final String roleCode;

  /// Overrides propios (`permission_code -> granted`) de la sucursal activa.
  /// Vacío = el usuario no tiene excepciones y todo sale del rol.
  final Map<String, bool> permissionOverrides;

  /// Permiso efectivo: manda el override explícito del usuario si existe; si
  /// no, el valor por defecto del rol, que es el comportamiento histórico.
  /// Sin overrides configurados, `hasPermission` devuelve siempre
  /// `roleDefault`, así que ningún gate cambia de conducta.
  bool hasPermission(String code, {required bool roleDefault}) =>
      permissionOverrides[code] ?? roleDefault;

  bool get isAdmin => roleCode == 'admin';
  bool get isSupervisor => roleCode == 'supervisor';
  bool get isCashier => roleCode == 'cashier';
  bool get isAccountant => roleCode == 'accountant';

  bool hasAny(Set<String> roles) => roles.contains(roleCode);

  // ─── Acciones gerenciales (admin + supervisor) ──────────────────────────
  bool get canVoidSale => isAdmin || isSupervisor;
  bool get canDeleteRecord => isAdmin || isSupervisor;
  bool get canEditPrices => isAdmin || isSupervisor;
  bool get canApplyDiscount => isAdmin || isSupervisor;
  bool get canManageInventoryAdjustments => isAdmin || isSupervisor;
  bool get canSealZClosure => isAdmin || isSupervisor;
  bool get canEditFiscalSettings => isAdmin;
  bool get canManageUsers => isAdmin;
  bool get canManagePettyCash => isAdmin || isSupervisor;

  // ─── Acciones operativas (todos los roles activos) ──────────────────────
  bool get canRegisterSale => !isAccountant;
  bool get canRegisterPayment => !isAccountant;

  // ─── Acciones contables ─────────────────────────────────────────────────
  bool get canViewFiscalReports => isAdmin || isAccountant;
}

/// Provider que expone el `RoleAccess` actual. Lee el rol desde
/// `shellAccessProfileProvider` (que ya combina perfil + override por
/// sucursal) y las excepciones desde `myPermissionOverridesProvider`.
final roleAccessProvider = Provider<RoleAccess>((ref) {
  final access = ref.watch(shellAccessProfileProvider).valueOrNull;
  final overrides = ref.watch(myPermissionOverridesProvider).valueOrNull;
  return RoleAccess(
    roleCode: access?.roleCode ?? 'cashier',
    permissionOverrides: overrides ?? const <String, bool>{},
  );
});

/// ¿Puede el usuario ver la ganancia (columnas/KPIs de utilidad)?
///
/// Por rol: admin, supervisor y contador sí; cajero no. Un override explícito
/// sobre `reports.profit` manda sobre el rol en ambos sentidos.
final canViewProfitProvider = Provider<bool>((ref) {
  final access = ref.watch(roleAccessProvider);
  return access.hasPermission(
    kReportsProfitPermission,
    roleDefault: access.isAdmin || access.isSupervisor || access.isAccountant,
  );
});

/// Envuelve un widget y lo oculta si el rol actual no está en `allowed`.
/// Por defecto devuelve `SizedBox.shrink()` cuando se oculta — pasar
/// `fallback` para mostrar otra cosa (ej. mensaje "sin permiso").
class RoleGate extends ConsumerWidget {
  const RoleGate({
    super.key,
    required this.allowed,
    required this.child,
    this.fallback = const SizedBox.shrink(),
  });

  final Set<String> allowed;
  final Widget child;
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(roleAccessProvider);
    return access.hasAny(allowed) ? child : fallback;
  }
}
