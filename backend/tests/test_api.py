import unittest
from datetime import date, datetime, time, timedelta

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import models
from database import Base, get_db
from main import app
from security import current_user, verify_firebase_signup_token


class ApiContractTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        self.session_factory = sessionmaker(bind=self.engine, expire_on_commit=False)
        Base.metadata.create_all(bind=self.engine)

        with self.session_factory() as db:
            self.user = models.Usuario(
                firebase_uid="verified-user-uid",
                email="player@example.com",
                nombre="Jugador",
                apellido="Uno",
            )
            self.other_user = models.Usuario(
                firebase_uid="other-user-uid",
                email="other@example.com",
                nombre="Jugador",
                apellido="Dos",
            )
            db.add_all([self.user, self.other_user])
            db.flush()
            self.venue = models.Sede(
                nombre="Sede Test",
                direccion="Calle 123",
                hora_apertura=time(8),
                hora_cierre=time(12),
            )
            db.add(self.venue)
            db.flush()
            self.space = models.EspacioDeportivo(
                sede_id=self.venue.id,
                tipo="Tenis",
                nombre_compuesto="Sede_Test_Calle_123_Tenis_1",
            )
            db.add(self.space)
            db.commit()
            self.user_id = self.user.id
            self.other_user_id = self.other_user.id
            self.venue_id = self.venue.id
            self.space_id = self.space.id

        self.request_session = self.session_factory()

        def override_get_db():
            yield self.request_session

        def override_current_user():
            return self.request_session.query(models.Usuario).filter_by(id=self.user_id).one()

        app.dependency_overrides[get_db] = override_get_db
        app.dependency_overrides[current_user] = override_current_user
        self.client = TestClient(app)

    def tearDown(self):
        app.dependency_overrides.clear()
        self.request_session.close()
        self.engine.dispose()

    def test_private_reservations_require_a_firebase_bearer_token(self):
        app.dependency_overrides.pop(current_user)

        response = self.client.get("/reservas/")

        self.assertEqual(response.status_code, 401)

    def test_availability_respects_venue_hours_and_existing_reservations(self):
        requested_date = date.today() + timedelta(days=4)
        with self.session_factory() as db:
            db.add(
                models.Reserva(
                    usuario_id=self.user_id,
                    espacio_id=self.space_id,
                    fecha=requested_date,
                    hora_inicio=time(9),
                    hora_fin=time(10),
                    estado="activa",
                )
            )
            db.commit()

        response = self.client.get(
            "/disponibilidad/",
            params={
                "espacio_id": self.space_id,
                "fecha": requested_date.isoformat(),
                "duracion_horas": 1,
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["horarios"], ["08:00:00", "10:00:00", "11:00:00"])

    def test_reservation_identity_comes_from_the_authenticated_user(self):
        requested_date = date.today() + timedelta(days=4)
        response = self.client.post(
            "/reservas/",
            json={
                "usuario_id": self.other_user_id,
                "espacio_id": self.space_id,
                "fecha": requested_date.isoformat(),
                "hora_inicio": "08:00:00",
                "hora_fin": "09:00:00",
            },
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()["usuario_id"], self.user_id)

    def test_availability_rounds_opening_up_to_a_full_hour(self):
        requested_date = date.today() + timedelta(days=4)
        with self.session_factory() as db:
            venue = db.query(models.Sede).filter_by(id=self.venue_id).one()
            venue.hora_apertura = time(8, 30)
            db.commit()

        response = self.client.get(
            "/disponibilidad/",
            params={
                "espacio_id": self.space_id,
                "fecha": requested_date.isoformat(),
                "duracion_horas": 1,
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["horarios"], ["09:00:00", "10:00:00", "11:00:00"])

    def test_user_cannot_cancel_another_users_reservation(self):
        requested_date = date.today() + timedelta(days=4)
        with self.session_factory() as db:
            booking = models.Reserva(
                usuario_id=self.other_user_id,
                espacio_id=self.space_id,
                fecha=requested_date,
                hora_inicio=time(8),
                hora_fin=time(9),
                estado="activa",
            )
            db.add(booking)
            db.commit()
            booking_id = booking.id

        response = self.client.put(f"/reservas/{booking_id}/cancelar")

        self.assertEqual(response.status_code, 404)
        with self.session_factory() as db:
            booking = db.query(models.Reserva).filter_by(id=booking_id).one()
            self.assertEqual(booking.estado, "activa")

    def test_profile_update_does_not_allow_email_changes(self):
        response = self.client.put(
            "/usuarios/me",
            json={
                "nombre": "Nombre actualizado",
                "apellido": "Apellido actualizado",
                "fecha_nacimiento": "1995-08-12",
                "email": "attacker@example.com",
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["email"], "player@example.com")
        self.assertEqual(response.json()["nombre"], "Nombre actualizado")

    def test_firebase_signup_persists_profile_and_me_reads_it(self):
        app.dependency_overrides[verify_firebase_signup_token] = lambda: {
            "uid": "new-firebase-user-uid",
            "email": "new-player@example.com",
            "email_verified": False,
        }
        registration = self.client.post(
            "/usuarios/",
            json={
                "nombre": "Nueva",
                "apellido": "Jugadora",
                "email": "new-player@example.com",
                "fecha_nacimiento": "2000-09-26",
            },
        )

        self.assertEqual(registration.status_code, 201)
        self.user_id = registration.json()["id"]
        profile = self.client.get("/usuarios/me")

        self.assertEqual(profile.status_code, 200)
        self.assertEqual(profile.json()["email"], "new-player@example.com")
        self.assertEqual(profile.json()["nombre"], "Nueva")
        self.assertEqual(profile.json()["fecha_nacimiento"], "2000-09-26")
        saved = self.request_session.query(models.Usuario).filter_by(id=self.user_id).one()
        self.assertEqual(saved.firebase_uid, "new-firebase-user-uid")


if __name__ == "__main__":
    unittest.main()
