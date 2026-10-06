from sqlalchemy import Column, Integer, String, Date, Time, ForeignKey, DateTime, Boolean, UniqueConstraint
from sqlalchemy.orm import relationship
from datetime import datetime, timezone
from database import Base


def utc_now_naive():
    return datetime.now(timezone.utc).replace(tzinfo=None)

class Usuario(Base):
    __tablename__ = "usuarios"

    id = Column(Integer, primary_key=True, index=True)
    firebase_uid = Column(String, unique=True, index=True, nullable=True)
    email = Column(String, unique=True, index=True, nullable=False)
    nombre = Column(String, nullable=False)
    apellido = Column(String, nullable=False)
    fecha_nacimiento = Column(Date, nullable=False)
    is_admin = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=utc_now_naive)

    reservas = relationship("Reserva", back_populates="usuario")
    notification_devices = relationship("NotificationDevice", back_populates="usuario", cascade="all, delete-orphan")

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
    created_at = Column(DateTime, default=utc_now_naive)

    usuario = relationship("Usuario", back_populates="reservas")
    espacio = relationship("EspacioDeportivo", back_populates="reservas")
    reminders = relationship("ReservationReminder", back_populates="reserva", cascade="all, delete-orphan")


class NotificationDevice(Base):
    __tablename__ = "notification_devices"
    __table_args__ = (UniqueConstraint("usuario_id", "token", name="uq_user_notification_token"),)

    id = Column(Integer, primary_key=True, index=True)
    usuario_id = Column(Integer, ForeignKey("usuarios.id", ondelete="CASCADE"), nullable=False, index=True)
    token = Column(String, nullable=False)
    updated_at = Column(DateTime, default=utc_now_naive, onupdate=utc_now_naive)

    usuario = relationship("Usuario", back_populates="notification_devices")


class ReservationReminder(Base):
    __tablename__ = "reservation_reminders"
    __table_args__ = (UniqueConstraint("reserva_id", "kind", name="uq_reservation_reminder_kind"),)

    id = Column(Integer, primary_key=True, index=True)
    reserva_id = Column(Integer, ForeignKey("reservas.id", ondelete="CASCADE"), nullable=False, index=True)
    kind = Column(String, nullable=False)
    scheduled_at = Column(DateTime, nullable=False, index=True)
    sent_at = Column(DateTime, nullable=True)

    reserva = relationship("Reserva", back_populates="reminders")