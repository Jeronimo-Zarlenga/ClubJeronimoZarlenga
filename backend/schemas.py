from pydantic import BaseModel, EmailStr
from datetime import date, time, datetime
from typing import Optional

# --- SCHEMAS DE USUARIO ---
class UsuarioBase(BaseModel):
    nombre: str
    apellido: str
    email: EmailStr
    fecha_nacimiento: Optional[date] = None

class UsuarioCreate(UsuarioBase):
    fecha_nacimiento: date


class UsuarioUpdate(BaseModel):
    nombre: str
    apellido: str
    fecha_nacimiento: date

class UsuarioResponse(UsuarioBase):
    id: int
    created_at: datetime
    is_admin: bool = False

    class Config:
        from_attributes = True

# --- SCHEMAS DE SEDE ---
class SedeBase(BaseModel):
    nombre: str
    direccion: str
    hora_apertura: time
    hora_cierre: time

class SedeCreate(SedeBase):
    pass

class SedeResponse(SedeBase):
    id: int

    class Config:
        from_attributes = True

# --- SCHEMAS DE ESPACIO DEPORTIVO ---
class EspacioDeportivoBase(BaseModel):
    sede_id: int
    tipo: str  # Fútbol, Paddle, Básquet, etc.
    numero: int  # Número de cancha para construir el nombre compuesto


class EspacioDeportivoUpdate(BaseModel):
    sede_id: int
    tipo: str
    numero: int

class EspacioDeportivoResponse(BaseModel):
    id: int
    sede_id: int
    tipo: str
    nombre_compuesto: str

    class Config:
        from_attributes = True

# --- SCHEMAS DE RESERVA ---
class ReservaCreate(BaseModel):
    espacio_id: int
    fecha: date
    hora_inicio: time
    hora_fin: time


class ReservaAvailabilityQuery(BaseModel):
    espacio_id: int
    fecha: date
    duracion_horas: int = 1


class NotificationDeviceCreate(BaseModel):
    token: str

class ReservaResponse(BaseModel):
    id: int
    usuario_id: int
    espacio_id: int
    fecha: date
    hora_inicio: time
    hora_fin: time
    estado: str
    created_at: datetime

    class Config:
        from_attributes = True