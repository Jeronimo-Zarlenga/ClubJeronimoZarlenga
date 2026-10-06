import os
import re
from contextlib import asynccontextmanager
from datetime import date, datetime, time, timedelta
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import Depends, FastAPI, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

import models
import schemas
from database import Base, engine, get_db, upgrade_schema
from notifications import send_due_reminders, start_scheduler, stop_scheduler
from security import (
    current_user,
    is_admin_token,
    require_admin,
    verify_firebase_signup_token,
    verify_firebase_token,
)

Base.metadata.create_all(bind=engine)
upgrade_schema()
app_timezone = ZoneInfo(os.getenv("APP_TIMEZONE", "America/Argentina/Buenos_Aires"))


@asynccontextmanager
async def lifespan(_: FastAPI):
    start_scheduler()
    yield
    stop_scheduler()


app = FastAPI(
    title="Club Jerónimo Zarlenga API",
    description=(
        "API REST para gestión de usuarios, sedes, espacios deportivos y reservas. "
        "Los endpoints protegidos reciben Firebase ID tokens como Bearer token."
    ),
    version="2.0.0",
    lifespan=lifespan,
)

origins = [origin.strip() for origin in os.getenv("CORS_ORIGINS", "*").split(",") if origin.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)


def _not_found(entity: str) -> HTTPException:
    return HTTPException(status_code=404, detail=f"No se encontró {entity}.")


def _space_name(venue: models.Sede, space_type: str, number: int) -> str:
    if number < 1:
        raise HTTPException(status_code=422, detail="El número de cancha debe ser al menos 1.")
    normalized_type = space_type.strip()
    if not normalized_type or not all(
        character.isalnum() or character in "_ " for character in normalized_type
    ):
        raise HTTPException(status_code=422, detail="El tipo de deporte contiene caracteres no permitidos.")
    parts = [venue.nombre, venue.direccion, normalized_type, str(number)]
    name = re.sub(r"[^\w]+", "_", "_".join(parts), flags=re.UNICODE).strip("_")
    if not name or not re.fullmatch(r"[\w]+(?:_[\w]+)+", name, flags=re.UNICODE):
        raise HTTPException(status_code=422, detail="El nombre compuesto no cumple el formato requerido.")
    return name


def _get_space(db: Session, space_id: int) -> models.EspacioDeportivo:
    space = db.query(models.EspacioDeportivo).filter(models.EspacioDeportivo.id == space_id).first()
    if space is None:
        raise _not_found("el espacio deportivo")
    return space


def _available_starts(
    db: Session,
    space: models.EspacioDeportivo,
    requested_date: date,
    duration_hours: int,
) -> list[time]:
    venue = space.sede
    opening = datetime.combine(requested_date, venue.hora_apertura)
    closing = datetime.combine(requested_date, venue.hora_cierre)
    now = datetime.now(app_timezone).replace(tzinfo=None)
    duration = timedelta(hours=duration_hours)
    if closing <= opening or duration > closing - opening:
        return []

    reservations = (
        db.query(models.Reserva)
        .filter(
            models.Reserva.espacio_id == space.id,
            models.Reserva.fecha == requested_date,
            models.Reserva.estado == "activa",
        )
        .all()
    )
    occupied = [
        (datetime.combine(requested_date, item.hora_inicio), datetime.combine(requested_date, item.hora_fin))
        for item in reservations
    ]

    starts: list[time] = []
    candidate = opening.replace(minute=0, second=0, microsecond=0)
    if candidate < opening:
        candidate += timedelta(hours=1)
    while candidate + duration <= closing:
        finishes = candidate + duration
        if candidate > now and all(candidate >= end or finishes <= start for start, end in occupied):
            starts.append(candidate.time())
        candidate += timedelta(hours=1)
    return starts


@app.get("/", tags=["Health Check"])
def read_root():
    return {"status": "online", "app": "Club Jerónimo Zarlenga", "message": "API disponible"}


@app.get("/health", tags=["Health Check"])
def health_check():
    return {"status": "healthy"}


@app.get("/sedes/", response_model=list[schemas.SedeResponse], tags=["Sedes"])
def listar_sedes(db: Session = Depends(get_db)):
    return db.query(models.Sede).order_by(models.Sede.nombre).all()


