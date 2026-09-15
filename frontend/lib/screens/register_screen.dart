import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nombreCtrl = TextEditingController();
  final TextEditingController _apellidoCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  DateTime? _fechaNacimiento;
  bool _loading = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _apellidoCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String? _notEmptyValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Campo requerido';
    return null;
  }

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email requerido';
    final pattern = RegExp(r"^[\w\.-]+@[\w\.-]+\.\w+");
    if (!pattern.hasMatch(v.trim())) return 'Email inválido';
    return null;
  }

  Future<void> _pickFecha() async {
    final now = DateTime.now();
    final initial = _fechaNacimiento ?? DateTime(now.year - 18, now.month, now.day);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _fechaNacimiento = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_fechaNacimiento == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seleccione fecha de nacimiento')));
      return;
    }

    setState(() => _loading = true);

    final uri = Uri.parse('http://10.0.2.2:8000/usuarios/');
    final body = {
      'nombre': _nombreCtrl.text.trim(),
      'apellido': _apellidoCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'fecha_nacimiento': _fechaNacimiento!.toIso8601String().split('T').first,
    };

    try {
      final resp = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cuenta creada correctamente')));
        // Optionally clear the form or navigate elsewhere
        _formKey.currentState!.reset();
        setState(() => _fechaNacimiento = null);
      } else {
        String msg = 'Error: ${resp.statusCode}';
        try {
          final decoded = jsonDecode(resp.body);
          if (decoded is Map && decoded['detail'] != null) msg = decoded['detail'].toString();
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error de red: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Widget _buildTextField({required String label, required TextEditingController controller, bool obscure = false, String? Function(String?)? validator, TextInputType? keyboardType}) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator ?? _notEmptyValidator,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTextField(label: 'Nombre', controller: _nombreCtrl),
              const SizedBox(height: 12),
              _buildTextField(label: 'Apellido', controller: _apellidoCtrl),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickFecha,
                child: AbsorbPointer(
                  child: TextFormField(
                    validator: (_) => _fechaNacimiento == null ? 'Fecha requerida' : null,
                    decoration: InputDecoration(
                      labelText: 'Fecha de nacimiento',
                      border: const OutlineInputBorder(),
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    controller: TextEditingController(text: _fechaNacimiento == null ? '' : '${_fechaNacimiento!.year}-${_fechaNacimiento!.month.toString().padLeft(2,'0')}-${_fechaNacimiento!.day.toString().padLeft(2,'0')}'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildTextField(label: 'Email', controller: _emailCtrl, keyboardType: TextInputType.emailAddress, validator: _emailValidator),
              const SizedBox(height: 12),
              _buildTextField(label: 'Contraseña', controller: _passwordCtrl, obscure: true, validator: _notEmptyValidator),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('CREAR CUENTA'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
