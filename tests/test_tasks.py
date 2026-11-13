def test_get_tasks_returns_list(client, mock_cursor):
    mock_cursor.fetchall.return_value = [(1, "Comprar leche"), (2, "Estudiar")]

    response = client.get("/tasks")

    assert response.status_code == 200
    assert response.get_json() == [
        {"id": 1, "tarea": "Comprar leche"},
        {"id": 2, "tarea": "Estudiar"},
    ]


def test_post_tasks_creates_task(client, mock_cursor):
    mock_cursor.fetchone.return_value = (1, "hola desde RDS")

    response = client.post("/tasks", json={"tarea": "hola desde RDS"})

    assert response.status_code == 201
    assert response.get_json() == {"id": 1, "tarea": "hola desde RDS"}
    # verifica que se inserto con parametros
    args = mock_cursor.execute.call_args[0]
    assert "INSERT INTO tasks" in args[0]
    assert args[1] == ("hola desde RDS",)


def test_post_tasks_without_tarea_field_returns_400(client, mock_cursor):
    response = client.post("/tasks", json={"notarea": "opasdifj"})

    assert response.status_code == 400
    assert "tarea" in response.get_json()["error"]
    mock_cursor.execute.assert_not_called()  # checar que no toco RDS
