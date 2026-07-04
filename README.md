# proxy-vps
Proxy inverso global basado en Nginx y Docker para la orquestación y enrutamiento de múltiples aplicaciones independientes en el VPS.

# VPS Reverse Proxy (Nginx)

Este repositorio contiene la configuración del proxy inverso global para nuestro VPS utilizando **Nginx** y **Docker**. Funciona como el único punto de entrada (Puerto 80/443) y redirige el tráfico de forma independiente a las distintas aplicaciones web alojadas en el servidor.

## 🏗️ Arquitectura del Sistema

              [ Tráfico de Internet ]
                         │
          ┌──────────────┴──────────────┐
          │  Puerto 80/443 (Nginx-Proxy)│
          └──────────────┬──────────────┘
                         │
          (Docker Network: proxy-network)
                ┌────────┴────────┐ 
                │                 │
     ┌──────────▼──────────┐   ┌──▼──────────────────┐
     │ Contenedor Pagina 1 │   │ Contenedor Pagina 2 │
     └─────────────────────┘   └─────────────────────┘
