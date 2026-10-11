#!/usr/bin/env bash
# Guion de validacion del Pre-Laboratorio 7 (Pasos 1 a 4).
# Ejecuta cada comando del enunciado, muestra un encabezado antes de cada uno
# y guarda una copia de toda la salida en evidencias/salida_<fecha>.txt.
# Uso:  ./validacion.sh          (ejecuta todo de corrido)
#       PAUSA=1 ./validacion.sh  (se detiene despues de cada paso para tomar la captura)

set -u
mkdir -p evidencias
LOG="evidencias/salida_$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee -a "$LOG") 2>&1

paso() {
  echo
  echo "=================================================================="
  echo ">>> $*"
  echo "=================================================================="
}
pausa() { if [ "${PAUSA:-0}" = "1" ]; then read -rp "[Enter para continuar] " _ </dev/tty; fi; }
cmd() { echo "\$ $*"; eval "$@"; echo; }

paso "PASO 1 - Construccion de la imagen"
cmd docker build -t lab-so-web:v1 .
cmd docker images lab-so-web
cmd docker history lab-so-web:v1
pausa

paso "PASO 3.1 - Levantar los servicios en segundo plano"
cmd docker compose up -d
sleep 3
cmd docker compose ps
if [ -z "$(docker ps -q -f name=^nodo_db$)" ] || [ -z "$(docker ps -q -f name=^nodo_web$)" ]; then
  echo "ERROR: nodo_web o nodo_db no estan corriendo. Revise 'docker compose logs' antes de seguir."; exit 1
fi
pausa

paso "PASO 3.2 - Consultas HTTP (total_visitas debe crecer 1, 2, 3...)"
cmd curl -s http://127.0.0.1:8080/
cmd curl -s http://127.0.0.1:8080/
cmd curl -s http://127.0.0.1:8080/
pausa

paso "PASO 3.3 - Persistencia: down (sin -v), el volumen sobrevive"
cmd time docker compose down
cmd docker volume ls
cmd docker compose up -d
sleep 3
cmd curl -s http://127.0.0.1:8080/
pausa

paso "PASO 3.4 - down -v destruye el volumen: el contador vuelve a 1"
cmd docker compose down -v
cmd docker volume ls
cmd docker compose up -d
sleep 3
cmd curl -s http://127.0.0.1:8080/
pausa

paso "PASO 4.1 - PID dentro del contenedor vs PID en el host"
cmd docker exec nodo_db ps aux
cmd "ps -ef | grep [r]edis-server"
PID_HOST=$(docker inspect -f '{{.State.Pid}}' nodo_db)
echo "PID de redis-server en el host (docker inspect): $PID_HOST"
cmd "grep NSpid /proc/$PID_HOST/status"
pausa

paso "PASO 4.2 - Namespaces del contenedor vs namespaces de esta terminal"
cmd sudo ls -l /proc/$PID_HOST/ns/
cmd ls -l /proc/$$/ns/
echo "Comparacion namespace por namespace (inodo contenedor | inodo terminal):"
for ns in cgroup ipc mnt net pid pid_for_children time time_for_children user uts; do
  a=$(sudo readlink /proc/$PID_HOST/ns/$ns 2>/dev/null); b=$(readlink /proc/$$/ns/$ns 2>/dev/null)
  if [ -z "$a" ] || [ -z "$b" ]; then estado="(no disponible)"
  elif [ "$a" = "$b" ]; then estado="COMPARTIDO con el host"; else estado="AISLADO (propio del contenedor)"; fi
  printf "  %-18s %-22s %-22s %s\n" "$ns" "$a" "$b" "$estado"
done
pausa

paso "PASO 4.3 - Bridge y pares veth en el host"
cmd docker network ls
cmd "docker network inspect lab_docker_red-so-interna --format '{{json .IPAM.Config}}' 2>/dev/null || docker network inspect \$(docker network ls -q --filter name=red-so-interna) --format '{{json .IPAM.Config}}'"
if command -v ip >/dev/null; then
  cmd "ip link show | grep -E -A1 'br-|docker0|veth'"
  cmd "ip -br addr show | grep -E 'br-|docker0'"
else
  echo "(el comando ip no esta instalado; se listan las interfaces desde /sys/class/net)"
  cmd "ls -l /sys/class/net | grep -E 'br-|docker0|veth'"
fi
echo "Puente al que esta conectado cada veth:"
for v in /sys/class/net/veth*; do [ -e "$v" ] && echo "  $(basename $v) -> $(basename $(readlink $v/master 2>/dev/null) 2>/dev/null)"; done
pausa

paso "EXTRA - PID 1 y SIGTERM (pregunta 8 del marco teorico)"
echo "nodo_db (redis maneja SIGTERM) vs nodo_web (python como PID 1, sin manejador):"
for c in nodo_db nodo_web; do
  s=$(date +%s); docker stop $c >/dev/null; e=$(date +%s)
  echo "  docker stop $c -> $((e - s)) s, codigo de salida $(docker inspect -f '{{.State.ExitCode}}' $c)"
done
echo "Con --init (tini como PID 1 reenvia la senal):"
docker run -d --init --name prueba_init lab-so-web:v1 >/dev/null; sleep 2
s=$(date +%s); docker stop prueba_init >/dev/null; e=$(date +%s)
echo "  docker stop prueba_init -> $((e - s)) s, codigo de salida $(docker inspect -f '{{.State.ExitCode}}' prueba_init)"
docker rm prueba_init >/dev/null
cmd docker compose down
pausa

echo
echo "Listo. Salida completa guardada en $LOG"
