# Portfolio Showcaser — Setup Guide

## Prerequisites

- **Python 3.11+** — for running the skill scripts
- **Node.js 18+** — for projects that use Node.js
- The project's package manager installed (`npm`, `pnpm`, `yarn`, or `bun`)
- A browser accessible to the VS Code agent (Playwright or built-in)

## Installation

1. **Copy config:**
   ```bash
   cp config.example.json config.json
   ```

2. **Edit config.json:**
   ```json
   {
     "repo_path": "/absolute/path/to/your/project",
     "output_dir": "./output",
     "screenshots_dir": "./output/screenshots",
     "report_filename": "portfolio-report.md",
     "state_file": "./output/state.json"
   }
   ```

3. **Set repo_path** to the absolute path of the project you want to showcase.
   Alternatively, set the `PORTFOLIO_REPO_PATH` environment variable.

## Running

### Full run (recommended first time)
```bash
python -m scripts.run_showcase --config config.json
```

### Dry run (analysis and scoring only, no server)
```bash
python -m scripts.run_showcase --config config.json --dry-run
```

### Focus modes
```bash
python -m scripts.run_showcase --config config.json --focus interactions
python -m scripts.run_showcase --config config.json --focus responsive
python -m scripts.run_showcase --config config.json --focus edge_cases
python -m scripts.run_showcase --config config.json --focus performance
python -m scripts.run_showcase --config config.json --focus freestyle
```

### Single feature
```bash
python -m scripts.run_showcase --config config.json --feature "Home Page"
```

### Skip server (if already running)
```bash
python -m scripts.run_showcase --config config.json --skip-server
```

## Output

After a run, you'll find:

| File | Description |
|------|-------------|
| `output/portfolio-report.md` | Full markdown report with scored features |
| `output/portfolio-data.json` | Structured JSON for programmatic use |
| `output/state.json` | Persistent state (supports resume) |
| `output/screenshots/` | Annotated screenshots organized by feature |
| `output/sessions/` | JSONL session logs for debugging |

## Troubleshooting

### Server won't start
- Check that `repo_path` is correct
- Run `cd <repo_path> && npm install` manually first
- Check if the port is already in use: `lsof -i :3000`
- Try `--skip-server` and start the server manually

### No features discovered
- Ensure the project has a standard directory structure
- Check `code_analyzer` output in the dry-run report
- The project needs at least a `package.json` or equivalent manifest

### Circuit breaker trips
- This means 5+ consecutive exploration failures
- Usually indicates the server crashed or the browser lost connection
- Restart the run; it will resume from the last completed feature

### Port conflicts
- Default is 3000; change via `config.json` → `exploration.port`
- Or stop whatever is using the port: `kill $(lsof -t -i:3000)`

## Environment Variables

| Variable | Description |
|----------|-------------|
| `PORTFOLIO_REPO_PATH` | Override repo_path from config |
| `PORT` | Set by app_runner when starting dev server |
| `NODE_ENV` | Set to `development` by app_runner |
