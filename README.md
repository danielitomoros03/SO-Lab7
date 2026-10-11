# Pre-Laboratorio 7: Contenerización y Docker

Sistemas Operativos (6004), UCV, semestre I-2026.

Contador de visitas distribuido con dos contenedores conectados por una red bridge privada:

- **`nodo_web`**: API Flask construida con el `Dockerfile` de este repositorio.
- **`nodo_db`**: Redis (`redis:alpine`) con persistencia AOF en el volumen `datos-redis`.

```
Host :8080 ──► nodo_web (Flask :5000) ──DNS: nodo_db──► nodo_db (Redis :6379) ──► volumen datos-redis (/data)
                      └──────────── red bridge red-so-interna ────────────┘
```

## Archivos

| Archivo | Contenido |
|---|---|
| `app.py` | Servidor Flask. Cada `GET /` hace `INCR contador_visitas` en Redis y responde en JSON. |
| `requirements.txt` | Dependencias: `flask==3.0.3` y `redis==5.0.4`. |
| `Dockerfile` | Imagen `lab-so-web:v1` sobre `python:3.11-alpine`. Copia primero las dependencias para aprovechar la caché de capas. |
| `docker-compose.yml` | Servicios `web` y `db-redis`, red `red-so-interna` y volumen `datos-redis`. |
| `.dockerignore` | Deja fuera del contexto de construcción lo que la imagen no necesita. |
| `validacion.sh` | Ejecuta los pasos 1 a 4 del enunciado y guarda la salida en `evidencias/`. |

## Requisitos

- **Docker Engine con el plugin Compose v2** (el comando es `docker compose`, sin guion).
- **Linux nativo o WSL2.** Los pasos 4.1 a 4.3 (ver el proceso con `ps -ef`, revisar `/proc/<PID>/ns/` y usar `ip link`) necesitan que los contenedores corran en el mismo kernel que la terminal. Con **Docker Desktop** en Windows o macOS, los contenedores viven dentro de una máquina virtual oculta, así que `ps -ef` en el host **no** muestra `redis-server`. En ese caso, abre una terminal dentro de esa VM con:
  ```bash
  docker run -it --rm --privileged --pid=host alpine nsenter -t 1 -m -u -n -i sh
  ```
  Desde ahí puedes ejecutar `ps`, `ls -l /proc/<PID>/ns/` e `ip link`.

## Uso rápido

```bash
git clone <URL-de-este-repositorio> lab_docker
cd lab_docker
chmod +x validacion.sh
PAUSA=1 ./validacion.sh     # se detiene en cada paso para tomar la captura
```

El nombre de la carpeta importa: Compose lo usa como prefijo. Con la carpeta `lab_docker`, los recursos se llaman `lab_docker_red-so-interna` y `lab_docker_datos-redis`, igual que en la salida esperada del enunciado.

## Comandos del enunciado, uno por uno

```bash
# Paso 1: construcción
docker build -t lab-so-web:v1 .
docker images

# Paso 3: ciclo de vida y persistencia
docker compose up -d
docker compose ps
curl http://127.0.0.1:8080/          # total_visitas = 1
curl http://127.0.0.1:8080/          # total_visitas = 2
docker compose down                  # quita contenedores y red; el volumen queda
docker volume ls                     # aparece lab_docker_datos-redis
docker compose up -d
curl http://127.0.0.1:8080/          # total_visitas = 3: el contador continúa
docker compose down -v               # -v también borra el volumen
docker compose up -d
curl http://127.0.0.1:8080/          # total_visitas = 1: empieza de nuevo

# Paso 4: inspección de namespaces
docker exec nodo_db ps aux                       # redis-server es el PID 1 dentro del contenedor
ps -ef | grep redis-server                       # el mismo proceso con su PID global en el host
docker inspect -f '{{.State.Pid}}' nodo_db       # otra forma de obtener el PID del host
sudo ls -l /proc/<PID_HOST>/ns/
ls -l /proc/$$/ns/
ip link show                                     # br-xxxx (red del compose), docker0 y veth*
```

## Notas

- **Aviso `version` is obsolete:** Compose v2 muestra este aviso por la línea `version: '3.8'`. Es inofensivo y se dejó porque así viene en el enunciado.
- **Subred:** el diagrama del enunciado muestra la subred `172.28.0.0/16`, pero el `docker-compose.yml` no la fija, así que Docker asigna una libre (por ejemplo `172.18.0.0/16`). Para usar exactamente la del diagrama, agrega en la red:
  ```yaml
      ipam:
        config:
          - subnet: 172.28.0.0/16
  ```
- **`docker compose down` tarda unos 10 s en `nodo_web`.** Python corre como PID 1 y no instala un manejador para SIGTERM, así que el kernel ignora la señal. Docker espera 10 s y termina el proceso con SIGKILL, y el contenedor sale con código **137** (128 + 9). Con `init: true` en el servicio (o `docker run --init`), `tini` es el PID 1 y reenvía la señal: el contenedor se detiene al instante con código **143** (128 + 15). El script `validacion.sh` lo mide al final.

