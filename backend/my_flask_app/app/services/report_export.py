"""Export a stored analysis run as a field report the operator can keep.

Two formats, because they answer different needs:

  * **CSV** — numbers an agronomist can drop into a spreadsheet and compare
    across blocks. Pure standard library, so it always works.
  * **PDF**  — a printable one-pager with the risk split drawn as a chart, for
    the file that goes to the farm owner. Rendered with matplotlib, which the
    project already depends on for plotting; if it is missing the caller gets
    a clear 503 rather than a broken download, and CSV still works.

Both are built from the persisted :class:`AnalysisRecord` (plus its alerts),
never re-running the pipeline — an exported report must show exactly what the
app showed, not a fresh computation that could differ.
"""

from __future__ import annotations

import csv
import io
import logging
from datetime import datetime
from typing import Tuple

logger = logging.getLogger(__name__)

# Colours match the app's risk palette so a printed report and the screen agree.
_RISK_COLOURS = {"low": "#5D9C59", "medium": "#E7B10A", "high": "#E64848"}


def _display_date(record) -> str:
    if not record.created_at:
        return "—"
    return record.created_at.strftime("%d %b %Y, %H:%M")


def _title(record) -> str:
    return record.field_name or f"Analysis #{record.id}"


def safe_filename(record, extension: str) -> str:
    """A download name that is readable and safe on every OS."""
    base = _title(record).lower()
    cleaned = "".join(c if c.isalnum() else "-" for c in base).strip("-")
    cleaned = "-".join(part for part in cleaned.split("-") if part) or "report"
    stamp = record.created_at.strftime("%Y%m%d") if record.created_at else "report"
    return f"agrivision-{cleaned}-{stamp}.{extension}"


def _summary_rows(record):
    """The report's headline figures, as (label, value) pairs."""
    distribution = {
        "low": record.risk_low or 0.0,
        "medium": record.risk_medium or 0.0,
        "high": record.risk_high or 0.0,
    }
    return [
        ("Field", _title(record)),
        ("Analysed", _display_date(record)),
        ("Health score", f"{round(record.health_score)} / 100"
            if record.health_score is not None else "—"),
        ("Health label", record.health_label or "—"),
        ("Primary index", record.primary_index or "—"),
        ("Calibration", "Calibrated reflectance" if record.calibrated
            else "Uncalibrated (relative)"),
        ("Low-risk area", f"{round(distribution['low'] * 100)}%"),
        ("Medium-risk area", f"{round(distribution['medium'] * 100)}%"),
        ("High-risk area", f"{round(distribution['high'] * 100)}%"),
        ("Detections", str(len(record.alerts))),
    ], distribution


# ── CSV ────────────────────────────────────────────────────────────────────


