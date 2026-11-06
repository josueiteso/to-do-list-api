from flask import Flask, request, jsonify

app = Flask(__name__)

# Lista de tareas en memoria
tasks = []


@app.route("/tasks", methods=["GET"])
def get_tasks():
    return jsonify(tasks), 200


@app.route("/tasks", methods=["POST"])
def add_task():
    data = request.get_json(silent=True)

    if not data or "tarea" not in data:
        return jsonify({"error": "El campo 'tarea' es requerido"}), 400

    nueva_tarea = {"id": len(tasks) + 1, "tarea": data["tarea"]}

    tasks.append(nueva_tarea)

    return jsonify(nueva_tarea), 201


if __name__ == "__main__":
    app.run(host="0.0.0.0", debug=True, port=5000)