@app.post(
    "/sedes/",
    response_model=schemas.SedeResponse,
    status_code=status.HTTP_201_CREATED,
    tags=["Sedes"],
    dependencies=[Depends(require_admin)],
)
def crear_sede(sede: schemas.SedeCreate, db: Session = Depends(get_db)):
    if sede.hora_cierre <= sede.hora_apertura:
        raise HTTPException(status_code=422, detail="El cierre debe ser posterior a la apertura.")
    db_sede = models.Sede(**sede.model_dump())
    db.add(db_sede)
    db.commit()
    db.refresh(db_sede)
    return db_sede


@app.put(
    "/sedes/{sede_id}",
    response_model=schemas.SedeResponse,
    tags=["Sedes"],
    dependencies=[Depends(require_admin)],
)
def actualizar_sede(sede_id: int, cambios: schemas.SedeCreate, db: Session = Depends(get_db)):
    sede = db.query(models.Sede).filter(models.Sede.id == sede_id).first()
    if sede is None:
        raise _not_found("la sede")
    if cambios.hora_cierre <= cambios.hora_apertura:
        raise HTTPException(status_code=422, detail="El cierre debe ser posterior a la apertura.")
    for field, value in cambios.model_dump().items():
        setattr(sede, field, value)
    for space in sede.espacios:
        number = space.nombre_compuesto.rsplit("_", 1)[-1]
        if number.isdigit():
            space.nombre_compuesto = _space_name(sede, space.tipo, int(number))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Los cambios generarían el mismo nombre compuesto que otra cancha.",
        ) from None
    db.refresh(sede)
    return sede


@app.delete(
    "/sedes/{sede_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    tags=["Sedes"],
    dependencies=[Depends(require_admin)],
)
def eliminar_sede(sede_id: int, db: Session = Depends(get_db)):
    sede = db.query(models.Sede).filter(models.Sede.id == sede_id).first()
    if sede is None:
        raise _not_found("la sede")
    if sede.espacios:
        raise HTTPException(status_code=409, detail="No se puede eliminar una sede que contiene espacios deportivos.")
    db.delete(sede)
    db.commit()


@app.get("/espacios/", response_model=list[schemas.EspacioDeportivoResponse], tags=["Espacios Deportivos"])
def listar_espacios(
    sede_id: int | None = None,
    tipo: str | None = None,
    db: Session = Depends(get_db),
):
    query = db.query(models.EspacioDeportivo)
    if sede_id is not None:
        query = query.filter(models.EspacioDeportivo.sede_id == sede_id)
    if tipo:
        query = query.filter(models.EspacioDeportivo.tipo.ilike(f"%{tipo}%"))
    return query.order_by(models.EspacioDeportivo.tipo, models.EspacioDeportivo.nombre_compuesto).all()


@app.post(
    "/espacios/",
    response_model=schemas.EspacioDeportivoResponse,
    status_code=status.HTTP_201_CREATED,
    tags=["Espacios Deportivos"],
    dependencies=[Depends(require_admin)],
)
def crear_espacio_deportivo(espacio: schemas.EspacioDeportivoBase, db: Session = Depends(get_db)):
    sede = db.query(models.Sede).filter(models.Sede.id == espacio.sede_id).first()
    if sede is None:
        raise _not_found("la sede especificada")
    db_espacio = models.EspacioDeportivo(
        sede_id=sede.id,
        tipo=espacio.tipo.strip(),
        nombre_compuesto=_space_name(sede, espacio.tipo.strip(), espacio.numero),
    )
    db.add(db_espacio)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Ya existe una cancha con ese tipo y número en la sede.") from None
    db.refresh(db_espacio)
    return db_espacio


@app.put(
    "/espacios/{espacio_id}",
    response_model=schemas.EspacioDeportivoResponse,
    tags=["Espacios Deportivos"],
    dependencies=[Depends(require_admin)],
)
def actualizar_espacio(
    espacio_id: int,
    cambios: schemas.EspacioDeportivoUpdate,
    db: Session = Depends(get_db),
):
    espacio = _get_space(db, espacio_id)
    sede = db.query(models.Sede).filter(models.Sede.id == cambios.sede_id).first()
    if sede is None:
        raise _not_found("la sede especificada")
    espacio.sede_id = sede.id
    espacio.tipo = cambios.tipo.strip()
    espacio.nombre_compuesto = _space_name(sede, cambios.tipo.strip(), cambios.numero)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Ya existe una cancha con ese tipo y número en la sede.") from None
    db.refresh(espacio)
    return espacio


