from sqlalchemy import Column, Integer, String, Date, Time, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base

class Usuario(Base):
    __tablename__ = "usuarios"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    nombre = Column(String, nullable=False)
    apellido = Column(String, nullable=False)
    fecha_nacimiento = Column(Date, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    reservas = relationship("Reserva", back_populates="usuario")

class Sede(Base):
    __tablename__ = "sedes"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String, nullable=False)
    direccion = Column(String, nullable=False)
    hora_apertura = Column(Time, nullable=False)
    hora_cierre = Column(Time, nullable=False)

    espacios = relationship("EspacioDeportivo", back_populates="sede")

class EspacioDeportivo(Base):
    __tablename__ = "espacios_deportivos"

    id = Column(Integer, primary_key=True, index=True)
    sede_id = Column(Integer, ForeignKey("sedes.id"), nullable=False)
    tipo = Column(String, nullable=False)  # Fútbol, Paddle, Básquet, etc.
    nombre_compuesto = Column(String, nullable=False, unique=True)  # Ej: Moron_Rivadavia_19850_Paddle_1

    sede = relationship("Sede", back_populates="espacios")
    reservas = relationship("Reserva", back_populates="espacio")

class Reserva(Base):
    __tablename__ = "reservas"

    id = Column(Integer, primary_key=True, index=True)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False)
    espacio_id = Column(Integer, ForeignKey("espacios_deportivos.id"), nullable=False)
    fecha = Column(Date, nullable=False)
    hora_inicio = Column(Time, nullable=False)
    hora_fin = Column(Time, nullable=False)
    estado = Column(String, default="activa")  # 'activa' o 'cancelada'
    created_at = Column(DateTime, default=datetime.utcnow)

    usuario = relationship("Usuario", back_populates="reservas")
    espacio = relationship("EspacioDeportivo", back_populates="reservas")