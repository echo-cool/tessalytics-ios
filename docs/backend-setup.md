# Backend setup

Tessalytics requires [TeslaMate](https://github.com/teslamate-org/teslamate), [Tessalytics Backend](https://github.com/echo-cool/tessalytics-backend), and secure iPhone-to-API connectivity.

Tessalytics Backend is not optional. TeslaMate does not serve the API this app reads, so a standalone TeslaMate installation will not work. Deploy the backend beside TeslaMate — adding it to the existing TeslaMate Docker Compose file is the simplest way — and give the app the backend's address.

> **Important:** Tessalytics Backend requires a bearer token on every route, but a token alone is not a security boundary. If the service is exposed outside a trusted private network, place a VPN or an authenticating reverse proxy in front of it as well.

Do not expose PostgreSQL, Mosquitto/MQTT, Tesla account tokens, or the API directly without access control.

## Generic Docker Compose example

Merge a service like this into your existing TeslaMate Compose project and replace every placeholder. The [backend repository](https://github.com/echo-cool/tessalytics-backend) carries the authoritative guide, including a complete Compose file for a fresh TeslaMate install.

```yaml
services:
  tessalytics-backend:
    build:
      context: ./tessalytics-backend      # git clone beside docker-compose.yml
      dockerfile: docker/Dockerfile
    restart: unless-stopped
    depends_on:
      - database
      - mosquitto
    environment:
      DATABASE_USER: "${DATABASE_USER}"
      DATABASE_PASS: "${DATABASE_PASSWORD}"
      DATABASE_NAME: "${DATABASE_NAME}"
      DATABASE_HOST: database
      MQTT_HOST: mosquitto
      API_TOKEN: "${TESSALYTICS_API_TOKEN}"
      TIMEZONE: "${TIME_ZONE}"
    expose:
      - "8080"
```

`expose` makes the port available to other Compose services without publishing it on every network interface. Put a protected proxy on the same Docker network or connect through a private overlay network.

## Secure access choices

- Tailscale or another authenticated VPN, with no public API listener
- Caddy, nginx, or Traefik terminating HTTPS and enforcing authentication on every route
- HTTP Basic Authentication at the reverse proxy
- Bearer authentication at the reverse proxy, including all read routes

Use a publicly trusted certificate for public hostnames. Tessalytics does not disable TLS verification. Do not put secrets in URL query parameters; URLs can be recorded by proxies and logs.

## Verification

From a device on the intended network:

1. `/api/ping` should return success without application authentication when configured that way.
2. `/v1/vehicles` should reject missing or wrong proxy credentials.
3. `/v1/vehicles` should succeed with the intended credentials.
4. The backend's forwarded command and wake-up routes should remain disabled; Tessalytics never calls them. Optional direct controls use a separate Owner API connection.

Enter only the protected backend base URL in Tessalytics onboarding — not TeslaMate's port 4000 or Grafana's port 3000. Do not place deployment-specific values in this repository.
