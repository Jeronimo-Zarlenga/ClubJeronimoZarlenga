from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime, date, time
from database import engine, Base, get_db

import models
import schemas

# Creación de tablas
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Club Jerónimo Zarlenga API",
    description="API REST para la gestión de espacios deportivos, reservas, sedes y usuarios.",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/", tags=["Health Check"])
def read_root():
    return {
        "status": "online",
        "app": "Club Jerónimo Zarlenga",
        "message": "Bienvenido a la API de Gestión de Espacios Deportivos"
    }

# ===============================
# ENDPOINTS: SEDES
# ===============================
@app.post("/sedes/", response_model=schemas.SedeResponse, status_code=status.HTTP_201_CREATED, tags=["Sedes"])
def crear_sede(sede: schemas.SedeCreate, db: Session = Depends(get_db)):
    db_sede = models.Sede(**sede.model_dump())
    db.add(db_sede)
    db.commit()
    db.refresh(db_sede)
    return db_sede

@app.get("/sedes/", response_model=List[schemas.SedeResponse], tags=["Sedes"])
def listar_sedes(db: Session = Depends(get_db)):
    return db.query(models.Sede).all()

# ===============================
# ENDPOINTS: ESPACIOS DEPORTIVOS
# ===============================
@app.post("/espacios/", response_model=schemas.EspacioDeportivoResponse, status_code=status.HTTP_201_CREATED, tags=["Espacios Deportivos"])
def crear_espacio_deportivo(espacio: schemas.EspacioDeportivoBase, db: Session = Depends(get_db)):
    sede = db.query(models.Sede).filter(models.Sede.id == espacio.sede_id).first()
    if not sede:
        raise HTTPException(status_code=404, detail="La sede especificada no existe.")

    # Generación del nombre compuesto reglamentario: Sede_Direccion_Tipo_Numero
    sede_clean = sede.nombre.replace(" ", "_")
    dir_clean = sede.direccion.replace(" ", "_")
    tipo_clean = espacio.tipo.replace(" ", "_")
    nombre_compuesto = f"{sede_clean}_{dir_clean}_{tipo_clean}_{espacio.numero}"

    # Validar que no exista un duplicado
    existe = db.query(models.EspacioDeportivo).filter(models.EspacioDeportivo.nombre_compuesto == nombre_compuesto).first()
    if existe:
        raise HTTPException(status_code=400, detail="Este espacio deportivo ya está registrado con ese nombre compuesto.")

    db_espacio = models.EspacioDeportivo(
        sede_id=espacio.sede_id,
        tipo=espacio.tipo,
        nombre_compuesto=nombre_compuesto
    )
    db.add(db_espacio)
    db.commit()
    db.refresh(db_espacio)
    return db_espacio

@app.get("/espacios/", response_model=List[schemas.EspacioDeportivoResponse], tags=["Espacios Deportivos"])
def listar_espacios(sede_id: Optional[int] = None, tipo: Optional[str] = None, db: Session = Depends(get_db)):
    query = db.query(models.EspacioDeportivo)
    if sede_id:
        query = query.filter(models.EspacioDeportivo.sede_id == sede_id)
    if tipo:
        query = query.filter(models.EspacioDeportivo.tipo.ilike(f"%{tipo}%"))
    return query.all()

# ===============================
# ENDPOINTS: RESERVAS
# ===============================

