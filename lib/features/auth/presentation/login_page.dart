import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../data/saved_login_emails.dart';
import 'auth_providers.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  /// Lista de correos guardados que se despliega bajo el campo "Correo".
  final _emailsMenu = OverlayPortalController();
  final _emailFieldLink = LayerLink();

  List<String> _savedEmails = readSavedLoginEmails();

  bool _isLoading = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(_syncEmailsMenu);
    _emailController.addListener(_syncEmailsMenu);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Los guardados que coinciden con lo escrito (todos si está vacío).
  List<String> get _emailSuggestions {
    final typed = _emailController.text.trim().toLowerCase();
    return _savedEmails.where((e) => e.contains(typed)).toList();
  }

  /// La lista se ve mientras el campo tiene el foco y hay algo que sugerir.
  void _syncEmailsMenu() {
    if (!mounted) return;
    setState(() {});
    if (_emailFocus.hasFocus && _emailSuggestions.isNotEmpty) {
      _emailsMenu.show();
    } else {
      _emailsMenu.hide();
    }
  }

  void _pickEmail(String email) {
    _emailController.value = TextEditingValue(
      text: email,
      selection: TextSelection.collapsed(offset: email.length),
    );
    // Pasar a la clave también cierra la lista.
    _passwordFocus.requestFocus();
  }

  void _forgetEmail(String email) {
    forgetLoginEmail(email);
    _savedEmails = readSavedLoginEmails();
    _syncEmailsMenu();
  }

  Future<void> _onLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    try {
      await ref
          .read(authRepositoryProvider)
          .signInWithPassword(
            email: email,
            password: _passwordController.text.trim(),
          );
      // Solo después de entrar bien: un correo mal escrito no se guarda.
      rememberLoginEmail(email);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo iniciar sesión: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D5BD7), Color(0xFF084AA8)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Busi Pos Web',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0D5BD7),
                              letterSpacing: 0.5,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Inicia sesión para continuar',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      LayoutBuilder(
                        builder: (context, constraints) =>
                            CompositedTransformTarget(
                          link: _emailFieldLink,
                          child: OverlayPortal(
                            controller: _emailsMenu,
                            overlayChildBuilder: (context) =>
                                CompositedTransformFollower(
                              link: _emailFieldLink,
                              showWhenUnlinked: false,
                              targetAnchor: Alignment.bottomLeft,
                              offset: const Offset(0, 4),
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: SizedBox(
                                  width: constraints.maxWidth,
                                  // Cuenta como parte del campo: un clic
                                  // aquí no le quita el foco, así que la
                                  // lista no se cierra antes de elegir.
                                  child: TextFieldTapRegion(
                                    child: _SavedEmailsMenu(
                                      emails: _emailSuggestions,
                                      onPick: _pickEmail,
                                      onForget: _forgetEmail,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            child: TextFormField(
                              controller: _emailController,
                              focusNode: _emailFocus,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) =>
                                  _passwordFocus.requestFocus(),
                              decoration: InputDecoration(
                                labelText: 'Correo',
                                hintText: 'admin@empresa.com',
                                suffixIcon: _savedEmails.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(
                                          Icons.arrow_drop_down,
                                        ),
                                        tooltip: 'Correos guardados',
                                        onPressed: () {
                                          _emailController.clear();
                                          _emailFocus.requestFocus();
                                          _syncEmailsMenu();
                                        },
                                      ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Ingresa el correo';
                                }
                                if (!value.contains('@')) {
                                  return 'Correo inválido';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          labelText: 'Clave',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            tooltip: _showPassword
                                ? 'Ocultar clave'
                                : 'Mostrar clave',
                            onPressed: () => setState(
                              () => _showPassword = !_showPassword,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Ingresa la clave';
                          }
                          if (value.length < 6) {
                            return 'Mínimo 6 caracteres';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _isLoading ? null : _onLogin,
                        child: _isLoading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Entrar'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => context.go('/registro'),
                        child: const Text(
                          '¿No tienes cuenta? Crear mi negocio',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Correos guardados bajo el campo "Correo": tocar uno lo pone y la X lo
/// quita de la lista para siempre (en este navegador).
class _SavedEmailsMenu extends StatelessWidget {
  const _SavedEmailsMenu({
    required this.emails,
    required this.onPick,
    required this.onForget,
  });

  final List<String> emails;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onForget;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      color: AppTokens.card,
      borderRadius: BorderRadius.circular(AppTokens.radius),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
          shrinkWrap: true,
          children: [
            for (final email in emails)
              InkWell(
                onTap: () => onPick(email),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: AppTokens.s12,
                    right: AppTokens.s4,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.account_circle_outlined,
                        size: 20,
                        color: AppTokens.mutedForeground,
                      ),
                      const SizedBox(width: AppTokens.s10),
                      Expanded(
                        child: Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => onForget(email),
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Quitar este correo de la lista',
                        color: AppTokens.mutedForeground,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
