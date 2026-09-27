import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../theme/club_theme.dart';

class ClubApp extends StatefulWidget {
  const ClubApp({this.firebaseConfigured = false, super.key});

  final bool firebaseConfigured;

  @override
  State<ClubApp> createState() => _ClubAppState();
}

class _ClubAppState extends State<ClubApp> {
  final _auth = AuthService();
  final _push = PushNotificationService();
  late final _api = ApiService(tokenProvider: _auth.getIdToken);
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _darkMode = false;
  bool _restoringSession = true;
  late final _pushMessageSubscription = _push.foregroundMessages.listen((
    message,
  ) {
    final notification = message.notification;
    if (notification == null) return;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          '${notification.title ?? 'Reserva'}: ${notification.body ?? 'Tenés una notificación nueva.'}',
        ),
      ),
    );
  });

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    if (!widget.firebaseConfigured) {
      setState(() => _restoringSession = false);
      return;
    }
    try {
      final authUser = await _auth.reloadCurrentUser();
      if (authUser == null || !authUser.emailVerified) {
        setState(() => _restoringSession = false);
        return;
      }
      final profile = await _api.getProfile();
      if (!mounted) return;
      setState(() => _restoringSession = false);
      _enter(profile);
    } on ApiException {
      if (mounted) setState(() => _restoringSession = false);
    } on AuthException {
      if (mounted) setState(() => _restoringSession = false);
    }
  }

  void _toggleTheme() => setState(() => _darkMode = !_darkMode);

  @override
  void dispose() {
    unawaited(_pushMessageSubscription.cancel());
    unawaited(_push.dispose());
    _api.close();
    super.dispose();
  }

  void _enter(Usuario? usuario) {
    if (usuario != null && widget.firebaseConfigured) {
      unawaited(_push.start(_api));
    }
    _navigatorKey.currentState?.pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => MainShell(
          api: _api,
          initialUser: usuario,
          isAdmin: usuario?.isAdmin ?? false,
          darkMode: _darkMode,
          onThemeChanged: _toggleTheme,
          onSignOut: _showAccess,
        ),
      ),
    );
  }

  void _showAccess() {
    unawaited(_push.stop(_api));
    unawaited(_auth.signOut());
    _navigatorKey.currentState?.pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => AccessScreen(
          api: _api,
          auth: _auth,
          firebaseConfigured: widget.firebaseConfigured,
          onEnter: _enter,
          darkMode: _darkMode,
          onThemeChanged: _toggleTheme,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      title: 'Club Jerónimo Zarlenga',
      debugShowCheckedModeBanner: false,
      locale: const Locale('es', 'AR'),
      supportedLocales: const [Locale('es', 'AR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ClubTheme.light(),
      darkTheme: ClubTheme.dark(),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      home: _restoringSession
          ? const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: ClubColors.lime),
              ),
            )
          : AccessScreen(
              api: _api,
              auth: _auth,
              firebaseConfigured: widget.firebaseConfigured,
              onEnter: _enter,
              darkMode: _darkMode,
              onThemeChanged: _toggleTheme,
            ),
    );
  }
}

class AccessScreen extends StatefulWidget {
  const AccessScreen({
    required this.api,
    required this.auth,
    required this.firebaseConfigured,
    required this.onEnter,
    required this.darkMode,
    required this.onThemeChanged,
    super.key,
  });

  final ApiService api;
  final AuthService auth;
  final bool firebaseConfigured;
  final void Function(Usuario? user) onEnter;
  final bool darkMode;
  final VoidCallback onThemeChanged;

  @override
  State<AccessScreen> createState() => _AccessScreenState();
}

