import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiService {
  ApiService({http.Client? client, this.tokenProvider})
    : _client = client ?? http.Client();

  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  final http.Client _client;
  final Future<String?> Function()? tokenProvider;

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: query);
  }

  Future<List<Sede>> getSedes() async {
    final data = await _getList('/sedes/');
    return data.map(Sede.fromJson).toList();
  }

  Future<List<EspacioDeportivo>> getEspacios({
    int? sedeId,
    String? tipo,
  }) async {
    final query = <String, String>{};
    if (sedeId != null) query['sede_id'] = '$sedeId';
    if (tipo != null && tipo.isNotEmpty) query['tipo'] = tipo;
    final data = await _getList('/espacios/', query: query);
    return data.map(EspacioDeportivo.fromJson).toList();
  }

  Future<List<Reserva>> getReservas({int? usuarioId}) async {
    final data = await _getList('/reservas/');
    return data.map(Reserva.fromJson).toList();
  }

  Future<Usuario> getProfile() async {
    final data = await _request('GET', '/usuarios/me');
    return Usuario.fromJson(data as Map<String, dynamic>);
  }

  Future<Usuario> createUsuario({
    required String nombre,
    required String apellido,
    required String email,
    required String fechaNacimiento,
  }) async {
    final data = await _request(
      'POST',
      '/usuarios/',
      body: {
        'nombre': nombre,
        'apellido': apellido,
        'email': email,
        'fecha_nacimiento': fechaNacimiento,
      },
    );
    return Usuario.fromJson(data as Map<String, dynamic>);
  }

  Future<Usuario> updateProfile({
    required String nombre,
    required String apellido,
    required String fechaNacimiento,
  }) async {
    final data = await _request(
      'PUT',
      '/usuarios/me',
      body: {
        'nombre': nombre,
        'apellido': apellido,
        'fecha_nacimiento': fechaNacimiento,
      },
    );
    return Usuario.fromJson(data as Map<String, dynamic>);
  }

  Future<Sede> createSede({
    required String nombre,
    required String direccion,
    required String horaApertura,
    required String horaCierre,
  }) async {
    final data = await _request(
      'POST',
      '/sedes/',
      body: {
        'nombre': nombre,
        'direccion': direccion,
        'hora_apertura': horaApertura,
        'hora_cierre': horaCierre,
      },
    );
    return Sede.fromJson(data as Map<String, dynamic>);
  }

  Future<EspacioDeportivo> createEspacio({
    required int sedeId,
    required String tipo,
    required int numero,
  }) async {
    final data = await _request(
      'POST',
      '/espacios/',
      body: {'sede_id': sedeId, 'tipo': tipo, 'numero': numero},
    );
    return EspacioDeportivo.fromJson(data as Map<String, dynamic>);
  }

  Future<void> updateSede({
    required int sedeId,
    required String nombre,
    required String direccion,
    required String horaApertura,
    required String horaCierre,
  }) async {
    await _request(
      'PUT',
      '/sedes/$sedeId',
      body: {
        'nombre': nombre,
        'direccion': direccion,
        'hora_apertura': horaApertura,
        'hora_cierre': horaCierre,
      },
    );
  }

  Future<void> deleteSede(int sedeId) async {
    await _request('DELETE', '/sedes/$sedeId');
  }

  Future<void> updateEspacio({
    required int espacioId,
    required int sedeId,
    required String tipo,
    required int numero,
  }) async {
    await _request(
      'PUT',
      '/espacios/$espacioId',
      body: {'sede_id': sedeId, 'tipo': tipo, 'numero': numero},
    );
  }

  Future<void> deleteEspacio(int espacioId) async {
    await _request('DELETE', '/espacios/$espacioId');
  }

  Future<List<String>> getAvailableTimes({
    required int espacioId,
    required String fecha,
    required int durationHours,
  }) async {
    final data =
        await _request(
              'GET',
              '/disponibilidad/',
              query: {
                'espacio_id': '$espacioId',
                'fecha': fecha,
                'duracion_horas': '$durationHours',
              },
            )
            as Map<String, dynamic>;
    return (data['horarios'] as List<dynamic>)
        .map((value) => value.toString().substring(0, 5))
        .toList();
  }

  Future<void> registerNotificationToken(String token) async {
    await _request(
      'POST',
      '/notificaciones/dispositivo',
      body: {'token': token},
    );
  }

  Future<void> unregisterNotificationToken(String token) async {
    await _request(
      'DELETE',
      '/notificaciones/dispositivo',
      query: {'token': token},
    );
  }

  Future<Reserva> createReserva({
    required int espacioId,
    required String fecha,
    required String horaInicio,
    required String horaFin,
  }) async {
    final data = await _request(
      'POST',
      '/reservas/',
      body: {
        'espacio_id': espacioId,
        'fecha': fecha,
        'hora_inicio': horaInicio,
        'hora_fin': horaFin,
      },
    );
    return Reserva.fromJson(data as Map<String, dynamic>);
  }

  Future<Reserva> cancelReserva(int reservaId) async {
    final data = await _request('PUT', '/reservas/$reservaId/cancelar');
    return Reserva.fromJson(data as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> _getList(
    String path, {
    Map<String, String>? query,
  }) async {
    final data = await _request('GET', path, query: query);
    return (data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    try {
      final uri = _uri(path, query);
      final token = await tokenProvider?.call();
      final headers = <String, String>{
        if (body != null) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      late final http.Response response;
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers);
        case 'POST':
          response = await _client.post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          );
        case 'PUT':
          response = await _client.put(
            uri,
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          );
        case 'DELETE':
          response = await _client.delete(uri, headers: headers);
        default:
          throw ArgumentError.value(method, 'method', 'Método no soportado');
      }

      final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded is Map<String, dynamic>
            ? decoded['detail']?.toString()
            : null;
        throw ApiException(
          detail ?? 'El servidor respondió con estado ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on FormatException {
      throw const ApiException('El servidor devolvió una respuesta inválida.');
    } catch (error) {
      throw ApiException('No se pudo conectar con el servidor: $error');
    }
  }

  void close() => _client.close();
}

class Sede {
  const Sede({
    required this.id,
    required this.nombre,
    required this.direccion,
    required this.horaApertura,
    required this.horaCierre,
  });

  final int id;
  final String nombre;
  final String direccion;
  final String horaApertura;
  final String horaCierre;

  factory Sede.fromJson(Map<String, dynamic> json) => Sede(
    id: json['id'] as int,
    nombre: json['nombre'] as String,
    direccion: json['direccion'] as String,
    horaApertura: json['hora_apertura'] as String,
    horaCierre: json['hora_cierre'] as String,
  );
}

class EspacioDeportivo {
  const EspacioDeportivo({
    required this.id,
    required this.sedeId,
    required this.tipo,
    required this.nombreCompuesto,
  });

  final int id;
  final int sedeId;
  final String tipo;
  final String nombreCompuesto;

  factory EspacioDeportivo.fromJson(Map<String, dynamic> json) =>
      EspacioDeportivo(
        id: json['id'] as int,
        sedeId: json['sede_id'] as int,
        tipo: json['tipo'] as String,
        nombreCompuesto: json['nombre_compuesto'] as String,
      );
}

class Usuario {
  const Usuario({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.email,
    this.fechaNacimiento,
    this.isAdmin = false,
  });

  final int id;
  final String nombre;
  final String apellido;
  final String email;
  final String? fechaNacimiento;
  final bool isAdmin;

  factory Usuario.fromJson(Map<String, dynamic> json) => Usuario(
    id: json['id'] as int,
    nombre: json['nombre'] as String,
    apellido: json['apellido'] as String,
    email: json['email'] as String,
    fechaNacimiento: json['fecha_nacimiento'] as String?,
    isAdmin: json['is_admin'] as bool? ?? false,
  );
}

class Reserva {
  const Reserva({
    required this.id,
    required this.usuarioId,
    required this.espacioId,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.estado,
  });

  final int id;
  final int usuarioId;
  final int espacioId;
  final String fecha;
  final String horaInicio;
  final String horaFin;
  final String estado;

  factory Reserva.fromJson(Map<String, dynamic> json) => Reserva(
    id: json['id'] as int,
    usuarioId: json['usuario_id'] as int,
    espacioId: json['espacio_id'] as int,
    fecha: json['fecha'] as String,
    horaInicio: json['hora_inicio'] as String,
    horaFin: json['hora_fin'] as String,
    estado: json['estado'] as String,
  );
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
