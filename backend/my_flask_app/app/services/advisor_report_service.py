"""Storing reports of crop-advisor answers.

See :mod:`app.api.models.advisor_report` for why these exist: Google Play
requires in-app reporting of harmful or offensive AI-generated content.
"""

from __future__ import annotations

from typing import Any, Dict, Optional, Tuple

from app.ai import gemini_advisor
from app.api.models.advisor_report import REPORT_REASONS, AdvisorReport
from app.core.database import db

# Generous caps: long enough for any real answer, short enough that the
# endpoint cannot be used to store arbitrary bulk text.
_MAX_ANSWER = 20000
_MAX_QUESTION = 4000
_MAX_NOTE = 2000


def _clip(value: Any, limit: int) -> Optional[str]:
    text = str(value or "").strip()
    return text[:limit] or None


class AdvisorReportService:

    @staticmethod
    def report(user_id, data) -> Tuple[Dict[str, Any], int]:
        data = data if isinstance(data, dict) else {}

        answer = _clip(data.get("answer"), _MAX_ANSWER)
        if not answer:
            return {"message": "Nothing to report: the answer is empty."}, 400

        reason = str(data.get("reason") or "").strip().lower()
        if reason not in REPORT_REASONS:
            allowed = ", ".join(REPORT_REASONS)
            return {"message": f"reason must be one of: {allowed}."}, 400

        record = AdvisorReport(
            user_id=user_id,
            reason=reason,
            note=_clip(data.get("note"), _MAX_NOTE),
            question=_clip(data.get("question"), _MAX_QUESTION),
            answer=answer,
            model=gemini_advisor.model_name(),
        )
        db.session.add(record)
        db.session.commit()
        return {
            "message": "Thank you. The answer has been reported for review.",
            "report_id": record.id,
        }, 201