class _AccessScreenState extends State<AccessScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final registered = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RegisterScreen(api: widget.api, auth: widget.auth),
      ),
    );
    if (registered == true && mounted) {
      setState(
        () => _message =
            'Te enviamos un enlace para verificar el correo antes de iniciar sesión.',
      );
    }
  }

  Future<void> _signIn() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _message = 'Ingresá tu correo y contraseña.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final credential = await widget.auth.signIn(
        email: _email.text,
        password: _password.text,
      );
      var authUser = credential.user;
      await authUser?.reload();
      authUser = widget.auth.currentUser;
      if (authUser == null) {
        throw const AuthException('No se pudo recuperar la sesión.');
      }
      if (!authUser.emailVerified) {
        await widget.auth.sendVerificationEmail();
        await widget.auth.signOut();
        if (mounted) {
          setState(
            () => _message =
                'Verificá tu correo desde el enlace que te enviamos y después volvé a ingresar.',
          );
        }
        return;
      }
      Usuario profile;
      try {
        profile = await widget.api.getProfile();
      } on ApiException catch (error) {
        if (error.statusCode != 404 || !mounted) rethrow;
        final completed = await Navigator.of(context).push<Usuario>(
          MaterialPageRoute<Usuario>(
            builder: (_) =>
                ProfileSetupScreen(api: widget.api, email: authUser!.email!),
          ),
        );
        if (completed == null) return;
        profile = completed;
      }
      if (mounted) widget.onEnter(profile);
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_email.text.trim().isEmpty) {
      setState(
        () => _message =
            'Escribí tu correo y volvé a tocar “¿Olvidaste tu contraseña?”.',
      );
      return;
    }
    try {
      await widget.auth.sendPasswordReset(_email.text);
      if (mounted) {
        setState(
          () => _message =
              'Si el correo está registrado, Firebase te enviará un enlace para restablecer la contraseña.',
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/club-pitch.png', fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: .68),
                  Colors.black.withValues(alpha: .86),
                  Colors.black,
                ],
                stops: const [0, .48, 1],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: IconButton(
                          tooltip: isDark
                              ? 'Usar modo claro'
                              : 'Usar modo oscuro',
                          onPressed: widget.onThemeChanged,
                          icon: Icon(
                            isDark
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      SizedBox(height: size.height < 760 ? 12 : 34),
                      const _Eyebrow('BIENVENIDO A'),
                      const SizedBox(height: 14),
                      const Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'CLUB '),
                            TextSpan(
                              text: 'JERÓNIMO ZARLENGA',
                              style: TextStyle(color: ClubColors.lime),
                            ),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 34,
                          height: .98,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Gestión de espacios deportivos',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 30),
                      if (!widget.firebaseConfigured)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .11),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Firebase todavía no está configurado. Podés explorar las sedes mientras conectás tu proyecto.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _message!,
                            style: const TextStyle(
                              color: ClubColors.lime,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _email,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        decoration: _darkInput('Email', Icons.mail_outline),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        enabled: !_busy,
                        obscureText: !_showPassword,
                        style: const TextStyle(color: Colors.white),
                        decoration: _darkInput('Contraseña', Icons.lock_outline)
                            .copyWith(
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _resetPassword,
                          child: const Text(
                            '¿Olvidaste tu contraseña?',
                            style: TextStyle(
                              color: ClubColors.lime,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _PrimaryButton(
                        label: _busy ? 'CONECTANDO…' : 'INICIAR SESIÓN',
                        onPressed: _busy ? null : _signIn,
                        loading: _busy,
                      ),
                      const SizedBox(height: 24),
                      const _DividerLabel(label: 'O'),
                      const SizedBox(height: 18),
                      Center(
                        child: TextButton(
                          key: const ValueKey('open-register'),
                          onPressed: _busy ? null : _register,
                          child: const Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '¿No tenés cuenta? ',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                TextSpan(
                                  text: 'CREAR CUENTA  →',
                                  style: TextStyle(
                                    color: ClubColors.lime,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => widget.onEnter(null),
                          icon: const Icon(Icons.explore_outlined, size: 17),
                          label: const Text('Explorar sedes como invitado'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({required this.api, required this.auth, super.key});

  final ApiService api;
  final AuthService auth;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _surname = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  DateTime? _birthDate;
  bool _saving = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _name.dispose();
    _surname.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_birthDate == null) {
      _notice(context, 'Seleccioná tu fecha de nacimiento.');
      return;
    }
    setState(() => _saving = true);
    try {
      final existingAuthUser = widget.auth.currentUser;
      if (existingAuthUser?.email?.toLowerCase() !=
          _email.text.trim().toLowerCase()) {
        await widget.auth.register(
          email: _email.text.trim(),
          password: _password.text,
          nombre: _name.text.trim(),
          apellido: _surname.text.trim(),
        );
      }
      await widget.api.createUsuario(
        nombre: _name.text.trim(),
        apellido: _surname.text.trim(),
        email: _email.text.trim(),
        fechaNacimiento: _dateValue(_birthDate!),
      );
      await widget.auth.signOut();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) _notice(context, error.message);
    } on AuthException catch (error) {
      if (mounted) _notice(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text(
          'CREAR CUENTA',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
              children: [
                const _Eyebrow('JUGÁ EN TU CLUB'),
                const SizedBox(height: 10),
                Text(
                  'Empezá por tus datos',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: _required,
                ),
                const SizedBox(height: 13),
                TextFormField(
                  controller: _surname,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Apellido'),
                  validator: _required,
                ),
                const SizedBox(height: 13),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: (value) {
                    if (_required(value) != null) return 'Ingresá tu email';
                    return RegExp(
                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                        ).hasMatch(value!.trim())
                        ? null
                        : 'Revisá el formato del email';
                  },
                ),
                const SizedBox(height: 13),
                TextFormField(
                  controller: _password,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => (value?.length ?? 0) < 8
                      ? 'Usá al menos 8 caracteres'
                      : null,
                ),
                const SizedBox(height: 13),
                TextFormField(
                  controller: _confirmPassword,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Repetir contraseña',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (value) => value != _password.text
                      ? 'Las contraseñas no coinciden'
                      : null,
                ),
                const SizedBox(height: 13),
                InkWell(
                  onTap: _pickBirthDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Fecha de nacimiento',
                      suffixIcon: Icon(Icons.calendar_month_outlined),
                    ),
                    child: Text(
                      _birthDate == null
                          ? 'Seleccionar fecha'
                          : _dateLabel(_birthDate!),
                      style: TextStyle(
                        color: _birthDate == null
                            ? Theme.of(context).hintColor
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'Te enviaremos un enlace de verificación. Tenés que verificar el correo antes de iniciar sesión.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 22),
                _PrimaryButton(
                  label: _saving ? 'CREANDO…' : 'CREAR CUENTA',
                  onPressed: _saving ? null : _submit,
                  loading: _saving,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({required this.api, required this.email, super.key});

  final ApiService api;
  final String email;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _surname = TextEditingController();
  DateTime? _birthDate;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _surname.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_birthDate == null) {
      _notice(context, 'Seleccioná tu fecha de nacimiento.');
      return;
    }
    setState(() => _saving = true);
    try {
      final profile = await widget.api.createUsuario(
        nombre: _name.text.trim(),
        apellido: _surname.text.trim(),
        email: widget.email,
        fechaNacimiento: _dateValue(_birthDate!),
      );
      if (mounted) Navigator.of(context).pop(profile);
    } on ApiException catch (error) {
      if (mounted) _notice(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'COMPLETÁ TU PERFIL',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const _Eyebrow('UN ÚLTIMO PASO'),
          const SizedBox(height: 8),
          Text(
            'Tus datos del club',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(widget.email, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 22),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: _required,
          ),
          const SizedBox(height: 13),
          TextFormField(
            controller: _surname,
            decoration: const InputDecoration(labelText: 'Apellido'),
            validator: _required,
          ),
          const SizedBox(height: 13),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime(now.year - 18, now.month, now.day),
                firstDate: DateTime(1900),
                lastDate: now,
              );
              if (date != null) setState(() => _birthDate = date);
            },
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(
              _birthDate == null
                  ? 'Fecha de nacimiento'
                  : _dateLabel(_birthDate!),
            ),
            style: _outlinedButtonStyle(context),
          ),
          const SizedBox(height: 22),
          _PrimaryButton(
            label: _saving ? 'GUARDANDO…' : 'GUARDAR PERFIL',
            onPressed: _saving ? null : _save,
            loading: _saving,
          ),
        ],
      ),
    ),
  );
}

class MainShell extends StatefulWidget {
  const MainShell({
    required this.api,
    required this.initialUser,
    required this.isAdmin,
    required this.darkMode,
    required this.onThemeChanged,
    required this.onSignOut,
    super.key,
  });

  final ApiService api;
  final Usuario? initialUser;
  final bool isAdmin;
  final bool darkMode;
  final VoidCallback onThemeChanged;
  final VoidCallback onSignOut;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  Usuario? _user;
  late bool _darkMode = widget.darkMode;
  int _tab = 0;
  bool _loading = true;
  String? _apiError;
  List<Sede> _sedes = [];
  List<EspacioDeportivo> _spaces = [];
  List<Reserva> _reservations = [];
  String _sport = 'Todos';

  @override
  void initState() {
    super.initState();
    _user = widget.initialUser;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _apiError = null;
    });
    try {
      final sedes = await widget.api.getSedes();
      final spaces = await widget.api.getEspacios();
      final reservations = _user == null
          ? <Reserva>[]
          : await widget.api.getReservas(usuarioId: _user!.id);
      if (!mounted) return;
      setState(() {
        _sedes = sedes;
        _spaces = spaces;
        _reservations = reservations;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _apiError = error.message;
        _loading = false;
      });
    }
  }

  Future<Usuario?> _ensureUser() async {
    if (_user != null) return _user;
    widget.onSignOut();
    return null;
  }

  void _toggleTheme() {
    setState(() => _darkMode = !_darkMode);
    widget.onThemeChanged();
  }

  Future<void> _openAvailability({int? sedeId}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AvailabilityScreen(
          api: widget.api,
          sedes: _sedes,
          spaces: _spaces,
          initialSedeId: sedeId,
          ensureUser: _ensureUser,
        ),
      ),
    );
    if (changed == true) await _refresh();
  }

  void _openAdmin() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AdminSedesScreen(api: widget.api, onChanged: _refresh),
      ),
    );
  }

  Future<void> _editProfile() async {
    final currentUser = _user;
    if (currentUser == null) return;
    final updated = await Navigator.of(context).push<Usuario>(
      MaterialPageRoute<Usuario>(
        builder: (_) => EditProfileScreen(api: widget.api, user: currentUser),
      ),
    );
    if (updated != null && mounted) setState(() => _user = updated);
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      HomeScreen(
        user: _user,
        sedes: _sedes,
        spaces: _spaces,
        reservations: _reservations,
        selectedSport: _sport,
        onSportChanged: (sport) => setState(() => _sport = sport),
        onRefresh: _refresh,
        onOpenAvailability: () => _openAvailability(),
        onOpenVenue: (sede) => _openAvailability(sedeId: sede.id),
        onOpenVenues: () => setState(() => _tab = 1),
      ),
      VenuesScreen(
        sedes: _sedes,
        spaces: _spaces,
        selectedSport: _sport,
        onSportChanged: (sport) => setState(() => _sport = sport),
        onOpenVenue: (sede) => _openAvailability(sedeId: sede.id),
      ),
      ReservationsScreen(
        user: _user,
        reservations: _reservations,
        spaces: _spaces,
        sedes: _sedes,
        onRegister: _ensureUser,
        onRefresh: _refresh,
        api: widget.api,
      ),
      ProfileScreen(
        user: _user,
        isAdmin: widget.isAdmin,
        darkMode: _darkMode,
        onThemeChanged: _toggleTheme,
        onRegister: _ensureUser,
        onEditProfile: _editProfile,
        onAdmin: _openAdmin,
        onSignOut: widget.onSignOut,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              children: [
                if (_apiError != null)
                  _ConnectionBanner(message: _apiError!, onRetry: _refresh),
                if (_loading)
                  const LinearProgressIndicator(
                    minHeight: 2,
                    color: ClubColors.lime,
                  ),
                Expanded(
                  child: IndexedStack(index: _tab, children: children),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _BottomNavigation(
        selected: _tab,
        onSelected: (index) => setState(() => _tab = index),
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => _openAvailability(),
              backgroundColor: ClubColors.lime,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.search),
              label: const Text(
                'BUSCAR CANCHA',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
              ),
            )
          : null,
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.user,
    required this.sedes,
    required this.spaces,
    required this.reservations,
    required this.selectedSport,
    required this.onSportChanged,
    required this.onRefresh,
    required this.onOpenAvailability,
    required this.onOpenVenue,
    required this.onOpenVenues,
    super.key,
  });

  final Usuario? user;
  final List<Sede> sedes;
  final List<EspacioDeportivo> spaces;
  final List<Reserva> reservations;
  final String selectedSport;
  final ValueChanged<String> onSportChanged;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenAvailability;
  final ValueChanged<Sede> onOpenVenue;
  final VoidCallback onOpenVenues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = selectedSport == 'Todos'
        ? sedes
        : sedes
              .where(
                (sede) => spaces.any(
                  (space) =>
                      space.sedeId == sede.id &&
                      _matchesSport(space.tipo, selectedSport),
                ),
              )
              .toList();
    final active =
        reservations
            .where((reservation) => reservation.estado == 'activa')
            .toList()
          ..sort((a, b) => a.fecha.compareTo(b.fecha));

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _HomeHero(user: user)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 120),
            sliver: SliverList.list(
              children: [
                _NextReservation(
                  reservation: active.isEmpty ? null : active.first,
                ),
                const SizedBox(height: 17),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final sport in _sports)
                        Padding(
                          padding: const EdgeInsets.only(right: 7),
                          child: _FilterChip(
                            label: sport,
                            selected: selectedSport == sport,
                            onTap: () => onSportChanged(sport),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'SEDES DISPONIBLES',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onOpenVenues,
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('Ver todas'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (filtered.isEmpty)
                  _EmptyState(
                    icon: Icons.sports_soccer,
                    title: 'Todavía no hay sedes',
                    subtitle:
                        'Cuando el club cargue sus espacios, vas a poder reservar desde acá.',
                    action: 'BUSCAR CANCHA',
                    onAction: onOpenAvailability,
                  )
                else
                  SizedBox(
                    height: 204,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) => SizedBox(
                        width: 238,
                        child: _VenueCard(
                          sede: filtered[index],
                          spaces: spaces
                              .where(
                                (space) => space.sedeId == filtered[index].id,
                              )
                              .toList(),
                          compact: true,
                          onTap: () => onOpenVenue(filtered[index]),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                _OutlinedAction(
                  icon: Icons.calendar_month_outlined,
                  label: 'Consultar disponibilidad',
                  onPressed: onOpenAvailability,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VenuesScreen extends StatelessWidget {
  const VenuesScreen({
    required this.sedes,
    required this.spaces,
    required this.selectedSport,
    required this.onSportChanged,
    required this.onOpenVenue,
    super.key,
  });

  final List<Sede> sedes;
  final List<EspacioDeportivo> spaces;
  final String selectedSport;
  final ValueChanged<String> onSportChanged;
  final ValueChanged<Sede> onOpenVenue;

  @override
  Widget build(BuildContext context) {
    final items = selectedSport == 'Todos'
        ? sedes
        : sedes
              .where(
                (sede) => spaces.any(
                  (space) =>
                      space.sedeId == sede.id &&
                      _matchesSport(space.tipo, selectedSport),
                ),
              )
              .toList();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _PageHeader(
            eyebrow: 'CLUB JERÓNIMO ZARLENGA',
            title: 'SEDES',
            subtitle: '${sedes.length} sedes registradas',
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final sport in _sports)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: _FilterChip(
                        label: sport,
                        selected: selectedSport == sport,
                        onTap: () => onSportChanged(sport),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              icon: Icons.location_city_outlined,
              title: 'No encontramos sedes',
              subtitle: 'Probá con otro deporte o volvé a cargar la lista.',
              action: 'TODOS LOS DEPORTES',
              onAction: () => onSportChanged('Todos'),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
            sliver: SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) => _VenueCard(
                sede: items[index],
                spaces: spaces
                    .where((space) => space.sedeId == items[index].id)
                    .toList(),
                onTap: () => onOpenVenue(items[index]),
              ),
            ),
          ),
      ],
    );
  }
}

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({
    required this.api,
    required this.sedes,
    required this.spaces,
    required this.ensureUser,
    this.initialSedeId,
    super.key,
  });

  final ApiService api;
  final List<Sede> sedes;
  final List<EspacioDeportivo> spaces;
  final Future<Usuario?> Function() ensureUser;
  final int? initialSedeId;

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  late int? _venueId = widget.initialSedeId;
  String _sport = 'Fútbol';
  String _surface = 'Todas';
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  int _duration = 1;
  bool _searched = false;
  bool _searching = false;
  bool _saving = false;
  String? _searchError;
  List<EspacioDeportivo> _results = [];
  final Map<int, List<String>> _availableTimes = {};
  final Map<int, String> _selectedTimes = {};

  Future<void> _search() async {
    if (_venueId == null && widget.sedes.isNotEmpty) {
      _notice(context, 'Elegí una sede para consultar canchas.');
      return;
    }
    final candidates = widget.spaces.where((space) {
      final matchesVenue = _venueId == null || space.sedeId == _venueId;
      final matchesSport = _matchesSport(space.tipo, _sport);
      final matchesSurface =
          _surface == 'Todas' ||
          _normalize(space.tipo).contains(_normalize(_surface));
      return matchesVenue && matchesSport && matchesSurface;
    }).toList();
    setState(() {
      _searched = true;
      _searching = true;
      _searchError = null;
      _results = [];
      _availableTimes.clear();
      _selectedTimes.clear();
    });
    try {
      for (final space in candidates) {
        final times = await widget.api.getAvailableTimes(
          espacioId: space.id,
          fecha: _dateValue(_date),
          durationHours: _duration,
        );
        if (times.isNotEmpty) {
          _availableTimes[space.id] = times;
          _selectedTimes[space.id] = times.first;
          _results.add(space);
        }
      }
      if (mounted) setState(() => _searching = false);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _searching = false;
          _searchError = error.message;
        });
      }
    }
  }

  Future<void> _book(EspacioDeportivo space, String selectedTime) async {
    final user = await widget.ensureUser();
    if (user == null || !mounted) return;
    final startHour = int.parse(selectedTime.substring(0, 2));
    final endHour = startHour + _duration;
    if (endHour > 23) {
      _notice(context, 'El horario debe terminar antes de las 23:00.');
      return;
    }
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _BookingReview(
        sede: widget.sedes.where((sede) => sede.id == space.sedeId).firstOrNull,
        space: space,
        date: _date,
        startHour: startHour,
        endHour: endHour,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.api.createReserva(
        espacioId: space.id,
        fecha: _dateValue(_date),
        horaInicio: '${startHour.toString().padLeft(2, '0')}:00:00',
        horaFin: '${endHour.toString().padLeft(2, '0')}:00:00',
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) _notice(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton.filledTonal(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'CONSULTAR CANCHAS',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Elegí sede, deporte, fecha y horario para ver disponibilidad.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 24),
                        _FieldLabel('SEDE'),
                        DropdownButtonFormField<int>(
                          initialValue: _venueId,
                          hint: const Text('Seleccioná una sede'),
                          items: widget.sedes
                              .map(
                                (sede) => DropdownMenuItem(
                                  value: sede.id,
                                  child: Text(sede.nombre),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _venueId = value),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _LabeledDropdown<String>(
                                label: 'DEPORTE',
                                value: _sport,
                                values: _sports
                                    .where((sport) => sport != 'Todos')
                                    .toList(),
                                onChanged: (value) =>
                                    setState(() => _sport = value),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const _FieldLabel('FECHA'),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final value = await showDatePicker(
                                        context: context,
                                        initialDate: _date,
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime.now().add(
                                          const Duration(days: 180),
                                        ),
                                      );
                                      if (value != null) {
                                        setState(() => _date = value);
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 16,
                                    ),
                                    label: Text(
                                      _dateLabel(_date),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    style: _outlinedButtonStyle(context),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _LabeledDropdown<int>(
                          label: 'DURACIÓN',
                          value: _duration,
                          values: const [1, 2],
                          display: (duration) =>
                              '$duration ${duration == 1 ? 'hora' : 'horas'}',
                          onChanged: (value) =>
                              setState(() => _duration = value),
                        ),
                        const SizedBox(height: 21),
                        const _FieldLabel('TIPO DE CANCHA'),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final surface in const [
                              'Todas',
                              'Polvo',
                              'Cemento',
                              'Indoor',
                            ])
                              _FilterChip(
                                label: surface,
                                selected: _surface == surface,
                                onTap: () => setState(() => _surface = surface),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _PrimaryButton(
                          label: 'CONSULTAR DISPONIBILIDAD',
                          onPressed: _searching ? null : _search,
                          loading: _searching,
                        ),
                        const SizedBox(height: 9),
                        _SecondaryButton(
                          label: 'LIMPIAR FILTROS',
                          onPressed: () => setState(() {
                            _venueId = null;
                            _sport = 'Fútbol';
                            _surface = 'Todas';
                            _date = DateTime.now().add(const Duration(days: 1));
                            _duration = 1;
                            _searched = false;
                            _results = [];
                            _availableTimes.clear();
                            _selectedTimes.clear();
                            _searchError = null;
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_searched)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
                    sliver: SliverList.list(
                      children: [
                        if (_searchError != null)
                          Text(
                            _searchError!,
                            style: const TextStyle(color: ClubColors.danger),
                          )
                        else if (_searching)
                          const Center(
                            child: CircularProgressIndicator(
                              color: ClubColors.lime,
                            ),
                          )
                        else if (_results.isEmpty)
                          const _EmptyState(
                            icon: Icons.search_off,
                            title: 'Sin disponibilidad',
                            subtitle:
                                'Probá otra fecha, duración, sede o deporte.',
                          )
                        else
                          for (final space in _results)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _SpaceResultCard(
                                space: space,
                                sede: widget.sedes
                                    .where((sede) => sede.id == space.sedeId)
                                    .firstOrNull,
                                times: _availableTimes[space.id] ?? const [],
                                selectedTime: _selectedTimes[space.id]!,
                                onTimeSelected: (value) => setState(
                                  () => _selectedTimes[space.id] = value,
                                ),
                                onBook: _saving
                                    ? null
                                    : () => _book(
                                        space,
                                        _selectedTimes[space.id]!,
                                      ),
                              ),
                            ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReservationsScreen extends StatelessWidget {
  const ReservationsScreen({
    required this.user,
    required this.reservations,
    required this.spaces,
    required this.sedes,
    required this.onRegister,
    required this.onRefresh,
    required this.api,
    super.key,
  });

  final Usuario? user;
  final List<Reserva> reservations;
  final List<EspacioDeportivo> spaces;
  final List<Sede> sedes;
  final Future<Usuario?> Function() onRegister;
  final Future<void> Function() onRefresh;
  final ApiService api;

  @override
  Widget build(BuildContext context) {
    final active = reservations
        .where((reservation) => reservation.estado == 'activa')
        .toList();
    final cancelled = reservations
        .where((reservation) => reservation.estado != 'activa')
        .toList();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _PageHeader(
            eyebrow: 'TU ACTIVIDAD',
            title: 'RESERVAS',
            subtitle: user == null
                ? 'Ingresá para ver tus turnos'
                : '${active.length} reservas activas',
          ),
        ),
        if (user == null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              icon: Icons.calendar_month_outlined,
              title: 'Reservá tu próximo partido',
              subtitle:
                  'Creá una cuenta para guardar y administrar tus reservas.',
              action: 'CREAR CUENTA',
              onAction: onRegister,
            ),
          )
        else if (reservations.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'Todavía no hay reservas',
              subtitle: 'Cuando confirmes una cancha, va a aparecer acá.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            sliver: SliverList.list(
              children: [
                for (final reservation in active)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ReservationCard(
                      reservation: reservation,
                      space: spaces
                          .where((space) => space.id == reservation.espacioId)
                          .firstOrNull,
                      sede: _venueForReservation(reservation, spaces, sedes),
                      onCancel: () async {
                        final confirm = await _confirmCancel(context);
                        if (confirm != true) return;
                        try {
                          await api.cancelReserva(reservation.id);
                          await onRefresh();
                        } on ApiException catch (error) {
                          if (context.mounted) _notice(context, error.message);
                        }
                      },
                    ),
                  ),
                if (cancelled.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const _SectionTitle('HISTORIAL'),
                  for (final reservation in cancelled)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _ReservationCard(
                        reservation: reservation,
                        space: spaces
                            .where((space) => space.id == reservation.espacioId)
                            .firstOrNull,
                        sede: _venueForReservation(reservation, spaces, sedes),
                        disabled: true,
                      ),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    required this.user,
    required this.isAdmin,
    required this.darkMode,
    required this.onThemeChanged,
    required this.onRegister,
    required this.onEditProfile,
    required this.onAdmin,
    required this.onSignOut,
    super.key,
  });

  final Usuario? user;
  final bool isAdmin;
  final bool darkMode;
  final VoidCallback onThemeChanged;
  final Future<Usuario?> Function() onRegister;
  final VoidCallback onEditProfile;
  final VoidCallback onAdmin;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 32),
      children: [
        const _Eyebrow('CLUB JERÓNIMO ZARLENGA'),
        const SizedBox(height: 8),
        Text('MI PERFIL', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: _surfaceDecoration(context),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: ClubColors.lime,
                foregroundColor: Colors.black,
                child: Text(
                  user?.nombre.substring(0, 1).toUpperCase() ?? 'I',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user == null
                          ? 'Invitado'
                          : '${user!.nombre} ${user!.apellido}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user?.email ?? 'Sin cuenta vinculada',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (user != null)
                      Text(
                        'Nacimiento · ${user!.fechaNacimiento == null ? 'Sin fecha' : _dateLabel(DateTime.parse(user!.fechaNacimiento!))}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 19),
        if (user == null)
          _SettingsRow(
            icon: Icons.person_add_alt_1,
            title: 'Crear cuenta',
            subtitle: 'Guardá tus reservas',
            onTap: onRegister,
          )
        else
          _SettingsRow(
            icon: Icons.verified_user_outlined,
            title: 'Cuenta registrada',
            subtitle: 'ID ${user!.id}',
            onTap: onEditProfile,
          ),
        if (user != null)
          _SettingsRow(
            icon: Icons.edit_outlined,
            title: 'Editar perfil',
            subtitle: 'Nombre, apellido y fecha de nacimiento',
            onTap: onEditProfile,
          ),
        _SettingsRow(
          icon: darkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
          title: 'Apariencia',
          subtitle: darkMode ? 'Modo oscuro' : 'Modo claro',
          trailing: Switch(
            value: darkMode,
            activeTrackColor: ClubColors.lime,
            onChanged: (_) => onThemeChanged(),
          ),
          onTap: onThemeChanged,
        ),
        _SettingsRow(
          icon: Icons.notifications_none,
          title: 'Notificaciones',
          subtitle: 'Recordatorios 24 y 1 hora antes',
          onTap: () => _notice(
            context,
            'Los recordatorios se envían a este dispositivo cuando la notificación está permitida.',
          ),
        ),
        if (isAdmin) ...[
          const SizedBox(height: 18),
          const _SectionTitle('ADMINISTRACIÓN'),
          const SizedBox(height: 8),
          _SettingsRow(
            icon: Icons.apartment_outlined,
            title: 'Gestionar sedes',
            subtitle: 'Crear sedes y espacios deportivos',
            onTap: onAdmin,
          ),
        ],
        const SizedBox(height: 24),
        _SecondaryButton(label: 'CERRAR SESIÓN', onPressed: onSignOut),
        if (isAdmin)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Los permisos de administración están vinculados a tu cuenta Firebase.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({required this.api, required this.user, super.key});

  final ApiService api;
  final Usuario user;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user.nombre);
  late final _surname = TextEditingController(text: widget.user.apellido);
  late DateTime? _birthDate = widget.user.fechaNacimiento == null
      ? null
      : DateTime.tryParse(widget.user.fechaNacimiento!);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _surname.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_birthDate == null) {
      _notice(context, 'Seleccioná tu fecha de nacimiento.');
      return;
    }
    setState(() => _saving = true);
    try {
      final profile = await widget.api.updateProfile(
        nombre: _name.text.trim(),
        apellido: _surname.text.trim(),
        fechaNacimiento: _dateValue(_birthDate!),
      );
      if (mounted) Navigator.of(context).pop(profile);
    } on ApiException catch (error) {
      if (mounted) _notice(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'EDITAR PERFIL',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const _Eyebrow('MIS DATOS'),
          const SizedBox(height: 18),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: _required,
          ),
          const SizedBox(height: 13),
          TextFormField(
            controller: _surname,
            decoration: const InputDecoration(labelText: 'Apellido'),
            validator: _required,
          ),
          const SizedBox(height: 13),
          TextFormField(
            initialValue: widget.user.email,
            enabled: false,
            decoration: const InputDecoration(
              labelText: 'Correo electrónico',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 13),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final date = await showDatePicker(
                context: context,
                initialDate:
                    _birthDate ?? DateTime(now.year - 18, now.month, now.day),
                firstDate: DateTime(1900),
                lastDate: now,
              );
              if (date != null) setState(() => _birthDate = date);
            },
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(
              _birthDate == null
                  ? 'Fecha de nacimiento'
                  : _dateLabel(_birthDate!),
            ),
            style: _outlinedButtonStyle(context),
          ),
          const SizedBox(height: 20),
          _PrimaryButton(
            label: _saving ? 'GUARDANDO…' : 'GUARDAR CAMBIOS',
            onPressed: _saving ? null : _save,
            loading: _saving,
          ),
        ],
      ),
    ),
  );
}

class AdminSedesScreen extends StatefulWidget {
  const AdminSedesScreen({
    required this.api,
    required this.onChanged,
    super.key,
  });

  final ApiService api;
  final Future<void> Function() onChanged;

  @override
  State<AdminSedesScreen> createState() => _AdminSedesScreenState();
}

class _AdminSedesScreenState extends State<AdminSedesScreen> {
  List<Sede> _sedes = [];
  List<EspacioDeportivo> _spaces = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sedes = await widget.api.getSedes();
      final spaces = await widget.api.getEspacios();
      if (!mounted) return;
      setState(() {
        _sedes = sedes;
        _spaces = spaces;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        _notice(context, error.message);
      }
    }
  }

  Future<void> _addVenue() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => AddVenueScreen(api: widget.api)),
    );
    if (changed == true) {
      await _load();
      await widget.onChanged();
    }
  }

  Future<void> _manageVenue(Sede sede) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ManageVenueScreen(
          api: widget.api,
          sede: sede,
          onChanged: widget.onChanged,
        ),
      ),
    );
    if (changed == true) {
      await _load();
      await widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'GESTIONAR SEDES',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addVenue,
        backgroundColor: ClubColors.lime,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text(
          'AGREGAR SEDE',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: ClubColors.lime),
            )
          : _sedes.isEmpty
          ? const _EmptyState(
              icon: Icons.apartment_outlined,
              title: 'No hay sedes registradas',
              subtitle: 'Agregá la primera sede para cargar sus canchas.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
              itemCount: _sedes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final sede = _sedes[index];
                final count = _spaces
                    .where((space) => space.sedeId == sede.id)
                    .length;
                return _VenueCard(
                  sede: sede,
                  spaces: _spaces
                      .where((space) => space.sedeId == sede.id)
                      .toList(),
                  onTap: () => _manageVenue(sede),
                  actionLabel: 'AGREGAR CANCHA · $count',
                );
              },
            ),
    );
  }
}

