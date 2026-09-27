import logging
import os
from datetime import datetime
from zoneinfo import ZoneInfo

from apscheduler.schedulers.background import BackgroundScheduler
from firebase_admin import messaging
from sqlalchemy.orm import joinedload

import models
from database import SessionLocal
from security import _firebase_app

logger = logging.getLogger(__name__)
timezone = ZoneInfo(os.getenv("APP_TIMEZONE", "America/Argentina/Buenos_Aires"))
scheduler = BackgroundScheduler(timezone=timezone)


def send_due_reminders() -> None:
    now = datetime.now(timezone).replace(tzinfo=None)
    with SessionLocal() as db:
        reminders = (
            db.query(models.ReservationReminder)
            .options(
                joinedload(models.ReservationReminder.reserva)
                .joinedload(models.Reserva.usuario),
                joinedload(models.ReservationReminder.reserva)
                .joinedload(models.Reserva.espacio)
                .joinedload(models.EspacioDeportivo.sede),
            )
            .filter(
                models.ReservationReminder.sent_at.is_(None),
                models.ReservationReminder.scheduled_at <= now,
                models.ReservationReminder.reserva.has(models.Reserva.estado == "activa"),
            )
            .all()
        )

        for reminder in reminders:
            reservation = reminder.reserva
            tokens = [device.token for device in reservation.usuario.notification_devices]
            if not tokens:
                continue

            venue = reservation.espacio.sede.nombre
            chunks_completed = True
            for offset in range(0, len(tokens), 500):
                chunk = tokens[offset : offset + 500]
                message = messaging.MulticastMessage(
                    notification=messaging.Notification(
                        title="Tu reserva se acerca",
                        body=(
                            f"{venue} · {reservation.espacio.tipo}, "
                            f"{reservation.fecha:%d/%m} a las {reservation.hora_inicio:%H:%M}"
                        ),
                    ),
                    data={"reservation_id": str(reservation.id), "reminder": reminder.kind},
                    tokens=chunk,
                )
                try:
                    result = messaging.send_each_for_multicast(message, app=_firebase_app())
                except Exception:
                    logger.exception("No se pudo enviar el recordatorio de reserva %s", reservation.id)
                    chunks_completed = False
                    break

                for token, response in zip(chunk, result.responses):
                    if not response.success and isinstance(
                        response.exception,
                        (messaging.UnregisteredError, messaging.SenderIdMismatchError),
                    ):
                        db.query(models.NotificationDevice).filter(
                            models.NotificationDevice.token == token
                        ).delete(synchronize_session=False)
            if chunks_completed:
                reminder.sent_at = now

        db.commit()


def start_scheduler() -> None:
    if not scheduler.running:
        scheduler.add_job(
            send_due_reminders,
            trigger="interval",
            minutes=1,
            id="reservation-push-reminders",
            replace_existing=True,
            max_instances=1,
        )
        scheduler.start()


def stop_scheduler() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)