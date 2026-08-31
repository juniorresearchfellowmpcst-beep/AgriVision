# Railway/Heroku start command. The build runs from the repo ROOT, so this has
# to reach into backend/my_flask_app itself.
#
# `cd` rather than gunicorn's own --chdir, and that is not a style choice.
# gunicorn resolves `-c <file>` in load_config(), and command-line settings —
# --chdir among them — are only applied to the config AFTER that. So the
# earlier `gunicorn --chdir backend/my_flask_app -c gunicorn.conf.py` looked
# for the config file in the repo root, never found it, and the deploy
# crash-looped on "Error: 'gunicorn.conf.py' doesn't exist". Changing
# directory before gunicorn starts leaves one unambiguous working directory
# for the config file, the `run:app` import and the instance folder alike.
#
# `release` runs before the new version takes traffic: production has
# AUTO_CREATE_TABLES off, so a model added since the last deploy only reaches
# the database through a migration.
#
# NOTE: `release:` is a Heroku convention and Railway does not honour it, so
# the same migration is declared as `deploy.preDeployCommand` in railway.json.
# Both are kept and must stay in step: `flask db upgrade` is idempotent
# (alembic records the revision), so running it twice costs nothing and
# running it zero times leaves every /api/survey call answering 500.
release: cd backend/my_flask_app && flask --app run:app db upgrade
web: cd backend/my_flask_app && gunicorn -c gunicorn.conf.py run:app
