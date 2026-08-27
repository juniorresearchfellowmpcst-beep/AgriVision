"""Development entry point, and the WSGI object gunicorn imports.

``app`` at module level is what ``gunicorn ... run:app`` loads. The
``__main__`` block below is *only* for running at a desk — a production
deployment goes through gunicorn (see ``gunicorn.conf.py`` and the root
Procfile), because Flask's built-in server is single-threaded by default and
would let one MJPEG viewer block every other request.
"""

import os

from app import create_app

app = create_app()


def _flag(name: str, default: bool) -> bool:
    return str(os.environ.get(name, default)).strip().lower() in (
        "1", "true", "yes", "on", "True",
    )


if __name__ == "__main__":
    production = app.config.get("APP_ENV") == "production"

    # The auto-reloader is a problem specifically for flight testing: the
    # MAVLink link and the camera streams live inside this process, so every
    # saved file restarts the server and silently drops the connection to the
    # vehicle and to every camera. The app then shows a link that no longer
    # exists until it next polls. Requests during the restart window fail
    # outright.
    #
    # Editing code -> leave it on. Flying a mission -> FLASK_RELOAD=0.
    use_reloader = _flag("FLASK_RELOAD", not production)
    debug = _flag("FLASK_DEBUG", not production)

    if production:
        # Werkzeug's server would still serve requests here, just badly and
        # without the thread pool the relay needs. Saying so is cheaper than
        # debugging why the live view stutters under two viewers.
        print(
            "WARNING: APP_ENV=production but this is Flask's development "
            "server. Serve it with:\n"
            "  gunicorn -c gunicorn.conf.py run:app"
        )

    if debug and not use_reloader:
        print("Reloader disabled — restart manually after editing code.")

    app.run(
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 5000)),
        debug=debug,
        use_reloader=use_reloader,
        # The relay holds a thread per viewer, and the dev server is
        # single-threaded without this — one open live view would block the
        # whole app, which looks exactly like the server having crashed.
        threaded=True,
    )
