# to-do-list-api

API REST sencilla para gestionar tareas pendientes. Escrita en Python con Flask + PostgreSQL (RDS) y desplegada a AWS con Terraform y Github Actions.

# Ejecucion

## Pre-requisitos

### Crea el bucket S3 del tfstate:

```bash
./scripts/create_bucket.sh
```

### Crear el par de llaves SSH

```bash
ssh-keygen -t ed25519 -f ./tasks-key -N ""
```

Esto crea tasks-key (privada, no la compartas) y tasks-key.pub (publica).

### Configurar los secrets en GitHub:

`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` (credenciales AWS)

`TFSTATE_BUCKET` (el bucket que creaste)

`SSH_PRIVATE_KEY` (contenido de la llave privada)

`PERMITTED_IP_CIDR` (direccion IP permitida para SSH en notacion CIDR)

`ALERT_EMAIL` (email que recibira las alertas)

## Flujo

1. Ejecuta el workflow Terraform Apply y confirma la suscripción SNS desde el correo.
2. Ejecuta el workflow Deploy con cualquier release. Si no hay releases, puedes crearlos:
   
   ```
   git tag v1.0.0
   
   git push origin v1.0.0
   ```
3. Probar `GET http://<ip_ec2>:5000/health`. Verifica que la version sea de la release que desplegaste.
4. Cuando termines, corre el workflow Terraform Destroy. Los recursos se destruiran con excepcion del bucket de S3.

Puedes eliminar el bucket S3 pero practicamente no genera costo (solo guarda un item) y mantenerlo te ahorrara correr create_bucket.sh cada ves que quieras usar la app.

Ten en cuenta que las credenciales de learner lab son temporales. Actualiza los 3 secrets de AWS en cada sesion.

Tanmbien cada ves que hagas destroy y apply, la suscripcion a SNS se recrea y tendras que confirmarla de nuevo.

# Endpoints

`GET /tasks`: regresa la lista de tareas creadas.

`POST /tasks`: crea una tarea y la guarda en RDS.

`GET /version`: regresa la versión de la aplicación desplegada en un release de github.

`GET /health`: regresa el estado de la base de datos y la version.

# Monitoreo

| Alarma | Metrica | Descripcion |
| --- | --- | --- |
| tasks-ec2-status-check-failed | StatusCheckFailed (AWS) | Estatus de la instancia EC2 |
| tasks-app-db-errors | DbErrors (app) | Errores de base de datos |
| tasks-app-tasks-created-spike | TasksCreated (app) | Pico en creacion de tareas |

