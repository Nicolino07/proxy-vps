# proxy-vps

Proxy inverso global basado en **Nginx Proxy Manager (NPM)** y Docker para la
orquestación y enrutamiento de múltiples aplicaciones independientes en el VPS.

Funciona como el único punto de entrada (puertos **80/443**) y redirige el
tráfico por dominio a cada aplicación, detrás de **Cloudflare** con cifrado de
extremo a extremo (**Full strict** + **Authenticated Origin Pulls**).

> 🔒 **El hardening de seguridad está en [`SECURITY.md`](SECURITY.md)** — léelo
> antes de exponer el VPS a internet. Cubre el certificado de origen, mTLS,
> firewall (con el detalle de que **Docker se salta ufw**) y el aislamiento del
> panel de administración.

## 🏗️ Arquitectura del Sistema

```text
                    Internet
                       │
                  :80 / :443
                       │
              ┌────────────────────┐
              │ Nginx Proxy Manager│  ← Panel web en :81
              └─────────┬──────────┘
                        │
             red docker: proxy-network
                 ┌──────┼──────────────┐
                 │      │              │
          ┌────────────┐ ┌────────────┐ ┌────────────┐
          │  Página A  │ │  Página B  │ │Uptime Kuma │  ← Dashboard en :3001
          └────────────┘ └────────────┘ └────────────┘
```

`Página A/B` y **Uptime Kuma** están al mismo nivel: el proxy no distingue
entre "una app" y "el monitor", ambos son contenedores en `proxy-network`.
Kuma solo se diferencia en que su puerto no pasa por Cloudflare (ver abajo).

## 📂 Estructura del Proyecto

```text
.
├── docker-compose.yml   # Orquestación de Nginx Proxy Manager + Uptime Kuma
├── SECURITY.md          # Guía de hardening (SSL, mTLS, firewall)
├── scripts/
│   └── firewall.sh      # Allowlist de Cloudflare (ufw + DOCKER-USER)
├── cloudflare/
│   └── README.md        # Cómo obtener la CA de Authenticated Origin Pulls
├── .gitignore           # Ignora data/, letsencrypt/, uptime-kuma-data/, la CA y secretos
├── data/                # (generado) Configuración y BD de NPM — NO se versiona
├── letsencrypt/         # (generado) Certificados SSL — NO se versiona
└── uptime-kuma-data/    # (generado) Configuración y BD de Uptime Kuma — NO se versiona
```

> La red `proxy-network` la crea este compose. Cada aplicación se conecta a ella
> como red **externa** para que el proxy pueda enrutar su tráfico.

## 🚀 Despliegue en el VPS

```bash
# 1. Clonar el repo en el VPS
git clone git@github.com:Nicolino07/proxy-vps.git
cd proxy-vps

# 2. Levantar el proxy
docker compose up -d

# 3. Acceder al panel de administración
#    http://<IP_DEL_VPS>:81
#    Credenciales por defecto:
#      Email:    admin@example.com
#      Password: changeme
#    (NPM obliga a cambiarlas en el primer login)
```

## 🔗 Conectar una aplicación al proxy

En el `docker-compose.yml` de cada app:

1. **Eliminar** el mapeo público de `ports:` (el proxy habla con la app por la
   red interna; no debe quedar expuesta al host).
2. Añadir la app a la red externa `proxy-network`.

```yaml
services:
  mi-app:
    # ports:                 # ← eliminar exposición pública
    #   - "3000:3000"
    expose:
      - "3000"               # solo visible dentro de la red docker
    networks:
      - default
      - proxy-network

networks:
  proxy-network:
    external: true
```

Luego, en el panel de NPM → **Hosts → Proxy Hosts → Add Proxy Host**:

- **Domain Names:** `midominio.com`
- **Forward Hostname / IP:** nombre del contenedor (ej. `mi-app`)
- **Forward Port:** puerto interno (ej. `3000`)
- Pestaña **SSL** → certificado **Custom** (Cloudflare Origin) — ver
  [`SECURITY.md`](SECURITY.md).

## 🔑 SSL — ver SECURITY.md

El SSL del origen se resuelve con un **Cloudflare Origin Certificate** +
**Authenticated Origin Pulls (mTLS)**, no con Let's Encrypt. El procedimiento
completo (borde, certificado, mTLS y firewall) está en [`SECURITY.md`](SECURITY.md).

## 📈 Monitoreo — Uptime Kuma

