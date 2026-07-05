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
                 ┌──────┴──────┐
                 │             │
          ┌────────────┐ ┌────────────┐
          │  Página A  │ │  Página B  │
          └────────────┘ └────────────┘
```

## 📂 Estructura del Proyecto

```text
.
├── docker-compose.yml   # Orquestación de Nginx Proxy Manager
├── SECURITY.md          # Guía de hardening (SSL, mTLS, firewall)
├── scripts/
│   └── firewall.sh      # Allowlist de Cloudflare (ufw + DOCKER-USER)
├── cloudflare/
│   └── README.md        # Cómo obtener la CA de Authenticated Origin Pulls
├── .gitignore           # Ignora data/, letsencrypt/, la CA y secretos
├── data/                # (generado) Configuración y BD de NPM — NO se versiona
└── letsencrypt/         # (generado) Certificados SSL — NO se versiona
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