@app.post("/reservas/", response_model=schemas.ReservaResponse, status_code=status.HTTP_201_CREATED, tags=["Reservas"])
def crear_reserva(reserva: schemas.ReservaCreate, db: Session = Depends(get_db)):
    # 1. Validar que la hora comience y termine en el minuto :00
    if reserva.hora_inicio.minute != 0 or reserva.hora_inicio.second != 0:
        raise HTTPException(status_code=400, detail="La hora de inicio debe ser en punto (minuto 00).")
    if reserva.hora_fin.minute != 0 or reserva.hora_fin.second != 0:
        raise HTTPException(status_code=400, detail="La hora de fin debe ser en punto (minuto 00).")

    # 2. Validar duración mínima de 1 hora y coherencia de horarios
    if reserva.hora_fin <= reserva.hora_inicio:
        raise HTTPException(status_code=400, detail="La hora de finalización debe ser posterior a la hora de inicio.")
    
    duracion_horas = reserva.hora_fin.hour - reserva.hora_inicio.hour
    if duracion_horas < 1:
        raise HTTPException(status_code=400, detail="La duración mínima de la reserva es de 1 hora.")

    # 3. Validar que la fecha y hora sean futuras
    ahora = datetime.now()
    fecha_hora_reserva = datetime.combine(reserva.fecha, reserva.hora_inicio)
    if fecha_hora_reserva <= ahora:
        raise HTTPException(status_code=400, detail="Las reservas deben realizarse para fechas y horarios futuros.")

    # 4. Validar existencia del espacio deportivo y horarios de la sede
    espacio = db.query(models.EspacioDeportivo).filter(models.EspacioDeportivo.id == reserva.espacio_id).first()
    if not espacio:
        raise HTTPException(status_code=404, detail="El espacio deportivo indicado no existe.")
    
    sede = espacio.sede
    if reserva.hora_inicio < sede.hora_apertura or reserva.hora_fin > sede.hora_cierre:
        raise HTTPException(
            status_code=400, 
            detail=f"La reserva está fuera del horario de funcionamiento de la sede ({sede.hora_apertura} a {sede.hora_cierre})."
        )

    # 5. Validar superposición de turnos para el mismo espacio deportivo
    # Solapamiento: (InicioA < FinB) y (FinA > InicioB)
    solapada = db.query(models.Reserva).filter(
        models.Reserva.espacio_id == reserva.espacio_id,
        models.Reserva.fecha == reserva.fecha,
        models.Reserva.estado == "activa",
        models.Reserva.hora_inicio < reserva.hora_fin,
        models.Reserva.hora_fin > reserva.hora_inicio
    ).first()

    if solapada:
        raise HTTPException(
            status_code=409, 
            detail="El espacio deportivo ya cuenta con una reserva activa en ese rango de horario."
        )

    # 6. Registrar la reserva
    nueva_reserva = models.Reserva(
        usuario_id=reserva.usuario_id,
        espacio_id=reserva.espacio_id,
        fecha=reserva.fecha,
        hora_inicio=reserva.hora_inicio,
        hora_fin=reserva.hora_fin,
        estado="activa"
    )
    db.add(nueva_reserva)
    db.commit()
    db.refresh(nueva_reserva)
    return nueva_reserva

@app.get("/reservas/", response_model=List[schemas.ReservaResponse], tags=["Reservas"])
def listar_reservas(usuario_id: Optional[int] = None, db: Session = Depends(get_db)):
    query = db.query(models.Reserva)
    if usuario_id:
        query = query.filter(models.Reserva.usuario_id == usuario_id)
    return query.all()

@app.put("/reservas/{reserva_id}/cancelar", response_model=schemas.ReservaResponse, tags=["Reservas"])
def cancelar_reserva(reserva_id: int, db: Session = Depends(get_db)):
    reserva = db.query(models.Reserva).filter(models.Reserva.id == reserva_id).first()
    if not reserva:
        raise HTTPException(status_code=404, detail="La reserva no existe.")
    
    if reserva.estado == "cancelada":
        raise HTTPException(status_code=400, detail="La reserva ya se encuentra cancelada.")

    reserva.estado = "cancelada"
    db.commit()
    db.refresh(reserva)
    return reserva


# ===============================
# ENDPOINTS: USUARIOS
# ===============================
@app.post("/usuarios/", response_model=schemas.UsuarioResponse, status_code=status.HTTP_201_CREATED, tags=["Usuarios"])
def crear_usuario(usuario: schemas.UsuarioCreate, db: Session = Depends(get_db)):
    db_usuario = models.Usuario(**usuario.model_dump())
    db.add(db_usuario)
    db.commit()
    db.refresh(db_usuario)
    return db_usuario