@app.delete(
    "/espacios/{espacio_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    tags=["Espacios Deportivos"],
    dependencies=[Depends(require_admin)],
)
def eliminar_espacio(espacio_id: int, db: Session = Depends(get_db)):
    espacio = _get_space(db, espacio_id)
    if espacio.reservas:
        raise HTTPException(status_code=409, detail="No se puede eliminar una cancha que tiene historial de reservas.")
    db.delete(espacio)
    db.commit()


@app.get("/disponibilidad/", tags=["Disponibilidad"])
def consultar_disponibilidad(
    espacio_id: int,
    fecha: date,
    duracion_horas: Annotated[int, Query(ge=1, le=6)] = 1,
    db: Session = Depends(get_db),
):
    espacio = _get_space(db, espacio_id)
    return {
        "espacio_id": espacio.id,
        "sede_id": espacio.sede_id,
        "fecha": fecha,
        "duracion_horas": duracion_horas,
        "horarios": _available_starts(db, espacio, fecha, duracion_horas),
    }


@app.post(
    "/reservas/",
    response_model=schemas.ReservaResponse,
    status_code=status.HTTP_201_CREATED,
    tags=["Reservas"],
)
def crear_reserva(
    reserva: schemas.ReservaCreate,
    user: models.Usuario = Depends(current_user),
    db: Session = Depends(get_db),
):
    start = datetime.combine(reserva.fecha, reserva.hora_inicio)
    finish = datetime.combine(reserva.fecha, reserva.hora_fin)
    if reserva.hora_inicio.second or reserva.hora_inicio.minute or reserva.hora_fin.second or reserva.hora_fin.minute:
        raise HTTPException(status_code=422, detail="Los horarios deben comenzar y finalizar en punto.")
    if finish - start < timedelta(hours=1):
        raise HTTPException(status_code=422, detail="La duración mínima de la reserva es de una hora.")
    if start <= datetime.now(app_timezone).replace(tzinfo=None):
        raise HTTPException(status_code=422, detail="Las reservas deben realizarse para fechas y horarios futuros.")

    space = (
        db.query(models.EspacioDeportivo)
        .filter(models.EspacioDeportivo.id == reserva.espacio_id)
        .with_for_update()
        .first()
    )
    if space is None:
        raise _not_found("el espacio deportivo")
    venue = space.sede
    if reserva.hora_inicio < venue.hora_apertura or reserva.hora_fin > venue.hora_cierre:
        raise HTTPException(
            status_code=422,
            detail=f"El horario debe estar dentro del funcionamiento de la sede ({venue.hora_apertura:%H:%M} a {venue.hora_cierre:%H:%M}).",
        )

    overlap = db.query(models.Reserva).filter(
        models.Reserva.espacio_id == space.id,
        models.Reserva.fecha == reserva.fecha,
        models.Reserva.estado == "activa",
        models.Reserva.hora_inicio < reserva.hora_fin,
        models.Reserva.hora_fin > reserva.hora_inicio,
    ).first()
    if overlap:
        raise HTTPException(status_code=409, detail="La cancha ya está reservada en ese rango horario.")

    booking = models.Reserva(
        usuario_id=user.id,
        espacio_id=space.id,
        fecha=reserva.fecha,
        hora_inicio=reserva.hora_inicio,
        hora_fin=reserva.hora_fin,
        estado="activa",
    )
    db.add(booking)
    db.flush()
    now = datetime.now(app_timezone).replace(tzinfo=None)
    for kind, lead_time in (("24h", timedelta(hours=24)), ("1h", timedelta(hours=1))):
        scheduled_at = start - lead_time
        if scheduled_at > now:
            db.add(models.ReservationReminder(reserva_id=booking.id, kind=kind, scheduled_at=scheduled_at))
    db.commit()
    db.refresh(booking)
    return booking


@app.get("/reservas/", response_model=list[schemas.ReservaResponse], tags=["Reservas"])
def listar_reservas(user: models.Usuario = Depends(current_user), db: Session = Depends(get_db)):
    return (
        db.query(models.Reserva)
        .filter(models.Reserva.usuario_id == user.id)
        .order_by(models.Reserva.fecha.desc(), models.Reserva.hora_inicio.desc())
        .all()
    )