def build_csv(record) -> bytes:
    """Two blocks — summary, then the alert table — in one spreadsheet file."""
    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer)

    rows, _distribution = _summary_rows(record)

    writer.writerow(["AgriVision field report"])
    writer.writerow(["Generated", datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")])
    writer.writerow([])

    writer.writerow(["Summary", "Value"])
    for label, value in rows:
        writer.writerow([label, value])

    writer.writerow([])
    writer.writerow(["Detections"])
    writer.writerow(["Title", "Severity", "Index", "Area", "Status", "Raised"])
    if record.alerts:
        for alert in record.alerts:
            writer.writerow([
                alert.title,
                alert.severity or "",
                alert.index_key or "",
                alert.area or "",
                "active" if alert.is_active else "resolved",
                alert.created_at.strftime("%Y-%m-%d %H:%M")
                if alert.created_at else "",
            ])
    else:
        writer.writerow(["No stress flags raised", "", "", "", "", ""])

    # utf-8-sig: Excel needs the BOM to read non-ASCII field names correctly.
    return buffer.getvalue().encode("utf-8-sig")


# ── PDF ────────────────────────────────────────────────────────────────────


def pdf_available() -> bool:
    try:
        import matplotlib  # noqa: F401
    except Exception:
        return False
    return True


def build_pdf(record) -> bytes:
    """A printable A4 one-pager: summary table, risk chart, detections list."""
    import matplotlib

    # Headless: the request thread has no display, and no GUI backend must be
    # touched or matplotlib will try to open a window and hang the worker.
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.backends.backend_pdf import PdfPages

    rows, distribution = _summary_rows(record)

    buffer = io.BytesIO()
    with PdfPages(buffer) as pdf:
        figure = plt.figure(figsize=(8.27, 11.69))  # A4 portrait, inches

        # ── header ────────────────────────────────────────────────────────
        figure.text(0.07, 0.995, "AgriVision", fontsize=10, color="#5D9C59",
                    weight="bold", va="top")
        figure.text(0.07, 0.965, _title(record), fontsize=20, weight="bold",
                    va="top", color="#1A3A28")
        figure.text(0.07, 0.935, f"Multispectral field report · {_display_date(record)}",
                    fontsize=10, color="#6B7280", va="top")
        figure.add_artist(plt.Line2D([0.07, 0.93], [0.922, 0.922],
                                     color="#D1D5DB", linewidth=0.8))

        # ── summary table ─────────────────────────────────────────────────
        y = 0.885
        for label, value in rows:
            figure.text(0.07, y, label, fontsize=10, color="#6B7280", va="top")
            figure.text(0.45, y, str(value), fontsize=10, color="#111827",
                        weight="bold", va="top")
            y -= 0.026

        # ── risk chart ────────────────────────────────────────────────────
        axes = figure.add_axes([0.07, 0.37, 0.86, 0.21])
        bands = ["low", "medium", "high"]
        values = [distribution[b] * 100 for b in bands]
        bars = axes.bar(
            ["Low risk", "Medium", "High risk"],
            values,
            color=[_RISK_COLOURS[b] for b in bands],
            width=0.55,
        )
        axes.set_title("Risk zone distribution", fontsize=12, weight="bold",
                       color="#1A3A28", loc="left", pad=12)
        axes.set_ylabel("% of analysed field", fontsize=9, color="#6B7280")
        axes.set_ylim(0, max(100, max(values) * 1.15 if values else 100))
        axes.spines[["top", "right"]].set_visible(False)
        axes.tick_params(labelsize=9, colors="#6B7280")
        for bar, value in zip(bars, values):
            axes.text(bar.get_x() + bar.get_width() / 2, value + 2,
                      f"{round(value)}%", ha="center", fontsize=9,
                      color="#111827", weight="bold")

        # ── detections ────────────────────────────────────────────────────
        figure.text(0.07, 0.305, "Detections", fontsize=12, weight="bold",
                    color="#1A3A28", va="top")
        y = 0.275
        if record.alerts:
            # Cap the list so a noisy analysis can't overflow the page; the CSV
            # export carries the complete set.
            for alert in record.alerts[:8]:
                colour = _RISK_COLOURS.get(alert.severity or "medium", "#6B7280")
                figure.text(0.07, y, "●", fontsize=9, color=colour, va="top")
                figure.text(0.10, y, alert.title, fontsize=9.5,
                            color="#111827", va="top")
                detail = " · ".join(
                    part for part in (
                        (alert.severity or "").upper() or None,
                        (alert.index_key or "").upper() or None,
                        alert.area,
                    ) if part
                )
                figure.text(0.10, y - 0.016, detail, fontsize=8,
                            color="#6B7280", va="top")
                y -= 0.042
            if len(record.alerts) > 8:
                figure.text(0.07, y, f"+ {len(record.alerts) - 8} more "
                                     f"(see the CSV export)",
                            fontsize=8, color="#6B7280", va="top", style="italic")
        else:
            figure.text(0.07, y, "No stress flags raised.", fontsize=9.5,
                        color="#6B7280", va="top")

        # ── footer ────────────────────────────────────────────────────────
        figure.text(
            0.07, 0.035,
            "Automated screening from multispectral imagery. Confirm findings "
            "in-field before applying treatments.",
            fontsize=7.5, color="#9CA3AF", va="top",
        )
        figure.text(
            0.07, 0.018,
            f"Generated {datetime.utcnow().strftime('%d %b %Y %H:%M UTC')} · "
            f"AgriVision analysis #{record.id}",
            fontsize=7.5, color="#9CA3AF", va="top",
        )

        pdf.savefig(figure)
        plt.close(figure)

    return buffer.getvalue()


# ── entry point ────────────────────────────────────────────────────────────

FORMATS = ("csv", "pdf")

_MIMETYPES = {
    "csv": "text/csv; charset=utf-8",
    "pdf": "application/pdf",
}


def build(record, export_format: str) -> Tuple[bytes, str, str]:
    """Return ``(payload, mimetype, filename)`` for the requested format.

    Raises:
        ValueError:   unknown format.
        RuntimeError: PDF requested but matplotlib is not installed.
    """
    export_format = str(export_format or "csv").lower().strip()
    if export_format not in FORMATS:
        raise ValueError(
            f"Unknown format '{export_format}'. Use one of: {', '.join(FORMATS)}."
        )

    if export_format == "pdf":
        if not pdf_available():
            raise RuntimeError(
                "PDF export needs matplotlib on the server "
                "(pip install matplotlib). CSV export works without it."
            )
        payload = build_pdf(record)
    else:
        payload = build_csv(record)

    return payload, _MIMETYPES[export_format], safe_filename(record, export_format)
