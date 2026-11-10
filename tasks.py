from flask import Flask, request, jsonify
import boto3
import psycopg2
import json
import os
from contextlib import closing

app = Flask(__name__)

SECRET_NAME = os.environ["DB_SECRET_NAME"]
AWS_REGION = os.environ["AWS_REGION"]


def get_rds_credentials():
    client = boto3.client("secretsmanager", region_name=AWS_REGION)
    response = client.get_secret_value(SecretId=SECRET_NAME)
    return json.loads(response["SecretString"])


DB = get_rds_credentials()


def get_conn():
    return psycopg2.connect(
        host=DB["host"],
        port=DB["port"],
        dbname=DB["dbname"],
        user=DB["username"],
        password=DB["password"],
        sslmode="require",
        connect_timeout=5,
    )


def init_db():
    with closing(get_conn()) as conn, conn, conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id SERIAL PRIMARY KEY,
                tarea TEXT NOT NULL
            )
            """)


init_db()


@app.route("/tasks", methods=["GET"])
def get_tasks():
    try:
        with closing(get_conn()) as conn, conn, conn.cursor() as cur:
            cur.execute("SELECT id, tarea FROM tasks ORDER BY id")
            tasks = [{"id": r[0], "tarea": r[1]} for r in cur.fetchall()]
        return jsonify(tasks), 200
    except psycopg2.Error as e:
        app.logger.error("DB error: %s", e)
        return jsonify({"error": "Error de base de datos"}), 500


@app.route("/tasks", methods=["POST"])
def add_task():
    data = request.get_json(silent=True)

    if not data or "tarea" not in data:
        return jsonify({"error": "El campo 'tarea' es requerido"}), 400

    try:
        with closing(get_conn()) as conn, conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO tasks (tarea) VALUES (%s) RETURNING id, tarea",
                (data["tarea"],),
            )
            row = cur.fetchone()
        return jsonify({"id": row[0], "tarea": row[1]}), 201
    except psycopg2.Error as e:
        app.logger.error("DB error: %s", e)
        return jsonify({"error": "Error de base de datos"}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", debug=True, port=5000)
