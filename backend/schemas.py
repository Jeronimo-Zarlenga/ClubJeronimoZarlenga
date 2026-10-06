from datetime import date, time, datetime
from typing import Optional

from pydantic import BaseModel, EmailStr, Field, field_validator

# --- SCHEMAS DE USUARIO ---
class UsuarioBase(BaseModel):
    nombre: str = Field(min_length=1, max_length=100)
    apellido: str = Field(min_length=1, max_length=100)
    email: EmailStr
    fecha_nacimiento: date

class UsuarioCreate(UsuarioBase):
    pass

class UsuarioUpdate(BaseModel):
    nombre: str = Field(min_length=1, max_length=100)
    apellido: str = Field(min_length=1, max_length=100)
    fecha_nacimiento: date

class UsuarioResponse(UsuarioBase):
    id: int
    created_at: datetime
    fecha_nacimiento: Optional[date] = None
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
    tipo: str = Field(min_length=1, max_length=80)
    numero: int = Field(ge=1)

    @field_validator("tipo")
    @classmethod
    def validar_tipo(cls, value: str) -> str:
        return value.strip()


class EspacioDeportivoUpdate(BaseModel):
    sede_id: int
    tipo: str = Field(min_length=1, max_length=80)
    numero: int = Field(ge=1)

    @field_validator("tipo")
    @classmethod
    def validar_tipo(cls, value: str) -> str:
        return value.strip()

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