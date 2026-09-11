"""Public pages Google Play requires: privacy policy, terms, account deletion.

The Play listing needs a privacy-policy URL, and the User Data policy needs a
web page where somebody who has already uninstalled the app can still delete
their account. They are served by this backend at root URLs -- ``/privacy``,
``/terms`` and ``/account/delete`` -- so the links move with the service rather
than living on some separate host that can lapse.

The policy text is markdown in ``app/legal``. The app bundles an identical copy
(``Frontend/agri_vision/assets/legal``) and a test fails if the two drift, so
the page Google reviews and the page a farmer reads in the app say the same
thing.
"""

from __future__ import annotations

import html
import os
import re

from flask import Blueprint, Response, current_app, request

from app.api.models.user import User
from app.core.database import db
from app.core.ratelimit import rate_limit
from app.core.security import hash_password, verify_password
from app.services.account_service import AccountService

legal_bp = Blueprint("legal", __name__)

_LEGAL_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "legal",
)

_STYLE = """
:root { color-scheme: light; }
* { box-sizing: border-box; }
body { margin: 0; background: #F4F6F4; color: #1F2024;
       font: 16px/1.6 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
main { max-width: 720px; margin: 0 auto; padding: 32px 20px 64px; }
header { color: #1F4D38; font-weight: 700; letter-spacing: .02em; margin-bottom: 8px; }
h1 { font-size: 1.8rem; line-height: 1.25; margin: 0 0 16px; }
h2 { font-size: 1.2rem; margin: 32px 0 8px; }
p, li { color: #2F3036; }
ul { padding-left: 1.2rem; }
li { margin: 6px 0; }
a { color: #1F4D38; }
code { background: #E8E9F1; padding: 1px 5px; border-radius: 4px; font-size: .9em; }
.card { background: #fff; border: 1px solid #E8E9F1; border-radius: 12px;
        padding: 20px; margin: 20px 0; }
label { display: block; font-weight: 600; margin: 14px 0 6px; }
input { width: 100%; padding: 11px 12px; font: inherit; border: 1px solid #C5C6CC;
        border-radius: 8px; background: #fff; }
button { margin-top: 18px; width: 100%; padding: 12px; font: inherit; font-weight: 700;
         color: #fff; background: #C62828; border: 0; border-radius: 8px; cursor: pointer; }
.error { background: #FDECEA; color: #8E1C1C; border-radius: 8px; padding: 12px 14px; }
.done { background: #E7F3E6; color: #1F4D38; border-radius: 8px; padding: 12px 14px; }
.muted { color: #71727A; font-size: .95rem; }
"""


def _page(title: str, body_html: str, status: int = 200) -> Response:
    document = (
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        f"<title>{html.escape(title)} · AgriVision</title>"
        f"<style>{_STYLE}</style></head><body><main>"
        "<header>AgriVision</header>"
        f"{body_html}</main></body></html>"
    )
    return Response(document, status=status, mimetype="text/html")


# ── a small markdown renderer ────────────────────────────────────────────────
#
# Only what the legal documents use: headings, paragraphs, bullets, bold,
# inline code and bare links. Everything is HTML-escaped *first*, so no text in
# a document can become markup, and nothing this does not recognise is lost --
# it is printed as a paragraph.

_CODE = re.compile(r"`([^`]+)`")
_BOLD = re.compile(r"\*\*(.+?)\*\*")
_URL = re.compile(r"(https?://[^\s<)]+[^\s<).,;])")
_HEADING = re.compile(r"^(#{1,3})\s+(.*)$")
_BULLET = re.compile(r"^\s*[-*]\s+(.*)$")


def _inline(text: str) -> str:
    out = html.escape(text, quote=False)
    out = _CODE.sub(r"<code>\1</code>", out)
    out = _BOLD.sub(r"<strong>\1</strong>", out)
    return _URL.sub(r'<a href="\1">\1</a>', out)


