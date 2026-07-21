"""Service layer for persisted analysis history: reports + AI alerts.

The preprocessing pipeline computes each analysis; this service records the
outcome so the app's Reports and Alerts tabs have real history to show.
Static methods returning (response_dict, status_code), matching the others.
"""

import json

from app.api.models.analysis import AlertRecord, AnalysisRecord
from app.repositories.analysis_repository import AnalysisRepository


def _fraction_label(fraction):
    if not fraction:
        return None
    return f"{round(float(fraction) * 100)}% of field"


class AnalysisService:

    @staticmethod
    def record_analysis(result, user_id=None, field_name=None):
        """Persist a successful /analyze-images response + derived alerts.

        `result` is the JSON-safe dict produced by analyze_images(): the
        `report` block carries health score/label and stress `flags`, and
        `risk.distribution` carries the high/medium/low area fractions.
        """
        report = result.get("report") or {}
        risk = result.get("risk") or {}
        distribution = (
            risk.get("distribution") or report.get("risk_distribution") or {}
        )

        record = AnalysisRecord(
            job_id=result.get("job_id"),
            user_id=user_id,
            field_name=field_name,
            primary_index=result.get("primary_index"),
            health_score=report.get("health_score"),
            health_label=report.get("health_label"),
            calibrated=bool(result.get("calibrated")),
            risk_high=float(distribution.get("high") or 0.0),
            risk_medium=float(distribution.get("medium") or 0.0),
            risk_low=float(distribution.get("low") or 0.0),
            summary=json.dumps(result),
        )

        # Each report flag becomes an actionable alert in the app.
        for flag in report.get("flags") or []:
            severity = str(flag.get("severity") or "medium").lower()
            record.alerts.append(
                AlertRecord(
                    title=flag.get("issue") or "Crop stress detected",
                    severity=severity if severity in ("high", "medium", "low") else "medium",
                    index_key=flag.get("index"),
                    location=field_name,
                    area=_fraction_label(distribution.get(severity)),
                )
            )

        AnalysisRepository.create(record)
        return record

    @staticmethod
    def list_reports(user_id=None):
        records = AnalysisRepository.list_records(user_id=user_id)
        return {
            "status": "ok",
            "reports": [r.to_dict() for r in records],
        }, 200

    @staticmethod
    def get_report(record_id, user_id=None):
        record = AnalysisRepository.get_by_id(record_id)
        if record is None:
            return {"status": "error", "message": "Report not found."}, 404
        if record.user_id is not None and record.user_id != user_id:
            return {"status": "error", "message": "Not your report."}, 403
        return {"status": "ok", "report": record.to_dict(include_summary=True)}, 200

    @staticmethod
    def list_alerts(user_id=None, active_only=True):
        alerts = AnalysisRepository.list_alerts(
            user_id=user_id, active_only=active_only
        )
        return {
            "status": "ok",
            "active_count": sum(1 for a in alerts if a.is_active),
            "alerts": [a.to_dict() for a in alerts],
        }, 200

    @staticmethod
    def resolve_alert(alert_id, user_id=None):
        alert = AnalysisRepository.get_alert(alert_id)
        if alert is None:
            return {"status": "error", "message": "Alert not found."}, 404

        owner = alert.analysis.user_id if alert.analysis else None
        if owner is not None and owner != user_id:
            return {"status": "error", "message": "Not your alert."}, 403

        alert.is_active = False
        AnalysisRepository.save()
        return {"status": "ok", "alert": alert.to_dict()}, 200
