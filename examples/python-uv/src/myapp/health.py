"""The answer of /healthz: liveness for the container health check, the reverse proxy and
dev-kit deploy, which waits until it reports the version it deployed."""

from importlib.metadata import version


def health() -> dict[str, str]:
    return {"status": "ok", "version": version("myapp")}
