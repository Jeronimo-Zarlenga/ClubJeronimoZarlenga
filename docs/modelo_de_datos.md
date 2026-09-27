# Modelo de datos

El backend usa una base relacional. Firebase Authentication guarda las credenciales; la base local relaciona cada perfil con el UID Firebase y conserva los datos de negocio.

```mermaid
erDiagram
    USUARIO ||--o{ RESERVA : realiza
    USUARIO ||--o{ DISPOSITIVO_NOTIFICACION : registra
    SEDE ||--o{ ESPACIO_DEPORTIVO : contiene
    ESPACIO_DEPORTIVO ||--o{ RESERVA : recibe
    RESERVA ||--o{ RECORDATORIO : programa

    USUARIO {
        int id PK
        string firebase_uid UK
        string email UK
        string nombre
        string apellido
        date fecha_nacimiento
        boolean is_admin
        datetime created_at
    }
    SEDE {
        int id PK
        string nombre
        string direccion
        time hora_apertura
        time hora_cierre
    }
    ESPACIO_DEPORTIVO {
        int id PK
        int sede_id FK
        string tipo
        string nombre_compuesto UK
    }
    RESERVA {
        int id PK
        int usuario_id FK
        int espacio_id FK
        date fecha
        time hora_inicio
        time hora_fin
        string estado
        datetime created_at
    }
    DISPOSITIVO_NOTIFICACION {
        int id PK
        int usuario_id FK
        string token
        datetime updated_at
    }
    RECORDATORIO {
        int id PK
        int reserva_id FK
        string kind
        datetime scheduled_at
        datetime sent_at
    }
```

## Reglas de relación

- `usuario.firebase_uid` vincula el perfil de la aplicación al usuario autenticado de Firebase; la contraseña nunca se almacena en esta base.
- El email identifica el perfil, pero no se modifica desde el endpoint de edición del perfil.
- `espacio_deportivo.nombre_compuesto` se construye con nombre de sede, dirección, tipo y número. Al renombrar una sede, se recalculan los nombres compuestos.
- Cada reserva pertenece a un perfil y a un único espacio deportivo. La API asigna `usuario_id` a partir del Firebase ID token.
- Cada dispositivo pertenece a un usuario. `token` se usa solo para entrega FCM y se elimina al cerrar sesión o cuando Firebase informa que dejó de ser válido.
- Cada recordatorio pertenece a una reserva y es único por tipo (`24h` o `1h`). Las reservas canceladas no generan notificaciones.
