import json
import logging
import os
from pathlib import Path
from typing import Any

import firebase_admin
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth, credentials
from sqlalchemy.orm import Session

import models
from database import get_db

bearer_scheme = HTTPBearer(auto_error=False)
logger = logging.getLogger(__name__)


def _firebase_app() -> firebase_admin.App:
    try:
        return firebase_admin.get_app()
    except ValueError:
        service_account_path = os.getenv("FIREBASE_SERVICE_ACCOUNT")
        service_account_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
        if service_account_json:
            credential = credentials.Certificate(json.loads(service_account_json))
        elif service_account_path:
            path = Path(service_account_path)
            if not path.is_absolute():
                path = Path(__file__).resolve().parent / path
            if not path.is_file():
                raise FileNotFoundError(
                    f"Firebase service account file not found: {path.name}"
                )
            credential = credentials.Certificate(str(path))
        else:
            credential = credentials.ApplicationDefault()

        project_id = os.getenv("FIREBASE_PROJECT_ID")
        options = {"projectId": project_id} if project_id else None
        return firebase_admin.initialize_app(credential, options=options)


def _decode_firebase_token(
    credentials_header: HTTPAuthorizationCredentials | None,
    *,
    require_verified_email: bool,
) -> dict[str, Any]:
    if credentials_header is None or credentials_header.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Iniciá sesión para continuar.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        firebase_app = _firebase_app()
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="La autenticación Firebase del servidor no está configurada.",
        ) from None
    try:
        decoded = auth.verify_id_token(
            credentials_header.credentials,
            app=firebase_app,
            check_revoked=True,
        )
    except (ValueError, auth.InvalidIdTokenError, auth.ExpiredIdTokenError, auth.RevokedIdTokenError) as error:
        logger.warning("Firebase ID token rejected (%s)", type(error).__name__)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="La sesión expiró o no es válida. Volvé a iniciar sesión.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from None
    if require_verified_email and not decoded.get("email_verified"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Verificá tu correo electrónico antes de continuar.",
        )
    if not decoded.get("uid") or not decoded.get("email"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="El token de Firebase no contiene una identidad válida.",
        )
    return decoded


def verify_firebase_token(
    credentials_header: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> dict[str, Any]:
    return _decode_firebase_token(credentials_header, require_verified_email=True)


def verify_firebase_signup_token(
    credentials_header: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> dict[str, Any]:
    return _decode_firebase_token(credentials_header, require_verified_email=False)


def current_user(
    token: dict[str, Any] = Depends(verify_firebase_token),
    db: Session = Depends(get_db),
) -> models.Usuario:
    uid = token["uid"]
    email = token["email"].strip().lower()
    user = db.query(models.Usuario).filter(models.Usuario.firebase_uid == uid).first()

    if user is None:
        user = db.query(models.Usuario).filter(models.Usuario.email == email).first()
        if user is not None and user.firebase_uid is not None:
            raise HTTPException(status_code=409, detail="El correo ya está vinculado a otra cuenta.")
        if user is not None:
            user.firebase_uid = uid
            db.commit()
            db.refresh(user)

    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Completá tu perfil para registrar tu cuenta.",
        )
    if user.email.lower() != email:
        raise HTTPException(status_code=409, detail="El correo de la cuenta no coincide con el perfil registrado.")
    user.is_admin = is_admin_token(token)
    return user


def require_admin(token: dict[str, Any] = Depends(verify_firebase_token)) -> dict[str, Any]:
    if not is_admin_token(token):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Se requiere una cuenta administradora.")
    return token


def is_admin_token(token: dict[str, Any]) -> bool:
    allowed_uids = {
        uid.strip()
        for uid in os.getenv("ADMIN_UIDS", "").split(",")
        if uid.strip()
    }
    return token.get("uid") in allowed_uids or token.get("admin") is True