# 🔒 Guía de Seguridad — Hardening del origen tras Cloudflare

Objetivo: que el VPS **solo** sea accesible a través de Cloudflare, cifrado de
extremo a extremo, con el panel de administración fuera de internet. Aunque
alguien descubra la IP del VPS, no debe poder tocar el origen directamente.

Capas (todas suman, de borde a origen):

1. **Cloudflare Full (strict)** — cifrado Cloudflare ↔ origen validado.
2. **Cloudflare Origin Certificate** — cert del origen que solo Cloudflare confía.
3. **Authenticated Origin Pulls (mTLS)** — el origen rechaza lo que no venga de Cloudflare.
4. **Firewall (DOCKER-USER)** — a nivel red, solo IPs de Cloudflare llegan a 80/443.
5. **Panel NPM atado a localhost** — el `:81` nunca sale a internet.

---

## 1. Cloudflare — configuración de borde

Panel de Cloudflare, por cada dominio (zona):

- **SSL/TLS → Overview → Full (strict)**
- **SSL/TLS → Edge Certificates:**
  - *Always Use HTTPS* → ON
  - *Minimum TLS Version* → 1.2 (idealmente 1.3)
  - *HSTS* → ON (⚠️ una vez activo obliga HTTPS en navegadores; activarlo cuando
    confirmes que el HTTPS del sitio funciona)
- **SSL/TLS → Origin Server → Authenticated Origin Pulls** → ON (nivel zona)

## 2. Certificado de Origen (Cloudflare Origin CA)

En vez de Let's Encrypt, usamos un cert que **solo Cloudflare confía** (válido 15 años):

1. Cloudflare → **SSL/TLS → Origin Server → Create Certificate**.
2. Deja *Generate private key and CSR with Cloudflare*, hostnames:
   `hockeybariloche.com.ar`, `*.hockeybariloche.com.ar`.
