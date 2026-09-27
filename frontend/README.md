# Club Jerónimo Zarlenga

Aplicación Flutter móvil para consultar sedes, buscar horarios disponibles, reservar canchas y recibir recordatorios push.

## Configurar Firebase

1. Crear o abrir el proyecto Firebase del grupo.
2. En Authentication, habilitar el proveedor **Correo electrónico/Contraseña**. Firebase enviará el enlace de verificación y el correo para restablecer la contraseña.
3. Registrar una app Android con package ID `com.example.club_jeronimo_zarlenga` y una app iOS con bundle ID `com.example.clubJeronimoZarlenga` en la configuración actual del proyecto.
4. En Firebase Console, habilitar Firebase Cloud Messaging. Para iOS, configurar también la clave APNs en la sección de Cloud Messaging y habilitar Push Notifications en la cuenta Apple usada para firmar la app.
5. Copiar desde la configuración de cada app los valores `apiKey`, `projectId`, `messagingSenderId` y `mobilesdk_app_id` (en iOS, `GOOGLE_APP_ID`). El `iosBundleId` es `com.example.clubJeronimoZarlenga`.

El API key y los IDs de Firebase identifican el cliente; **no son la cuenta de servicio**. La clave privada Admin SDK solo va en el backend y nunca en Flutter.

## Ejecutar en Android

Iniciá primero el backend según [backend/README.md](../backend/README.md), luego desde esta carpeta:

```powershell
flutter pub get
flutter run
```

Android ya carga por defecto el proyecto Firebase registrado en `google-services.json` y en `lib/services/firebase_bootstrap.dart`. En Android Emulator, `10.0.2.2` apunta a la computadora anfitriona. Podés sobrescribir opciones de compilación con `--dart-define` si fuera necesario. El acceso de invitado permite leer sedes y disponibilidad, no crear reservas.

El proyecto iOS requiere registrar su propio bundle ID en Firebase y aportar su `appId` antes de ejecutar en iPhone.

Para un teléfono físico, reemplazá `API_BASE_URL` por la IP local de tu computadora y escuchá FastAPI en `0.0.0.0`. El firewall debe permitir el puerto. Android permite HTTP local solo en builds de depuración; los builds release requieren HTTPS.

## Flujos implementados

- Registro Email/Password en Firebase, perfil asociado al UID y verificación de correo obligatoria antes de entrar.
- Inicio de sesión Firebase y restablecimiento seguro de contraseña por correo.
- Sesión persistente, cierre de sesión, perfil y edición de nombre/apellido/fecha de nacimiento; el correo no es editable.
- Sedes, espacios y búsqueda real de horarios libres calculada por la API.
- Creación, listado, historial y cancelación de reservas con ownership verificado en el servidor.
- Modo claro/oscuro, notificaciones push FCM, registro/baja de token y recordatorios 24 h/1 h.
- Administración de sedes y canchas protegida por UID configurado en el backend.

La verificación de correo es una verificación de propiedad de la cuenta, **no un segundo factor MFA**. Si la evaluación exige dos factores estrictos, hay que habilitar MFA con SMS en Firebase Authentication with Identity Platform, preparar teléfonos de prueba/costos y agregar el flujo de segundo factor de Firebase. No se debe presentar la verificación de email como 2FA.

El icono launcher inicial se genera desde la fotografía de cancha incluida en Figma. Para regenerarlo después de cambiar la imagen:

```powershell
dart run flutter_launcher_icons
```

Se puede sustituir por el logo oficial del club cuando esté disponible.

## Pruebas y compilación

```powershell
flutter test
flutter analyze
flutter build apk --debug
```

La compilación con Firebase operativo necesita IDs reales de Android/iOS. Para una app de producción, configurar firma Android/iOS, HTTPS, App Store/Play Store y APNs.