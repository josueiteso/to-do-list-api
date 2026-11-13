import pytest
from unittest.mock import MagicMock, patch
import json
import os

# app.py exige estas variables al importarse
os.environ.setdefault("DB_SECRET_NAME", "test-secret")
os.environ.setdefault("AWS_REGION", "us-east-1")

TEST_SECRET = {
    "username": "user123",
    "password": "password",
    "host": "localhost",
    "port": 5432,
    "dbname": "testdb",
}


@pytest.fixture(scope="session")
def app_module():
    # importa tasks.py con secrets manager y psycopg2 mockeados
    mock_client = MagicMock()
    mock_client.get_secret_value.return_value = {
        "SecretString": json.dumps(TEST_SECRET)
    }
    with patch("boto3.client", return_value=mock_client), patch("psycopg2.connect"):
        import tasks as module
    return module


@pytest.fixture
def client(app_module):
    app_module.app.config["TESTING"] = True
    return app_module.app.test_client()


@pytest.fixture
def mock_cursor(app_module, monkeypatch):
    # reemplaza get_conn() por un mock y devuelve su cursor
    conn = MagicMock()
    cursor = conn.cursor.return_value.__enter__.return_value
    monkeypatch.setattr(app_module, "get_conn", lambda: conn)
    return cursor