3. Copia el **Origin Certificate** y la **Private Key**.
4. En NPM: **SSL Certificates → Add SSL Certificate → Custom** → pega cert + key.
5. En el Proxy Host (pestaña SSL) elige ese certificado. **No** actives “Request
   a new certificate” (ya no usamos Let's Encrypt para el origen).

> Ventaja: sin dependencia de renovaciones ni del DNS challenge, y el origen solo
> sirve tráfico confiado por Cloudflare.

## 3. Authenticated Origin Pulls (mTLS) en NPM

Hace que NPM **rechace** toda conexión que no presente el certificado cliente de
Cloudflare. Es la defensa clave contra el bypass del origen.

1. Descargar la CA de Cloudflare (ver [`cloudflare/README.md`](cloudflare/README.md)):
   ```bash
   curl -fsSL https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem \
     -o cloudflare/origin-pull-ca.pem
   ```
   `docker-compose.yml` ya la monta en `/etc/nginx/cloudflare/origin-pull-ca.pem`.

2. En el Proxy Host de NPM → pestaña **Advanced** → *Custom Nginx Configuration*:
   ```nginx
   # Authenticated Origin Pulls: exigir el certificado cliente de Cloudflare
   ssl_client_certificate /etc/nginx/cloudflare/origin-pull-ca.pem;
   ssl_verify_client on;
   ```

3. Guardar. A partir de aquí, un `curl https://IP_DEL_VPS` directo (sin pasar por
   Cloudflare) debe fallar con error de certificado — eso confirma que funciona.

## 4. Firewall — solo Cloudflare a 80/443

⚠️ **Docker se salta ufw.** Los puertos publicados por contenedores se filtran en
la cadena `DOCKER-USER`, no con `ufw allow`. El script
[`scripts/firewall.sh`](scripts/firewall.sh) hace ambas capas.

```bash
# Averiguar la interfaz pública
ip -o -4 route show to default        # ej: "default via ... dev eth0"

# Ejecutar DESPUÉS de docker compose up -d
WAN_IF=eth0 SSH_PORT=22 sudo ./scripts/firewall.sh
```

Qué hace:
- ufw: permite SSH, deniega el resto del tráfico entrante al host.
- `DOCKER-USER`: permite 80/443 **solo** desde los rangos de Cloudflare (IPv4+IPv6),
  descarta el resto.

**Persistencia:** las reglas `DOCKER-USER` se pierden si el daemon de Docker se
reinicia. Re-ejecutar el script al arrancar (unit de systemd o `@reboot`).

## 5. Panel de NPM — nunca público

En `docker-compose.yml` el panel está atado a `127.0.0.1:81:81`, así que no sale
a internet. Se accede por túnel SSH desde tu máquina:

```bash
ssh -L 81:localhost:81 usuario@IP_DEL_VPS
# luego abrir en el navegador: http://localhost:81
```

**Primer login** (cambiar de inmediato): `admin@example.com` / `changeme`.

## 6. Acceso a la base de datos (pgAdmin) por túnel SSH

La DB de cada app debe publicarse **solo en localhost** del VPS, nunca en
`0.0.0.0`. En la Página A ya está así:

```yaml
  db:
    ports:
      - "127.0.0.1:5434:5432"   # solo localhost → accesible vía túnel SSH
```

Desde tu PC, abrir el túnel y conectar pgAdmin a `localhost:5434`:

```bash
ssh -L 5434:localhost:5434 usuario@IP_DEL_VPS
```

pgAdmin → Host `localhost`, Port `5434`, credenciales del `.env`. El puerto 5434
no se expone a internet y el firewall no necesita abrirlo (el tráfico viaja
dentro de la conexión SSH). ⚠️ Nunca cambiar el binding a `0.0.0.0:5434`.

## 7. Uptime Kuma — monitoreo, nunca público

Igual que el panel de NPM: el dashboard queda atado a `127.0.0.1:3001` y se
accede por túnel SSH, no por Cloudflare/NPM.

```bash
ssh -L 3001:localhost:3001 usuario@IP_DEL_VPS
# luego abrir en el navegador: http://localhost:3001
```

Al estar en `proxy-network`, Kuma puede monitorear a los demás contenedores
por su nombre (ej. `http://mi-app:3000/health`) sin depender de que Cloudflare
o el DNS público estén arriba — importante para no perder la alerta justo
cuando falla la parte pública del sistema.

**Primer login:** lo pide Kuma al abrir el dashboard por primera vez (no hay
usuario por defecto). Elegí email/password fuertes ahí mismo.

## 8. Netdata — métricas de recursos, nunca público

Mismo patrón: dashboard atado a `127.0.0.1:19999`, acceso por túnel SSH.

```bash
ssh -L 19999:localhost:19999 usuario@IP_DEL_VPS
# luego abrir en el navegador: http://localhost:19999
```

Monta `/proc`, `/sys` y el socket de Docker **de solo lectura** para poder leer
métricas del host y de cada contenedor sin poder modificarlos. Los `cap_add`/
`security_opt` del compose son los que Netdata pide oficialmente para leer
esas métricas — no le dan privilegios de escritura sobre el host.

Las alertas (RAM/disco/CPU) se configuran dentro del contenedor, en
`health_alarm_notify.conf`, con el mismo bot de Telegram que ya usa Kuma.

---

## ✅ Checklist de verificación

- [ ] `curl -I https://hockeybariloche.com.ar` responde 200 vía Cloudflare.
- [ ] `curl -k https://IP_DEL_VPS` **falla** (mTLS rechaza el acceso directo).
- [ ] Puerto 81 no accesible desde internet (`nmap`/navegador externo).
- [ ] Cloudflare en Full (strict) + Authenticated Origin Pulls ON.
- [ ] `sudo iptables -L DOCKER-USER -n` muestra la allowlist de Cloudflare.
- [ ] Firewall se re-aplica tras reboot.
- [ ] DB accesible por túnel SSH (`localhost:5434`) y **no** desde internet.
- [ ] Uptime Kuma accesible por túnel SSH (`localhost:3001`) y **no** desde internet.
- [ ] Netdata accesible por túnel SSH (`localhost:19999`) y **no** desde internet.
