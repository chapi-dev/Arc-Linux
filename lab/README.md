# Lab notes – Azure Arc Linux

Carpeta para archivos temporales del lab (variables locales, claves de
service principal, parámetros de tu suscripción). **Nada de esto se commitea**
gracias al `.gitignore` de la raíz.

Sugerido:

- `lab.env` con tus exports de `ARC_*` (lo lee `04-azcmagent-connect.sh`).
- `subscription.txt` con tu Subscription ID y RG por defecto.

```bash
# Plantilla de lab.env
export ARC_TENANT_ID=00000000-0000-0000-0000-000000000000
export ARC_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000
export ARC_RESOURCE_GROUP=rg-arc-linux-lab
export ARC_LOCATION=westeurope
export ARC_SP_APP_ID=
export ARC_SP_SECRET=
export ARC_TAG_ENV=lab
export ARC_TAG_RING=R0
```