class ManageVenueScreen extends StatefulWidget {
  const ManageVenueScreen({
    required this.api,
    required this.sede,
    required this.onChanged,
    super.key,
  });

  final ApiService api;
  final Sede sede;
  final Future<void> Function() onChanged;

  @override
  State<ManageVenueScreen> createState() => _ManageVenueScreenState();
}

class _ManageVenueScreenState extends State<ManageVenueScreen> {
  List<EspacioDeportivo> _spaces = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final spaces = await widget.api.getEspacios(sedeId: widget.sede.id);
      if (mounted) {
        setState(() {
          _spaces = spaces;
          _loading = false;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        _notice(context, error.message);
      }
    }
  }

  Future<void> _addSpace([EspacioDeportivo? space]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _AddSpaceDialog(api: widget.api, sede: widget.sede, space: space),
    );
    if (changed == true) {
      await _load();
      await widget.onChanged();
    }
  }

  Future<void> _editVenue() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddVenueScreen(api: widget.api, venue: widget.sede),
      ),
    );
    if (changed == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _deleteVenue() async {
    final confirmed = await _confirmAction(
      context,
      'Eliminar sede',
      'Esta acción no se puede deshacer. Las sedes con canchas no se pueden eliminar.',
    );
    if (confirmed != true) return;
    try {
      await widget.api.deleteSede(widget.sede.id);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) _notice(context, error.message);
    }
  }

  Future<void> _deleteSpace(EspacioDeportivo space) async {
    final confirmed = await _confirmAction(
      context,
      'Eliminar cancha',
      'La cancha con reservas históricas no se puede eliminar.',
    );
    if (confirmed != true) return;
    try {
      await widget.api.deleteEspacio(space.id);
      await _load();
      await widget.onChanged();
    } on ApiException catch (error) {
      if (mounted) _notice(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.sede.nombre.toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: [
        IconButton(
          onPressed: _editVenue,
          tooltip: 'Editar sede',
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          onPressed: _deleteVenue,
          tooltip: 'Eliminar sede',
          icon: const Icon(Icons.delete_outline, color: ClubColors.danger),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _addSpace(),
      backgroundColor: ClubColors.lime,
      foregroundColor: Colors.black,
      icon: const Icon(Icons.add),
      label: const Text(
        'AGREGAR CANCHA',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator(color: ClubColors.lime))
        : _spaces.isEmpty
        ? const _EmptyState(
            icon: Icons.sports_soccer,
            title: 'Esta sede todavía no tiene canchas',
            subtitle: 'Agregá un espacio deportivo para habilitar reservas.',
          )
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
            itemCount: _spaces.length,
            separatorBuilder: (_, _) => const SizedBox(height: 9),
            itemBuilder: (context, index) {
              final space = _spaces[index];
              return Container(
                decoration: _surfaceDecoration(context),
                child: ListTile(
                  title: Text(
                    space.tipo,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    space.nombreCompuesto,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: Wrap(
                    spacing: 0,
                    children: [
                      IconButton(
                        onPressed: () => _addSpace(space),
                        tooltip: 'Editar cancha',
                        icon: const Icon(Icons.edit_outlined, size: 19),
                      ),
                      IconButton(
                        onPressed: () => _deleteSpace(space),
                        tooltip: 'Eliminar cancha',
                        icon: const Icon(
                          Icons.delete_outline,
                          color: ClubColors.danger,
                          size: 19,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
  );
}

class AddVenueScreen extends StatefulWidget {
  const AddVenueScreen({required this.api, this.venue, super.key});

  final ApiService api;
  final Sede? venue;

  @override
  State<AddVenueScreen> createState() => _AddVenueScreenState();
}

class _AddVenueScreenState extends State<AddVenueScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.venue?.nombre ?? '');
  late final _address = TextEditingController(
    text: widget.venue?.direccion ?? '',
  );
  late int _open =
      int.tryParse((widget.venue?.horaApertura ?? '').split(':').first) ?? 8;
  late int _close =
      int.tryParse((widget.venue?.horaCierre ?? '').split(':').first) ?? 23;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final nombre = _name.text.trim();
      final direccion = _address.text.trim();
      final horaApertura = '${_open.toString().padLeft(2, '0')}:00:00';
      final horaCierre = '${_close.toString().padLeft(2, '0')}:00:00';
      if (widget.venue == null) {
        await widget.api.createSede(
          nombre: nombre,
          direccion: direccion,
          horaApertura: horaApertura,
          horaCierre: horaCierre,
        );
      } else {
        await widget.api.updateSede(
          sedeId: widget.venue!.id,
          nombre: nombre,
          direccion: direccion,
          horaApertura: horaApertura,
          horaCierre: horaCierre,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) _notice(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.venue == null ? 'AGREGAR SEDE' : 'EDITAR SEDE',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre de la sede'),
              validator: _required,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Dirección'),
              validator: _required,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _LabeledDropdown<int>(
                    label: 'ABRE',
                    value: _open,
                    values: List.generate(23, (i) => i),
                    display: (hour) => '${hour.toString().padLeft(2, '0')}:00',
                    onChanged: (value) => setState(() {
                      _open = value;
                      if (_close <= value) _close = value + 1;
                    }),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _LabeledDropdown<int>(
                    label: 'CIERRA',
                    value: _close,
                    values: List.generate(23, (i) => i + 1),
                    display: (hour) => '${hour.toString().padLeft(2, '0')}:00',
                    onChanged: (value) => setState(() => _close = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _PrimaryButton(
              label: widget.venue == null ? 'GUARDAR SEDE' : 'GUARDAR CAMBIOS',
              onPressed: _saving ? null : _save,
              loading: _saving,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddSpaceDialog extends StatefulWidget {
  const _AddSpaceDialog({required this.api, required this.sede, this.space});

  final ApiService api;
  final Sede sede;
  final EspacioDeportivo? space;

  @override
  State<_AddSpaceDialog> createState() => _AddSpaceDialogState();
}

class _AddSpaceDialogState extends State<_AddSpaceDialog> {
  late String _sport = widget.space?.tipo ?? 'Fútbol 5';
  late final _number = TextEditingController(
    text: widget.space?.nombreCompuesto.split('_').last ?? '1',
  );
  bool _saving = false;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final number = int.tryParse(_number.text);
    if (number == null || number < 1) {
      _notice(context, 'Ingresá un número de cancha válido.');
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.space == null) {
        await widget.api.createEspacio(
          sedeId: widget.sede.id,
          tipo: _sport,
          numero: number,
        );
      } else {
        await widget.api.updateEspacio(
          espacioId: widget.space!.id,
          sedeId: widget.sede.id,
          tipo: _sport,
          numero: number,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) _notice(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '${widget.space == null ? 'Agregar' : 'Editar'} cancha · ${widget.sede.nombre}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _sport,
            items: {..._sportTypes, _sport}
                .toList()
                .map(
                  (sport) => DropdownMenuItem(value: sport, child: Text(sport)),
                )
                .toList(),
            onChanged: (value) => setState(() => _sport = value ?? _sport),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _number,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Número de cancha'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: ClubColors.lime,
            foregroundColor: Colors.black,
          ),
          child: Text(_saving ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }
}

class _BookingReview extends StatelessWidget {
  const _BookingReview({
    required this.sede,
    required this.space,
    required this.date,
    required this.startHour,
    required this.endHour,
  });

  final Sede? sede;
  final EspacioDeportivo space;
  final DateTime date;
  final int startHour;
  final int endHour;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'CONFIRMÁ TU RESERVA',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _surfaceDecoration(context),
              child: Column(
                children: [
                  _InfoLine(label: 'Sede', value: sede?.nombre ?? 'Sede'),
                  _InfoLine(label: 'Cancha', value: _prettySpace(space)),
                  _InfoLine(label: 'Fecha', value: _dateLabel(date)),
                  _InfoLine(
                    label: 'Horario',
                    value: '${_hourLabel(startHour)} a ${_hourLabel(endHour)}',
                  ),
                  _InfoLine(label: 'Precio', value: 'A consultar en la sede'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _PrimaryButton(
              label: 'CONFIRMAR RESERVA',
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 8),
            _SecondaryButton(
              label: 'VOLVER',
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  static const _items = [
    (Icons.home_outlined, Icons.home, 'INICIO'),
    (Icons.apartment_outlined, Icons.apartment, 'SEDES'),
    (Icons.calendar_month_outlined, Icons.calendar_month, 'RESERVAS'),
    (Icons.person_outline, Icons.person, 'PERFIL'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 7, 18, 10),
        child: Container(
          height: 66,
          decoration: BoxDecoration(
            color: dark ? ClubColors.darkBackground : const Color(0xFFF0F2F8),
            border: Border.all(
              color: dark ? const Color(0xFF292B30) : const Color(0xFFD4D7DE),
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: dark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .07),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          child: Row(
            children: [
              for (var index = 0; index < _items.length; index++)
                Expanded(
                  child: InkWell(
                    onTap: () => onSelected(index),
                    borderRadius: BorderRadius.circular(18),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          index == selected
                              ? _items[index].$2
                              : _items[index].$1,
                          size: 20,
                          color: index == selected
                              ? ClubColors.olive
                              : theme.hintColor,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _items[index].$3,
                          style: TextStyle(
                            fontSize: 8,
                            letterSpacing: .6,
                            fontWeight: FontWeight.w900,
                            color: index == selected
                                ? ClubColors.olive
                                : theme.hintColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: index == selected ? 21 : 0,
                          height: 2,
                          decoration: BoxDecoration(
                            color: ClubColors.lime,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.user});

  final Usuario? user;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 250,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/club-pitch.png', fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: .78),
                  Colors.black.withValues(alpha: .22),
                  Theme.of(context).scaffoldBackgroundColor,
                ],
                stops: const [0, .62, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 34, 20, 25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'BUENOS DÍAS,',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              letterSpacing: 2.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            user?.nombre ?? 'Jugador',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _RoundIcon(
                      icon: Icons.notifications_none,
                      onTap: () =>
                          _notice(context, 'No hay notificaciones nuevas.'),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: ClubColors.lime,
                      foregroundColor: Colors.black,
                      child: Text(
                        user?.nombre.substring(0, 1).toUpperCase() ?? 'I',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                const _Eyebrow('CLUB JERÓNIMO ZARLENGA'),
                const SizedBox(height: 7),
                const Text(
                  'ZONA DEPORTIVA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 31,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  isDark
                      ? 'RESERVÁ TU PRÓXIMO PARTIDO'
                      : 'ELEGÍ TU PRÓXIMA CANCHA',
                  style: const TextStyle(
                    color: ClubColors.lime,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NextReservation extends StatelessWidget {
  const _NextReservation({required this.reservation});

  final Reserva? reservation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _surfaceDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _Eyebrow('PRÓXIMA RESERVA')),
              if (reservation != null)
                Text(
                  _dateLabel(DateTime.parse(reservation!.fecha)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (reservation == null)
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: ClubColors.lime.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.sports_tennis,
                    color: ClubColors.olive,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Todavía no tenés una reserva',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontSize: 13),
                      ),
                      Text(
                        'Buscá disponibilidad en tus sedes',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward, size: 17),
              ],
            )
          else
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: ClubColors.lime.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.event_available_outlined,
                    color: ClubColors.olive,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reserva #${reservation!.id}',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontSize: 13),
                      ),
                      Text(
                        '${reservation!.horaInicio.substring(0, 5)} · ${reservation!.estado.toUpperCase()}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  reservation!.fecha,
                  style: const TextStyle(
                    color: ClubColors.olive,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          const Divider(height: 20),
          Text(
            reservation == null
                ? 'Elegí deporte y horario para ver canchas disponibles.'
                : 'Los detalles completos están en la sección Reservas.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _VenueCard extends StatelessWidget {
  const _VenueCard({
    required this.sede,
    required this.spaces,
    required this.onTap,
    this.compact = false,
    this.actionLabel,
  });

  final Sede sede;
  final List<EspacioDeportivo> spaces;
  final VoidCallback onTap;
  final bool compact;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final image = _venueImage(sede.nombre);
    return Material(
      color: Theme.of(context).cardColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: .7),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: compact ? 122 : 160,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Image.asset(
                      'assets/images/club-pitch.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 13,
                    right: 13,
                    bottom: 10,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sede.nombre.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                sede.direccion,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .55),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${spaces.length}',
                                style: const TextStyle(
                                  color: ClubColors.lime,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              const Text(
                                'canchas',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        for (final sport in _typesIn(
                          spaces,
                        ).take(compact ? 3 : 5))
                          _SportTag(sport),
                        if (spaces.isEmpty)
                          Text(
                            'Sin canchas cargadas',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 8),
                    Text(
                      actionLabel ?? 'VER CANCHAS',
                      style: const TextStyle(
                        color: ClubColors.olive,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward,
                      size: 14,
                      color: ClubColors.olive,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpaceResultCard extends StatelessWidget {
  const _SpaceResultCard({
    required this.space,
    required this.sede,
    required this.times,
    required this.selectedTime,
    required this.onTimeSelected,
    required this.onBook,
  });

  final EspacioDeportivo space;
  final Sede? sede;
  final List<String> times;
  final String selectedTime;
  final ValueChanged<String> onTimeSelected;
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _surfaceDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_tennis, color: ClubColors.lime, size: 22),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sede?.nombre ?? 'Sede',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      _prettySpace(space),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Text(
                'A CONSULTAR',
                style: TextStyle(
                  color: ClubColors.olive,
                  fontWeight: FontWeight.w900,
                  fontSize: 9,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          const _FieldLabel('HORARIOS LIBRES'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final time in times)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: _FilterChip(
                      label: time,
                      selected: time == selectedTime,
                      onTap: () => onTimeSelected(time),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onBook,
              style: FilledButton.styleFrom(
                backgroundColor: ClubColors.lime,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(40),
                padding: const EdgeInsets.symmetric(horizontal: 13),
              ),
              child: Text(
                'RESERVAR $selectedTime',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    required this.reservation,
    required this.space,
    required this.sede,
    this.onCancel,
    this.disabled = false,
  });

  final Reserva reservation;
  final EspacioDeportivo? space;
  final Sede? sede;
  final VoidCallback? onCancel;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _surfaceDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (sede?.nombre ?? 'RESERVA').toUpperCase(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _StatusPill(
                label: disabled ? 'CANCELADA' : 'ACTIVA',
                subdued: disabled,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoLine(
            label: 'Cancha',
            value: space == null
                ? 'Espacio ${reservation.espacioId}'
                : _prettySpace(space!),
          ),
          _InfoLine(
            label: 'Fecha',
            value: _dateLabel(DateTime.parse(reservation.fecha)),
          ),
          _InfoLine(
            label: 'Horario',
            value:
                '${reservation.horaInicio.substring(0, 5)} a ${reservation.horaFin.substring(0, 5)}',
          ),
          if (!disabled && onCancel != null) ...[
            const Divider(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(
                  Icons.close,
                  color: ClubColors.danger,
                  size: 17,
                ),
                label: const Text(
                  'Cancelar reserva',
                  style: TextStyle(
                    color: ClubColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 176,
      padding: const EdgeInsets.fromLTRB(20, 84, 20, 18),
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/club-pitch.png'),
          fit: BoxFit.cover,
        ),
        gradient: LinearGradient(colors: [Colors.transparent, Colors.black]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _Eyebrow(eyebrow),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 31,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ClubColors.danger.withValues(alpha: .12),
      child: InkWell(
        onTap: onRetry,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 17,
                color: ClubColors.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
              const Icon(Icons.refresh, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: ClubColors.lime,
        foregroundColor: Colors.black,
        disabledBackgroundColor: ClubColors.lime.withValues(alpha: .5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.black,
              ),
            )
          : Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: .3,
              ),
            ),
    ),
  );
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
      ),
    ),
  );
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(47),
      foregroundColor: ClubColors.olive,
      side: BorderSide(color: ClubColors.lime.withValues(alpha: .7)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
    showCheckmark: false,
    side: BorderSide(
      color: selected ? ClubColors.lime : Theme.of(context).dividerColor,
    ),
    backgroundColor: Theme.of(context).cardColor,
    selectedColor: ClubColors.lime,
    labelStyle: TextStyle(
      color: selected ? Colors.black : Theme.of(context).hintColor,
      fontWeight: FontWeight.w800,
      fontSize: 11,
    ),
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 5),
  );
}

class _SportTag extends StatelessWidget {
  const _SportTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: ClubColors.lime.withValues(alpha: .15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: ClubColors.olive,
        fontSize: 9,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, this.subdued = false});

  final String label;
  final bool subdued;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: (subdued ? Theme.of(context).hintColor : ClubColors.lime)
          .withValues(alpha: .16),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 8,
        color: subdued ? Theme.of(context).hintColor : ClubColors.olive,
        fontWeight: FontWeight.w900,
        letterSpacing: .4,
      ),
    ),
  );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: ClubColors.olive,
      fontSize: 9,
      letterSpacing: 2.1,
      fontWeight: FontWeight.w900,
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: ClubColors.olive,
        fontSize: 9,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    this.display,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T value)? display;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _FieldLabel(label),
      DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        items: values
            .map(
              (item) => DropdownMenuItem<T>(
                value: item,
                child: Text(
                  display?.call(item) ?? '$item',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(
      color: ClubColors.olive,
      fontSize: 10,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w900,
    ),
  );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    leading: Icon(icon, color: ClubColors.olive),
    title: Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14),
    ),
    subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    trailing: trailing ?? const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? action;
  final FutureOr<void> Function()? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38, color: ClubColors.olive),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (action != null && onAction != null) ...[
            const SizedBox(height: 17),
            _PrimaryButton(label: action!, onPressed: () => onAction!()),
          ],
        ],
      ),
    ),
  );
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    icon: Icon(icon, color: Colors.white),
    style: IconButton.styleFrom(
      backgroundColor: Colors.black.withValues(alpha: .28),
      side: BorderSide(color: Colors.white.withValues(alpha: .25)),
    ),
  );
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Divider(color: Colors.white.withValues(alpha: .2))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ),
      Expanded(child: Divider(color: Colors.white.withValues(alpha: .2))),
    ],
  );
}

InputDecoration _darkInput(String label, IconData icon) => InputDecoration(
  labelText: label,
  prefixIcon: Icon(icon, color: Colors.white54, size: 19),
  filled: true,
  fillColor: Colors.white.withValues(alpha: .11),
  labelStyle: const TextStyle(color: Colors.white60),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: BorderSide(color: Colors.white.withValues(alpha: .19)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: const BorderSide(color: ClubColors.lime),
  ),
);

ButtonStyle _outlinedButtonStyle(BuildContext context) =>
    OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    );

BoxDecoration _surfaceDecoration(BuildContext context) => BoxDecoration(
  color: Theme.of(context).cardColor,
  border: Border.all(
    color: Theme.of(context).dividerColor.withValues(alpha: .8),
  ),
  borderRadius: BorderRadius.circular(15),
);

List<String> _typesIn(List<EspacioDeportivo> spaces) =>
    spaces.map((space) => space.tipo).toSet().toList();

bool _matchesSport(String type, String sport) {
  final normalizedType = _normalize(type);
  final normalizedSport = _normalize(sport);
  if (normalizedSport == 'futbol') return normalizedType.contains('futbol');
  if (normalizedSport == 'tenis') return normalizedType.contains('tenis');
  if (normalizedSport == 'voley') return normalizedType.contains('voley');
  return normalizedType.contains(normalizedSport);
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ü', 'u');

String _prettySpace(EspacioDeportivo space) => space.nombreCompuesto
    .replaceAll('_', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _venueImage(String name) {
  final normalized = _normalize(name);
  if (normalized.contains('moron')) return 'assets/images/sede-moron.png';
  if (normalized.contains('ramos')) return 'assets/images/sede-ramos-mejia.png';
  if (normalized.contains('san justo')) {
    return 'assets/images/sede-san-justo.png';
  }
  if (normalized.contains('castelar')) return 'assets/images/sede-castelar.png';
  return 'assets/images/club-pitch.png';
}

List<String> _sports = const [
  'Todos',
  'Fútbol',
  'Tenis',
  'Golf',
  'Hockey',
  'Vóley',
];
const _sportTypes = [
  'Fútbol 5',
  'Fútbol 7',
  'Fútbol 11',
  'Tenis Polvo de Ladrillo',
  'Tenis Cemento',
  'Golf',
  'Hockey 7',
  'Hockey 11',
  'Vóley Indoor',
  'Vóley Playa',
];

Sede? _venueForReservation(
  Reserva reservation,
  List<EspacioDeportivo> spaces,
  List<Sede> sedes,
) {
  final space = spaces
      .where((item) => item.id == reservation.espacioId)
      .firstOrNull;
  if (space == null) return null;
  return sedes.where((venue) => venue.id == space.sedeId).firstOrNull;
}

Future<bool?> _confirmCancel(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Cancelar reserva'),
    content: const Text('¿Querés cancelar este turno?'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Volver'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        style: FilledButton.styleFrom(backgroundColor: ClubColors.danger),
        child: const Text('Cancelar reserva'),
      ),
    ],
  ),
);

Future<bool?> _confirmAction(
  BuildContext context,
  String title,
  String message,
) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Volver'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        style: FilledButton.styleFrom(backgroundColor: ClubColors.danger),
        child: const Text('Eliminar'),
      ),
    ],
  ),
);

void _notice(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Este campo es obligatorio' : null;

String _dateValue(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().padLeft(4, '0')}';

String _hourLabel(int hour) => '${hour.toString().padLeft(2, '0')}:00';
