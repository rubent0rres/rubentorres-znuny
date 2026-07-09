# Helpdesk Znuny 7.3.4 en Docker

Sistema de tickets **Znuny 7.3.4** (última versión estable, fork libre de OTRS)
desplegado con Docker Compose. La imagen de Znuny se **construye localmente**
desde el código fuente oficial, así que sale **nativa para tu arquitectura**
(en Apple Silicon corre nativa arm64, sin emulación).

Stack: contenedor Znuny (Apache2 + mod_perl2 + supervisor + daemon) +
PostgreSQL 16.

## Requisitos

- Docker Desktop en ejecución.
- La primera vez, `docker compose up -d --build` construye la imagen
  (descarga dependencias Perl y compila; tarda varios minutos).

## Puesta en marcha rápida

**Opción 1 — construir localmente (por defecto):**
```bash
git clone <este-repo> heldesk && cd heldesk
cp .env.example .env      # ajusta contraseñas
docker compose up -d --build
```

**Opción 2 — usar la imagen ya publicada en Docker Hub (sin compilar):**
```bash
cp .env.example .env
echo 'ZNUNY_IMAGE=TU_USUARIO/znuny:7.3.4' >> .env
docker compose pull && docker compose up -d
```
La imagen de Docker Hub es **multiarquitectura** (amd64 + arm64), así que corre
nativa tanto en Intel/AMD como en Apple Silicon.

## Acceso

| Interfaz          | URL                                             |
|-------------------|-------------------------------------------------|
| Agentes (admin)   | http://localhost:8080/otrs/index.pl             |
| Clientes          | http://localhost:8080/otrs/customer.pl          |

**Usuario administrador:** `root@localhost`
**Contraseña:** el valor de `ZNUNY_ROOT_PASSWORD` en `.env`

## Uso

```bash
# Construir (primera vez) y arrancar
docker compose up -d --build

# Arrancar (sin reconstruir)
docker compose up -d

# Estado / logs
docker compose ps
docker compose logs -f znuny

# Detener (conserva datos) / eliminar contenedores (datos persisten en volúmenes)
docker compose stop
docker compose down
```

## Estructura del proyecto

```
heldesk/
├── docker-compose.yml     # znuny (build local) + postgres:16-alpine
├── .env                   # config y contraseñas (NO se versiona)
├── .env.example           # plantilla versionable
├── build/                 # contexto de construcción de la imagen Znuny 7.3.4
│   ├── Dockerfile         # multi-stage, Debian 12 slim; descarga Znuny en el build
│   ├── docker-entrypoint.sh
│   ├── autoinstall.sh     # instalación automática de BD + admin
│   ├── upgrade.sh
│   ├── apache-znuny.conf
│   └── supervisord.conf
├── LICENSE
└── README.md
```

> Base del `build/`: proyecto MIT `andrey-n-safonov/znuny-dockerized`,
> modificado para fijar la versión **7.3.4** (se descarga del sitio oficial
> durante el build). El código de Znuny NO se incluye en el repo.

## Publicar / reconstruir la imagen multiarquitectura

Para publicar la imagen en Docker Hub para amd64 + arm64 (requiere `docker login`):

```bash
docker buildx create --name znuny-builder --use   # una sola vez
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t TU_USUARIO/znuny:7.3.4 -t TU_USUARIO/znuny:latest \
  --push ./build
```

Para otra versión de Znuny: `--build-arg ZNUNY_VERSION=7.3.5` (u otra).

## Datos y persistencia

Todo se guarda en **volúmenes nombrados** de Docker:

- `znuny_data`    → instalación y config de Znuny (`/opt/znuny`)
- `postgres_data` → base de datos PostgreSQL

```bash
docker volume ls | grep -E 'znuny|postgres'
```

> `.env` y el tarball grande no se versionan (ver `.gitignore`).

## Instalación automática

El contenedor Znuny se auto-instala en el primer arranque
(`ZNUNY_AUTO_INSTALL=true`): espera a PostgreSQL, crea el `Kernel/Config.pm`,
importa el esquema, aplica `ZNUNY_ROOT_PASSWORD` y configura FQDN, SecureMode
y logs. Es **idempotente**: en arranques posteriores detecta que ya está
instalado (flag `var/.znuny_installed`) y no reinstala.

## Respaldo de la base de datos

```bash
# Respaldo
docker compose exec postgres pg_dump -U znuny znuny > respaldo.sql

# Restauración (con el stack arriba y la BD vacía)
cat respaldo.sql | docker compose exec -T postgres psql -U znuny -d znuny
```

## Reinstalar desde cero

```bash
docker compose down -v      # elimina también los volúmenes (¡borra datos!)
docker compose up -d --build
```

## Portabilidad

En otra máquina con Docker: copia el proyecto (o clónalo), `cp .env.example .env`,
ajusta contraseñas y `docker compose up -d --build`. La imagen se reconstruye
nativa para esa arquitectura. Esto reproduce la **instalación**, no tus datos;
para migrar datos usa el respaldo `pg_dump` de arriba.

## Notas de versión

- Znuny **7.3.4** (última estable de la línea 7.x al momento del build).
- Znuny no publica imágenes Docker oficiales; por eso se construye localmente.
