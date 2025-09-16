# OpenWebUI Setup

## Ollama Setup

Install the native Ollama version on macOS:

```bash
brew install ollama
brew services start ollama
```

OpenWebUI will automatically detect it later.

## Configure SearXNG for Web Search support

### Step 1: Generate Initial Configuration

Run the following command so that **searxng** generates the `settings.yml` file:

```bash
docker compose up -d ; sleep 10 ; docker compose down
```

---

### Step 2: Edit `settings.yml`

Open and modify the configuration file:

```bash
sed -i .bak '/- html/a\
\ \ \ \ - json
' searxng/settings.yml
```

#### Verify the output:

```bash
grep -A3 'formats:' searxng/settings.yml
```

---

### Step 3: Update Security and Server Settings

Generate a secure key:

```bash
sed -i .bak "s|ultrasecretkey|$(openssl rand -hex 32)|g" searxng/settings.yml
```

Change the server port:

```bash
sed -i .bak '/^server:/,/^[^[:space:]]/ s/^\([[:space:]]*port:\).*/\1 8080/' searxng/settings.yml
```

Bind the server to all interfaces:

```bash
sed -i .bak '/^server:/,/^[^[:space:]]/ s/^\([[:space:]]*bind_address:\).*/\1 "0.0.0.0"/' searxng/settings.yml
```

#### Verify the changes:

```bash
grep -nE '^(server:|[[:space:]]+port:|[[:space:]]+bind_address:)' searxng/settings.yml
```

---

### Step 4: Download `limiter.toml`

```bash
cd searxng
curl --remote-name https://raw.githubusercontent.com/searxng/searxng-docker/refs/heads/master/searxng/limiter.toml
```

---

### Step 5: (Optional) Fix Hugging Face CAS 403 Errors

If you encounter errors like:

```
Fatal Error: "s3::get_range" api call failed ... HTTP status client error (403 Forbidden)
```

add the following to the **OpenWebUI environment section**:

```yaml
# 👇 Workaround for 403s from xethub/hf CAS
HF_HUB_DISABLE_XET: "1"
HF_HUB_ENABLE_HF_TRANSFER: "0"

# (Optional) Persist / pre-seed embeddings locally
SENTENCE_TRANSFORMERS_HOME: "/app/backend/data/cache/embedding/models"
```

---
