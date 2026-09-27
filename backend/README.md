# Backend · Club Jerónimo Zarlenga

API REST con FastAPI, SQLAlchemy y Firebase Admin SDK. Swagger/OpenAPI está disponible en `/docs` y el esquema OpenAPI JSON en `/openapi.json`.

## Requisitos

- Python 3.11 o superior.
- PostgreSQL para despliegue; SQLite se usa por defecto en desarrollo.
- Proyecto Firebase con Authentication por correo/contraseña habilitado.
- Cuenta de servicio de Firebase Admin para verificar ID tokens y enviar FCM.

## Desarrollo local

Desde `backend` en PowerShell:

```powershell
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
uvicorn main:app --reload
```

La API queda en `http://127.0.0.1:8000` y Swagger en `http://127.0.0.1:8000/docs`. Completá `.env` con el proyecto Firebase, la cuenta de servicio, tu UID administrador y `DATABASE_URL`. Nunca subas `.env` ni el JSON de la cuenta de servicio a GitHub.

Las tablas se crean al iniciar. Para bases existentes, el arranque aplica migraciones aditivas de `firebase_uid` e `is_admin` en `usuarios`; para cambios de esquema mayores, usá una migración versionada antes de desplegar.

## Seguridad y endpoints

- `GET /sedes/`, `GET /espacios/` y `GET /disponibilidad/` son consultas públicas.
- Registro, perfil, reservas, cancelación y dispositivos push requieren `Authorization: Bearer <Firebase ID token>`; para operar, el correo debe estar verificado.
- La API obtiene el usuario desde el UID del token. No acepta un `usuario_id` del cliente al crear reservas y limita consulta/cancelación al propietario.
- CRUD de sedes y espacios requiere un UID incluido en `ADMIN_UIDS` o un custom claim Firebase `admin: true`.
- `POST /usuarios/` solo permite crear/vincular el perfil al email verificado contenido en el token. El registro inicial puede sincronizar el perfil antes de verificar el correo, pero el resto de endpoints protegidos continúa bloqueado.
- Al crear una reserva se validan fecha futura, horas completas, duración mínima, horario de la sede y superposición. La respuesta `409` indica que la cancha ya fue ocupada.
- `GET /disponibilidad/?espacio_id=1&fecha=2027-01-12&duracion_horas=1` devuelve horas libres dentro del horario de la sede.
- Los recordatorios FCM se programan al crear una reserva para 24 horas y 1 hora antes. El proceso de la API ejecuta el despachador cada minuto; requiere que el usuario haya permitido notificaciones y registrado un token FCM.

## Pruebas

Con el entorno activo:

```powershell
.\venv\Scripts\python.exe -m unittest discover -s tests -v
```

Las pruebas usan SQLite aislado e incluyen autenticación obligatoria, disponibilidad, identidad al reservar y protección de reservas ajenas.

## Despliegue en Render

1. Crear PostgreSQL y un servicio web conectado al repositorio.
2. Usar `backend` como Root Directory.
3. Build command: `pip install -r requirements.txt`.
4. Start command: `uvicorn main:app --host 0.0.0.0 --port $PORT`.
5. Definir en Environment `DATABASE_URL`, `FIREBASE_PROJECT_ID`, `FIREBASE_SERVICE_ACCOUNT_JSON`, `ADMIN_UIDS` y `APP_TIMEZONE`. Guardar el JSON de servicio solo como variable secreta.
6. Configurar `CORS_ORIGINS` con orígenes web específicos si se usa Flutter Web.
7. Apuntar Flutter a la URL HTTPS pública de Render mediante `--dart-define=API_BASE_URL=...`.

La cuenta gratuita de una plataforma puede suspender servicios o limitar procesos en segundo plano. Para recordatorios fiables, alojá el scheduler en un proceso/worker que permanezca activo y usá PostgreSQL compartido. No arranques múltiples workers del scheduler sin locking distribuido, para evitar envíos duplicados.
