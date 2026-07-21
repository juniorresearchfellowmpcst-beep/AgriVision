"""Input validation for the drone endpoints.

Plain-dict validators (no marshmallow dependency) returning
(cleaned_data, error_message). error_message is None when the input is valid,
mirroring the light-weight style used across the API layer.
"""

_TELEMETRY_INT_FIELDS = (
    "battery_percent",
    "tank_percent",
    "gps_satellites",
    "signal_dbm",
    "total_flights",
)

_TELEMETRY_STATUSES = ("available", "paired", "flying", "offline")


def validate_pair_payload(data):
    """Pairing needs either a drone id or a serial number."""
    if not isinstance(data, dict):
        return None, "Request body must be JSON"

    drone_id = data.get("drone_id")
    serial = (data.get("serial_number") or "").strip()

    if drone_id is None and not serial:
        return None, "Provide 'drone_id' or 'serial_number' to pair."

    if drone_id is not None:
        try:
            drone_id = int(drone_id)
        except (TypeError, ValueError):
            return None, "'drone_id' must be an integer."

    return {"drone_id": drone_id, "serial_number": serial or None}, None


def validate_telemetry_payload(data):
    """Telemetry updates: any subset of numeric gauges + connection/status."""
    if not isinstance(data, dict):
        return None, "Request body must be JSON"

    cleaned = {}
    for field in _TELEMETRY_INT_FIELDS:
        if field in data and data[field] is not None:
            try:
                cleaned[field] = int(data[field])
            except (TypeError, ValueError):
                return None, f"'{field}' must be an integer."

    if "is_connected" in data:
        cleaned["is_connected"] = bool(data["is_connected"])

    if data.get("status"):
        status = str(data["status"]).lower()
        if status not in _TELEMETRY_STATUSES:
            return None, (
                f"'status' must be one of: {', '.join(_TELEMETRY_STATUSES)}."
            )
        cleaned["status"] = status

    if not cleaned:
        return None, "No recognised telemetry fields in payload."

    return cleaned, None
