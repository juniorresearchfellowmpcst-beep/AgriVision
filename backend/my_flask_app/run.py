import os

from app import create_app

app = create_app()


def _flag(name: str, default: bool) -> bool:
    return str(os.environ.get(name, default)).strip().lower() in (
        "1", "true", "yes", "on", "True",
    )


if __name__ == "__main__":
    # The auto-reloader is a problem specifically for flight testing: the
    # MAVLink link lives inside this process, so every saved file restarts the
    # server and silently drops the connection to the vehicle. The app then
    # shows a link that no longer exists until it next polls. Requests during
    # the restart window fail outright.
    #
    # Editing code -> leave it on. Flying a mission -> FLASK_RELOAD=0.
    use_reloader = _flag("FLASK_RELOAD", True)
    debug = _flag("FLASK_DEBUG", True)

    if debug and not use_reloader:
        print("Reloader disabled — restart manually after editing code.")

    app.run(
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 5000)),
        debug=debug,
        use_reloader=use_reloader,
    )
