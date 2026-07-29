"""Service layer for pilot credentials (licences, certificates, clearances).

Static methods returning ``(response_dict, status_code)``, matching the other
services. The Profile screen's PILOT CREDENTIALS section reads from here; the
status badge (valid / expiring / expired) is computed from the expiry date on
every read, so nothing has to run nightly to keep the screen honest.

A fresh account is seeded with the credential *types* an Indian agri-drone
pilot is required to hold, left blank for the operator to fill in. Blank rows
with no number are what an unfinished profile actually looks like — inventing
licence numbers would be worse than useless.
"""

from datetime import date, datetime

from app.api.models.credential import CREDENTIAL_KINDS, PilotCredential
from app.repositories.credential_repository import CredentialRepository

# The paperwork a spraying/survey drone operator needs, in the order the
# Profile screen shows it.
_SEED_CREDENTIALS = (
    ("licence", "DRONE PILOT LICENCE", "DGCA"),
    ("certification", "PESTICIDE OPERATOR CERT.", None),
    ("clearance", "FLIGHT ZONE CLEARANCE", None),
    ("insurance", "INSURANCE POLICY", None),
)

# Free-text fields that can be set or cleared. 'kind' is deliberately absent —
# it has a closed value set and is validated separately.
_EDITABLE = ("label", "identifier", "issuer", "notes")


def _fail(message, status=400):
    return {"status": "error", "message": message}, status


def _parse_date(value, field):
    """ISO date string -> date. Returns (value, error_message)."""
    if value in (None, ""):
        return None, None
    if isinstance(value, date):
        return value, None
    try:
        return datetime.strptime(str(value)[:10], "%Y-%m-%d").date(), None
    except (TypeError, ValueError):
        return None, f"'{field}' must be an ISO date (YYYY-MM-DD)."


class CredentialService:

    @staticmethod
    def _ensure_seed(user_id):
        """Give a new account the empty credential rows to fill in."""
        if CredentialRepository.list_for_user(user_id):
            return
        for kind, label, issuer in _SEED_CREDENTIALS:
            CredentialRepository.create(
                PilotCredential(
                    user_id=user_id, kind=kind, label=label, issuer=issuer
                )
            )

    @staticmethod
    def list_credentials(user_id):
        if user_id is None:
            return _fail("Sign in to see your credentials.", 401)

        CredentialService._ensure_seed(user_id)
        credentials = CredentialRepository.list_for_user(user_id)
        today = date.today()

        items = [c.to_dict(today) for c in credentials]
        return {
            "status": "ok",
            "credentials": items,
            # Lets the app badge the Profile tab without re-scanning the list.
            "expiring_count": sum(1 for i in items if i["status"] == "expiring"),
            "expired_count": sum(1 for i in items if i["status"] == "expired"),
        }, 200

    @staticmethod
    def create_credential(user_id, payload):
        if user_id is None:
            return _fail("Sign in to add a credential.", 401)
        if not isinstance(payload, dict):
            return _fail("Request body must be JSON.")

        label = str(payload.get("label") or "").strip()
        if not label:
            return _fail("'label' is required.")

        kind = str(payload.get("kind") or "other").lower().strip()
        if kind not in CREDENTIAL_KINDS:
            return _fail(f"'kind' must be one of: {', '.join(CREDENTIAL_KINDS)}.")

        issued_on, error = _parse_date(payload.get("issued_on"), "issued_on")
        if error:
            return _fail(error)
        expires_on, error = _parse_date(payload.get("expires_on"), "expires_on")
        if error:
            return _fail(error)
        if issued_on and expires_on and expires_on < issued_on:
            return _fail("'expires_on' cannot be before 'issued_on'.")

        credential = PilotCredential(
            user_id=user_id,
            kind=kind,
            label=label,
            identifier=(payload.get("identifier") or None),
            issuer=(payload.get("issuer") or None),
            issued_on=issued_on,
            expires_on=expires_on,
            notes=(payload.get("notes") or None),
        )
        CredentialRepository.create(credential)

        return {
            "status": "ok",
            "message": f"'{label}' added.",
            "credential": credential.to_dict(),
        }, 201

    @staticmethod
    def update_credential(user_id, credential_id, payload):
        if user_id is None:
            return _fail("Sign in to edit a credential.", 401)
        if not isinstance(payload, dict):
            return _fail("Request body must be JSON.")

        credential = CredentialRepository.get_by_id(credential_id)
        if credential is None:
            return _fail("Credential not found.", 404)
        if credential.user_id != user_id:
            return _fail("Not your credential.", 403)

        # Handled here rather than in the generic loop below: kind is the one
        # field with a closed value set, and it must never be cleared to null.
        if "kind" in payload:
            kind = str(payload.get("kind") or "").lower().strip()
            if kind not in CREDENTIAL_KINDS:
                return _fail(
                    f"'kind' must be one of: {', '.join(CREDENTIAL_KINDS)}."
                )
            credential.kind = kind

        for field in ("issued_on", "expires_on"):
            if field in payload:
                parsed, error = _parse_date(payload.get(field), field)
                if error:
                    return _fail(error)
                setattr(credential, field, parsed)

        if credential.issued_on and credential.expires_on \
                and credential.expires_on < credential.issued_on:
            return _fail("'expires_on' cannot be before 'issued_on'.")

        for field in _EDITABLE:
            if field not in payload:
                continue
            value = payload[field]
            value = str(value).strip() if value not in (None, "") else None
            if field == "label" and not value:
                return _fail("'label' cannot be empty.")
            setattr(credential, field, value)

        credential.touch()
        CredentialRepository.save()

        return {
            "status": "ok",
            "message": f"'{credential.label}' updated.",
            "credential": credential.to_dict(),
        }, 200

    @staticmethod
    def delete_credential(user_id, credential_id):
        if user_id is None:
            return _fail("Sign in to remove a credential.", 401)

        credential = CredentialRepository.get_by_id(credential_id)
        if credential is None:
            return _fail("Credential not found.", 404)
        if credential.user_id != user_id:
            return _fail("Not your credential.", 403)

        label = credential.label
        CredentialRepository.delete(credential)
        return {"status": "ok", "message": f"'{label}' removed."}, 200
