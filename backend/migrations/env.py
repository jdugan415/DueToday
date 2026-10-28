"""Alembic environment: runs migrations against $DATABASE_URL (or an explicit
``sqlalchemy.url`` set by tests) using the app's own engine settings."""

from logging.config import fileConfig

from alembic import context

from app.database import DATABASE_URL, Base, make_engine, normalize_database_url

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name, disable_existing_loggers=False)

target_metadata = Base.metadata
url = normalize_database_url(config.get_main_option("sqlalchemy.url") or DATABASE_URL)


def run_migrations_offline() -> None:
    context.configure(url=url, target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    engine = make_engine(url)
    with engine.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            render_as_batch=connection.dialect.name == "sqlite",
        )
        with context.begin_transaction():
            context.run_migrations()
    engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