@app.put("/reservas/{reserva_id}/cancelar", response_model=schemas.ReservaResponse, tags=["Reservas"])
def cancelar_reserva(
    reserva_id: int,
    user: models.Usuario = Depends(current_user),
    db: Session = Depends(get_db),
):
    booking = db.query(models.Reserva).filter(
        models.Reserva.id == reserva_id,
        models.Reserva.usuario_id == user.id,
    ).first()
    if booking is None:
        raise _not_found("la reserva")
    if booking.estado == "cancelada":
        raise HTTPException(status_code=409, detail="La reserva ya se encuentra cancelada.")
    booking.estado = "cancelada"
    db.commit()
    db.refresh(booking)
    return booking


@app.post(
    "/usuarios/",
    response_model=schemas.UsuarioResponse,
    status_code=status.HTTP_201_CREATED,
    tags=["Usuarios"],
)
def registrar_perfil(
    profile: schemas.UsuarioCreate,
    token: dict = Depends(verify_firebase_signup_token),
    db: Session = Depends(get_db),
):
    email = token["email"].strip().lower()
    if profile.email.lower() != email:
        raise HTTPException(status_code=403, detail="El correo del perfil debe coincidir con el correo verificado de Firebase.")
    user = db.query(models.Usuario).filter(models.Usuario.firebase_uid == token["uid"]).first()
    if user is None:
        user = db.query(models.Usuario).filter(models.Usuario.email == email).first()
        if user is not None and user.firebase_uid not in (None, token["uid"]):
            raise HTTPException(status_code=409, detail="El correo ya está vinculado a otra cuenta.")
    if user is None:
        user = models.Usuario(firebase_uid=token["uid"], email=email, **profile.model_dump(exclude={"email"}))
        db.add(user)
    else:
        user.firebase_uid = token["uid"]
        user.email = email
        user.nombre = profile.nombre
        user.apellido = profile.apellido
        user.fecha_nacimiento = profile.fecha_nacimiento
    user.is_admin = is_admin_token(token)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Ya existe una cuenta con ese correo.") from None
    db.refresh(user)
    return user


@app.get("/usuarios/me", response_model=schemas.UsuarioResponse, tags=["Usuarios"])
def obtener_perfil(user: models.Usuario = Depends(current_user)):
    return user


@app.put("/usuarios/me", response_model=schemas.UsuarioResponse, tags=["Usuarios"])
def actualizar_perfil(
    changes: schemas.UsuarioUpdate,
    user: models.Usuario = Depends(current_user),
    db: Session = Depends(get_db),
):
    user.nombre = changes.nombre.strip()
    user.apellido = changes.apellido.strip()
    user.fecha_nacimiento = changes.fecha_nacimiento
    db.commit()
    db.refresh(user)
    return user


@app.post("/notificaciones/dispositivo", status_code=status.HTTP_204_NO_CONTENT, tags=["Notificaciones"])
def registrar_dispositivo(
    device: schemas.NotificationDeviceCreate,
    user: models.Usuario = Depends(current_user),
    db: Session = Depends(get_db),
):
    existing = db.query(models.NotificationDevice).filter(models.NotificationDevice.token == device.token).first()
    if existing is not None:
        existing.usuario_id = user.id
        existing.updated_at = models.utc_now_naive()
    else:
        db.add(models.NotificationDevice(usuario_id=user.id, token=device.token))
    db.commit()


@app.delete("/notificaciones/dispositivo", status_code=status.HTTP_204_NO_CONTENT, tags=["Notificaciones"])
def eliminar_dispositivo(
    token: str = Query(min_length=1),
    user: models.Usuario = Depends(current_user),
    db: Session = Depends(get_db),
):
    db.query(models.NotificationDevice).filter(
        models.NotificationDevice.usuario_id == user.id,
        models.NotificationDevice.token == token,
    ).delete(synchronize_session=False)
    db.commit()


@app.post("/admin/notificaciones/procesar", include_in_schema=False)
def procesar_notificaciones(token: dict = Depends(require_admin)):
    send_due_reminders()
    return {"status": "processed"}