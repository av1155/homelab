# Deploying Web Applications with Dokploy + Nginx Proxy Manager + Cloudflare Wildcard Domain

This guide explains how to deploy applications using **Dokploy**, route traffic via **Nginx Proxy Manager (NPM)**, and serve apps over HTTPS using a **wildcard domain certificate**.

---

## Prerequisites

- Dokploy installed and running (e.g., on `10.0.10.110`)
- Nginx Proxy Manager installed and accessible
- Wildcard domain configured with Cloudflare (e.g., `*.example.com`)
- Router forwarding **only port 443** to the server

---

## Deploying a New App

### Step 1: Expose App Port in Dokploy

1. Navigate to your project in Dokploy.
2. Go to **Advanced > Ports**
3. Click **"Add Port"**:
    - **Published Port**: A unique external port (e.g., `10001`)
    - **Target Port**: The internal app port (usually `3000` for Node/Next.js, depends on the app type)
    - **Protocol**: TCP

4. Click **Create**, then **Redeploy** the app.

### Step 2: Assign Domain in Dokploy

1. In Dokploy, go to **Domains**.
2. Click **"Add Domain"**:
    - **Host**: e.g., `yourapp.example.com`
    - **Path**: `/`
    - **Container Port**: `3000` (again, usually `3000` for Node/Next.js, depends on the app type)
    - **HTTPS**: Enable, Certificate Provider=none (handled by NPM)

3. Click **Create**.

### Step 3: Configure Nginx Proxy Manager

1. Go to NPM.
2. Click **"Add Proxy Host"** (or edit an existing one):
    - **Domain Names**: `yourapp.example.com`
    - **Scheme**: `http`
    - **Forward Hostname/IP**: `10.0.10.110`
    - **Forward Port**: `10001`
    - Enable **Block Common Exploits** and **Websockets Support**

3. Go to the **SSL** tab:
    - Enable **"Force SSL"**, **"HTTP/2 Support"**, and **"HSTS Enabled"**
    - Choose your wildcard SSL certificate
    - Accept Terms and click **Save**

4. Go to the **Advanced** tab:
    - Fill in the following:

    ```bash
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    ```

### Step 5: Test

Visit your app at `https://yourapp.example.com`. You should see the deployed app over HTTPS.

---

## Deploying More Apps

Repeat the steps above using a new:

- Published Port (e.g., `10002`, `10003`, ...)
- Subdomain (e.g., `project2.example.com`, etc.)

Only port `443` is needed open on your router for **all** apps.

---

## Notes

- SSL is terminated at Nginx Proxy Manager
- Dokploy should not provision its own SSL certs (use NPM instead)
- Wildcard domain DNS (`*.example.com`) must point to your server's WAN IP via Cloudflare

---

## "Invalid Origin" Error When Logging In Fix

Run the following command to fix it:

```bash
docker service update \
  --env-rm ALLOWED_ORIGINS \
  --env-add ALLOWED_ORIGINS=http://localhost:3000,https://dokploy.example.com \
  dokploy
```

> Only use https://dokploy.example.com if you actually have it exposed to the internet via something like Nginx Proxy Manager.