`docker-compose.yml` levanta **Uptime Kuma** junto a NPM. Es "¿está vivo o
no?" con alertas — el acceso al dashboard sigue el mismo patrón de seguridad
que el panel de NPM: atado a `127.0.0.1:3001`, nunca público, se accede por
túnel SSH (ver [`SECURITY.md`](SECURITY.md#7-uptime-kuma--monitoreo-nunca-público)).

**Primera vez:**

```bash
docker compose up -d
ssh -L 3001:localhost:3001 usuario@IP_DEL_VPS
# abrir http://localhost:3001 y crear el usuario admin
```

**Configurar alertas a Telegram** (Settings → Notifications → Setup Notification):

1. Hablar con [@BotFather](https://t.me/BotFather) en Telegram → `/newbot` → copiar el token.
2. Escribirle cualquier mensaje al bot recién creado (para que pueda responderte).
3. Obtener tu `chat_id`: abrir
   `https://api.telegram.org/bot<TOKEN>/getUpdates` y buscar el campo `chat.id`.
4. En Kuma: tipo *Telegram*, pegar el bot token y el chat ID, **Save**.
5. Marcarla como notificación por defecto para que se aplique a los monitores nuevos.

**Qué monitorear (mínimo):**

- Cada dominio público (Página A, Página B, y a futuro el sitio de pagos), como
  monitor tipo *HTTP(s)* apuntando al dominio público (valida también que
  Cloudflare + NPM + mTLS estén sirviendo bien de punta a punta).
- El endpoint de health-check de cada app por su nombre de contenedor interno
  (ej. `http://mi-app:3000/health`) — detecta caídas aunque Cloudflare siga
  respondiendo con una página de error.
- El día que esté el sistema de pagos: el **endpoint del webhook** específicamente
  (si deja de responder, dejás de cobrar sin enterarte) y el certificado SSL
  (Kuma avisa si vence en menos de N días).

**Netdata** cubre "¿por qué se cayó / qué se está por caer?" con métricas de
CPU/RAM/disco/red del host y por contenedor. Mismo patrón de acceso que Kuma:

```bash
ssh -L 19999:localhost:19999 usuario@IP_DEL_VPS
# abrir http://localhost:19999
```

**Configurar alertas a Telegram** (usa el mismo bot y chat ID que ya armaste
para Kuma). Se hace por consola, sin editor interactivo, en un solo comando
(reemplazando `<TOKEN>` y `<CHAT_ID>` por los tuyos):

```bash
docker exec netdata bash -c '
cp -f /usr/lib/netdata/conf.d/health_alarm_notify.conf /etc/netdata/health_alarm_notify.conf
sed -i "s/^SEND_TELEGRAM=.*/SEND_TELEGRAM=\"YES\"/" /etc/netdata/health_alarm_notify.conf
sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=\"<TOKEN>\"|" /etc/netdata/health_alarm_notify.conf
sed -i "s/^DEFAULT_RECIPIENT_TELEGRAM=.*/DEFAULT_RECIPIENT_TELEGRAM=\"<CHAT_ID>\"/" /etc/netdata/health_alarm_notify.conf
'
docker compose restart netdata
docker exec -it netdata /usr/libexec/netdata/plugins.d/alarm-notify.sh test
```

El `hostname` del servicio en `docker-compose.yml` (ej. `vps-nico-srv1421620`)
es lo que identifica al servidor dentro del mensaje de Telegram — sin esto,
la alerta te muestra el ID interno del contenedor, ilegible.

**Ajuste de performance (recomendado):** por defecto Netdata recolecta cada
1 segundo y corre detección de anomalías por ML sobre cada métrica, lo cual
en un VPS de 2 cores se notó como ~8-10% de CPU sostenido. Bajarlo a cada 5
segundos y desactivar el ML lo deja en ~2% sin perder las alertas por umbral
(RAM/disco/CPU). **Este archivo vive en un volumen de Docker
(`netdataconfig`), no en el repo — si se recrea el VPS desde cero hay que
volver a crearlo:**

```bash
docker exec netdata bash -c 'cat > /etc/netdata/netdata.conf <<EOF
[global]
    update every = 5

[ml]
    enabled = no
EOF'
docker compose restart netdata
```

Netdata ya trae umbrales por defecto razonables (ej. RAM/disco al 80-90%,
picos de carga) sin que definas nada — con esto alcanza para empezar. Ajustar
umbrales puntuales se hace en `/etc/netdata/health.d/*.conf` si en algún
momento las alertas por defecto resultan muy sensibles o muy laxas.

### ¿Cuándo te avisa por Telegram?

- **Kuma** (cada 60s, 2 reintentos antes de alertar): si `www.hockeybariloche.com.ar`
  o `www.asociacionaustraldehockey.com.ar` dejan de responder, o si el
  certificado SSL de alguno está por vencer.
- **Netdata**: RAM o disco por arriba de ~80-90%, carga de CPU sostenida
  anormal, y otros chequeos de sistema por defecto (swap, inodos, etc.).
- Cada alerta llega en 3 etapas — **warning → critical → recovered** — así
  sabés cuándo empezó el problema y cuándo se resolvió solo.
- **Pendiente:** cuando se integre el sistema de pagos, sumar un monitor de
  Kuma específico para el endpoint del webhook de Mercado Pago.
