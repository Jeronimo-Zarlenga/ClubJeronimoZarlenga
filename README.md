# ClubJeronimoZarlenga

Aplicación móvil y API REST para gestionar sedes, espacios deportivos y reservas del Club Jerónimo Zarlenga.

## Componentes

- `frontend/`: app móvil Flutter, Firebase Authentication y Firebase Cloud Messaging.
- `backend/`: API FastAPI, SQLAlchemy y PostgreSQL/SQLite.
- [Modelo de datos](docs/modelo_de_datos.md): entidades y relaciones relacionales.

## Puesta en marcha

1. Configurá Firebase Authentication Email/Password y Firebase Cloud Messaging. Instrucciones y valores Flutter: [frontend/README.md](frontend/README.md).
2. Configurá `backend/.env` tomando como referencia [backend/.env.example](backend/.env.example), instalá `backend/requirements.txt` e iniciá `uvicorn main:app --reload` desde `backend`.
3. Iniciá Flutter desde `frontend` con los `--dart-define` de Firebase/API. En Android Emulator la URL local del backend es `http://10.0.2.2:8000`.
4. Abrí `http://127.0.0.1:8000/docs` para consultar Swagger/OpenAPI.

Los endpoints de reservas y perfil requieren Firebase ID tokens; las operaciones administrativas además requieren un UID en `ADMIN_UIDS` o un custom claim `admin: true`. No guardes credenciales de Firebase Admin en el repositorio.

## Validación local

```powershell
cd backend
.\venv\Scripts\python.exe -m unittest discover -s tests -v
cd ..\frontend
flutter analyze
flutter test
```
