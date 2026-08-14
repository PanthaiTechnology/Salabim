from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_ok():
    response = client.get("/v1/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert set(body["providers"].keys()) == {
        "audd", "acrcloud", "acrcloud_fingerprint", "odesli", "musixmatch", "spotify",
    }


def test_root():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["app"] == "Salabim"