def _render(markdown_text: str) -> str:
    blocks, paragraph, items = [], [], []

    def flush_paragraph():
        if paragraph:
            blocks.append("<p>" + _inline(" ".join(paragraph)) + "</p>")
            paragraph.clear()

    def flush_list():
        if items:
            blocks.append(
                "<ul>" + "".join(f"<li>{_inline(i)}</li>" for i in items) + "</ul>"
            )
            items.clear()

    for raw in markdown_text.splitlines():
        line = raw.rstrip()
        if not line.strip():
            flush_paragraph()
            flush_list()
            continue
        heading = _HEADING.match(line)
        bullet = _BULLET.match(line)
        if heading:
            flush_paragraph()
            flush_list()
            level = len(heading.group(1))
            blocks.append(f"<h{level}>{_inline(heading.group(2))}</h{level}>")
        elif bullet:
            flush_paragraph()
            items.append(bullet.group(1))
        else:
            flush_list()
            paragraph.append(line.strip())

    flush_paragraph()
    flush_list()
    return "\n".join(blocks)


def _document(name: str, title: str) -> Response:
    with open(os.path.join(_LEGAL_DIR, name), encoding="utf-8") as handle:
        return _page(title, _render(handle.read()))


@legal_bp.route("/privacy", methods=["GET"])
def privacy():
    return _document("privacy_policy.md", "Privacy Policy")


@legal_bp.route("/terms", methods=["GET"])
def terms():
    return _document("terms.md", "Terms of Use")


# ── account deletion on the web ──────────────────────────────────────────────
#
# Email and password, deliberately. An emailed confirmation code would work for
# Google sign-in accounts too, but until SMTP is configured the reset-code
# endpoint returns the code in its response -- so a code-based form would let
# anyone type any address and delete that account. A password is something only
# the owner has. Google sign-in accounts have no password they know, so the
# page sends them to the in-app button or to a support address instead.

_dummy_hash = None


def _burn_a_hash_check(password: str) -> None:
    """Spend the time a real password check costs, for an unknown email.

    Without it, "no such account" answers measurably faster than "wrong
    password", and the form becomes a way to test which emails are registered.
    """
    global _dummy_hash
    if _dummy_hash is None:
        _dummy_hash = hash_password("not-a-real-password")
    verify_password(_dummy_hash, password or "x")


def _deletion_page(error=None, done=False, status=200) -> Response:
    support = html.escape((os.environ.get("SUPPORT_EMAIL") or "").strip())
    contact = (
        f'<a href="mailto:{support}">{support}</a>' if support
        else "the support address in the Privacy Policy"
    )

    if done:
        return _page("Account deleted", (
            "<h1>Your account has been deleted</h1>"
            '<p class="done">Your AgriVision account and all of its data have '
            "been permanently deleted.</p>"
        ), status)

    alert = f'<p class="error">{html.escape(error)}</p>' if error else ""
    return _page("Delete your account", f"""
<h1>Delete your AgriVision account</h1>
<p>This permanently deletes your account and everything in it: your profile,
pilot credentials, drones, missions, surveys, spray plans, scans, photographs
and camera frames. <strong>It cannot be undone.</strong></p>

<h2>In the app</h2>
<p>Open AgriVision and go to <strong>Settings &rarr; Delete account</strong>.</p>

<h2>Here</h2>
<div class="card">
{alert}
<form method="post" action="/account/delete">
  <label for="email">Email address</label>
  <input id="email" name="email" type="email" autocomplete="email" required>
  <label for="password">Password</label>
  <input id="password" name="password" type="password"
         autocomplete="current-password" required>
  <button type="submit">Delete my account permanently</button>
</form>
</div>

<p class="muted">Signed up with Google? Your account has no AgriVision
password. Delete it from the app (Settings &rarr; Delete account), or email
{contact} from the Google address you signed in with and we will delete it
for you.</p>
""", status)


@legal_bp.route("/account/delete", methods=["GET"])
def delete_account_form():
    return _deletion_page()


@legal_bp.route("/account/delete", methods=["POST"])
@rate_limit("signin", "RATELIMIT_SIGNIN")
def delete_account_submit():
    email = (request.form.get("email") or "").strip().lower()
    password = request.form.get("password") or ""

    user = (
        User.query.filter(db.func.lower(User.email) == email).first()
        if email else None
    )
    if user is None:
        _burn_a_hash_check(password)
    # One message for every failure, so the form never confirms an account.
    if user is None or not password or not verify_password(user.password, password):
        return _deletion_page(
            error="That email address and password do not match an account.",
            status=400,
        )

    response, status = AccountService.delete_account(
        user.id, user.email, current_app.instance_path
    )
    if status != 200:
        return _deletion_page(error=response.get("message"), status=status)
    return _deletion_page(done=True)
