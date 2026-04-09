# Framework Adapters — Dev Server Startup Commands

Reference for skills that need to spin up a local development server. Detect the framework first (via `repo_analyzer.py` patterns), then use the matching startup command.

---

## Detection Signatures

| Framework        | File Signature              | Package Dependency  |
| ---------------- | --------------------------- | ------------------- |
| Next.js          | `next.config.*`             | `next`              |
| Remix            | `remix.config.*`            | `@remix-run/react`  |
| Vite + React     | `vite.config.*`             | `react`, `vite`     |
| Create React App | —                           | `react-scripts`     |
| Nuxt             | `nuxt.config.*`             | `nuxt`              |
| SvelteKit        | `svelte.config.*`           | `@sveltejs/kit`     |
| Angular          | `angular.json`              | `@angular/core`     |
| Astro            | `astro.config.*`            | `astro`             |
| Gatsby           | `gatsby-config.*`           | `gatsby`            |
| Django           | `manage.py`                 | `django`            |
| Flask            | —                           | `flask`             |
| FastAPI          | —                           | `fastapi`           |
| Rails            | `Gemfile`                   | `rails`             |
| Laravel          | `artisan`                   | `laravel/framework` |
| Spring Boot      | `pom.xml` or `build.gradle` | `spring-boot`       |

## Package Manager Detection

Check in order:

1. `bun.lockb` → `bun`
2. `pnpm-lock.yaml` → `pnpm`
3. `yarn.lock` → `yarn`
4. `package-lock.json` → `npm`

## Startup Commands

### JavaScript/TypeScript Frameworks

```yaml
next:
  install: "{pm} install"
  dev: "{pm} run dev"
  build: "{pm} run build"
  start: "{pm} start"
  port: 3000
  ready_signal: "Ready on"

remix:
  install: "{pm} install"
  dev: "{pm} run dev"
  port: 5173
  ready_signal: "Local:"

vite_react:
  install: "{pm} install"
  dev: "{pm} run dev"
  port: 5173
  ready_signal: "Local:"

cra:
  install: "{pm} install"
  dev: "{pm} start"
  port: 3000
  env: "BROWSER=none"
  ready_signal: "Compiled"

nuxt:
  install: "{pm} install"
  dev: "{pm} run dev"
  port: 3000
  ready_signal: "Listening on"

sveltekit:
  install: "{pm} install"
  dev: "{pm} run dev"
  port: 5173
  ready_signal: "Local:"

angular:
  install: "{pm} install"
  dev: "{pm} run start -- --open=false"
  port: 4200
  ready_signal: "Compiled successfully"

astro:
  install: "{pm} install"
  dev: "{pm} run dev"
  port: 4321
  ready_signal: "Local"

gatsby:
  install: "{pm} install"
  dev: "{pm} run develop"
  port: 8000
  ready_signal: "You can now view"
```

### Python Frameworks

```yaml
django:
  install: "pip install -r requirements.txt"
  dev: "python manage.py runserver"
  port: 8000
  ready_signal: "Starting development server"

flask:
  install: "pip install -r requirements.txt"
  dev: "flask run"
  port: 5000
  env: "FLASK_ENV=development"
  ready_signal: "Running on"

fastapi:
  install: "pip install -r requirements.txt"
  dev: "uvicorn main:app --reload"
  port: 8000
  ready_signal: "Uvicorn running"
```

### Ruby/PHP/Java

```yaml
rails:
  install: "bundle install"
  dev: "rails server"
  port: 3000
  ready_signal: "Listening on"

laravel:
  install: "composer install && php artisan key:generate"
  dev: "php artisan serve"
  port: 8000
  ready_signal: "Server running"

spring:
  install: "./mvnw clean compile"
  dev: "./mvnw spring-boot:run"
  port: 8080
  ready_signal: "Started"
```

## Health Check Pattern

After starting the dev server, poll the base URL until it responds:

```python
import time
import urllib.request
import urllib.error

def wait_for_server(url: str, timeout: int = 120) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            response = urllib.request.urlopen(url, timeout=5)
            if response.status < 500:
                return True
        except (urllib.error.URLError, ConnectionRefusedError, OSError):
            pass
        time.sleep(2)
    return False
```

## Environment Variable Handling

Many repos need `.env` files. Detection pattern:

1. Check for `.env.example`, `.env.local.example`, `.env.sample`
2. Copy to `.env` / `.env.local`
3. Fill in required values (or use dummy values for portfolio screenshots)
4. Common dummy-safe vars: `DATABASE_URL=sqlite:///dev.db`, `SECRET_KEY=dev-secret-not-for-production`
5. Never use production credentials — this is for local demo only

## Port Conflict Resolution

If the default port is occupied:

```python
import socket

def find_open_port(start: int = 3000, max_attempts: int = 10) -> int:
    for port in range(start, start + max_attempts):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex(("localhost", port)) != 0:
                return port
    raise RuntimeError(f"No open port found in range {start}-{start + max_attempts}")
```
