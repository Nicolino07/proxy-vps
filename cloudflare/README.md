# cloudflare/

Aquí va el certificado CA de **Authenticated Origin Pulls** de Cloudflare, que
NPM usa para verificar (mTLS) que cada conexión proviene realmente de Cloudflare.

Descargarlo en el VPS **antes** de `docker compose up -d`:

```bash
curl -fsSL https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem \
  -o cloudflare/origin-pull-ca.pem
```

> Este archivo es público (la CA de Cloudflare), no es un secreto.
> `docker-compose.yml` lo monta en `/etc/nginx/cloudflare/origin-pull-ca.pem`.
> Si el archivo no existe al levantar, Docker crearía un directorio en su lugar
> y el mTLS fallaría — por eso se descarga primero.
