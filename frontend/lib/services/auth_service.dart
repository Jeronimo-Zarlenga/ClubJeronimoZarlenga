import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_bootstrap.dart';

class AuthService {
  FirebaseAuth get _auth {
    if (!FirebaseBootstrap.isConfigured) {
      throw const AuthException(
        'Falta configurar Firebase. Consultá frontend/README.md para conectar tu proyecto.',
      );
    }
    return FirebaseAuth.instance;
  }

  User? get currentUser =>
      FirebaseBootstrap.isConfigured ? FirebaseAuth.instance.currentUser : null;

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw AuthException(_messageFor(error));
    }
  }

  Future<UserCredential> register({
    required String email,
    required String password,
    required String nombre,
    required String apellido,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await credential.user?.updateDisplayName('$nombre $apellido');
      await credential.user?.sendEmailVerification();
      return credential;
    } on FirebaseAuthException catch (error) {
      throw AuthException(_messageFor(error));
    }
  }

  Future<void> sendVerificationEmail() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
    } on FirebaseAuthException catch (error) {
      throw AuthException(_messageFor(error));
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      throw AuthException(_messageFor(error));
    }
  }

  Future<User?> reloadCurrentUser() async {
    try {
      final user = _auth.currentUser;
      await user?.reload();
      return _auth.currentUser;
    } on FirebaseAuthException catch (error) {
      throw AuthException(_messageFor(error));
    }
  }

  Future<void> signOut() async {
    if (!FirebaseBootstrap.isConfigured) return;
    await FirebaseAuth.instance.signOut();
  }

  Future<String?> getIdToken() async {
    if (!FirebaseBootstrap.isConfigured) return null;
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  String _messageFor(FirebaseAuthException error) => switch (error.code) {
    'invalid-email' => 'El correo no tiene un formato válido.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => 'El correo o la contraseña son incorrectos.',
    'email-already-in-use' => 'Ya existe una cuenta con ese correo.',
    'weak-password' => 'Elegí una contraseña de al menos 8 caracteres.',
    'too-many-requests' =>
      'Hubo demasiados intentos. Esperá unos minutos y volvé a probar.',
    'network-request-failed' =>
      'No hay conexión. Revisá internet e intentá nuevamente.',
    'operation-not-allowed' =>
      'Activá Email/Password en los proveedores de autenticación de Firebase.',
    _ => error.message ?? 'No se pudo completar la autenticación.',
  };
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
