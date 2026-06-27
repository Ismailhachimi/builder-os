#!/bin/zsh

bos_register_project() {
  local name="$1" project_dir="$2" type="$3"
  bos_ensure_dirs
  local json
  json="$(jq --arg name "$name" --arg path "$project_dir" --arg type "$type" --arg created "$(date -u +%FT%TZ)" '
    .projects = ([.projects[] | select(.name != $name and .path != $path)] + [{
      name:$name,path:$path,type:$type,created_at:$created
    }])' "$BOS_PROJECTS")"
  bos_atomic_json "$BOS_PROJECTS" "$json"
}

bos_resolve_project() {
  local target="$1"
  if [[ "$target" == "." ]]; then
    pwd -P
  elif [[ -d "$target" ]]; then
    (cd "$target" && pwd -P)
  else
    local project_dir
    project_dir="$(jq -r --arg name "$target" '.projects[] | select(.name==$name) | .path' "$BOS_PROJECTS" | head -1)"
    [[ -n "$project_dir" && -d "$project_dir" ]] || return 1
    print -r -- "$project_dir"
  fi
}

bos_projects() {
  bos_ensure_dirs
  printf "%-22s %-10s %-10s %s\n" NAME TYPE GIT PATH
  jq -r '.projects[] | [.name,.type,.path] | @tsv' "$BOS_PROJECTS" |
    while IFS=$'\t' read -r name type project_dir; do
      local git_state="missing"
      if [[ -d "$project_dir/.git" ]]; then
        git_state="$([[ -z "$(git -C "$project_dir" status --porcelain 2>/dev/null)" ]] && echo clean || echo dirty)"
      elif [[ -d "$project_dir" ]]; then
        git_state="no-git"
      fi
      printf "%-22s %-10s %-10s %s\n" "$name" "$type" "$git_state" "$project_dir"
    done
}

bos_project_register() {
  bos_ensure_dirs
  local target="." name="" type=""
  if [[ $# -gt 0 && "$1" != --* ]]; then
    target="$1"
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="${2:-}"; shift 2 ;;
      --type) type="${2:-}"; shift 2 ;;
      *) bos_die "Unknown project register option: $1"; return 1 ;;
    esac
  done

  local project_dir
  project_dir="$(bos_resolve_project "$target")" || { bos_die "Project directory not found: $target"; return 1; }
  name="${name:-${project_dir:t}}"
  [[ -n "$name" ]] || { bos_die "Project name cannot be empty."; return 1; }
  if [[ -z "$type" ]]; then
    type="$([[ -f "$project_dir/.bos/project.json" ]] && jq -r '.template // "existing"' "$project_dir/.bos/project.json" || echo existing)"
  fi
  [[ -n "$type" ]] || type="existing"

  bos_register_project "$name" "$project_dir" "$type"
  bos_info "Registered project: $name"
  bos_info "Path: $project_dir"
  bos_info "Type: $type"
  bos_info "Open it with: bos open $name"
}

bos_project_reset() {
  bos_ensure_dirs
  local target="${1:-}"
  [[ -n "$target" && "$target" != --* ]] || {
    bos_die "Usage: bos project reset NAME|PATH|. [--template web] [--orm drizzle|prisma] [--yes]"
    return 1
  }
  shift

  local template="web" orm_override="" yes=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --template) template="${2:-}"; shift 2 ;;
      --orm) orm_override="${2:-}"; shift 2 ;;
      --yes) yes=1; shift ;;
      *) bos_die "Unknown project reset option: $1"; return 1 ;;
    esac
  done

  local project_dir
  project_dir="$(bos_resolve_project "$target")" || { bos_die "Project not found: $target"; return 1; }
  project_dir="${project_dir:A}"
  [[ -d "$project_dir" ]] || { bos_die "Project directory not found: $project_dir"; return 1; }

  local name registered_name
  registered_name="$(jq -r --arg path "$project_dir" '.projects[] | select(.path==$path) | .name' "$BOS_PROJECTS" | head -1)"
  if [[ "$target" != "." && ! -d "$target" && -n "$registered_name" ]]; then
    name="$registered_name"
  else
    name="${registered_name:-${project_dir:t}}"
  fi
  [[ -n "$name" ]] || { bos_die "Project name cannot be empty."; return 1; }

  local stamp backup_dir parent
  stamp="$(date +%Y%m%d-%H%M%S)"
  parent="${project_dir:h}"
  backup_dir="$parent/$name.backup-$stamp"
  while [[ -e "$backup_dir" ]]; do
    sleep 1
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup_dir="$parent/$name.backup-$stamp"
  done

  cat <<EOF
This will reset a project by moving the current directory to a backup, then
creating a fresh BOS project at the original path.

Project:   $name
Current:   $project_dir
Backup:    $backup_dir
Template:  $template
EOF
  if [[ -n "$orm_override" ]]; then
    print -r -- "ORM:       $orm_override"
  fi
  print
  print -r -- "Nothing will be deleted immediately, but the active project path will be replaced."

  if (( ! yes )); then
    print -n -r -- "Type RESET $name to continue: "
    local confirm
    read -r confirm
    if [[ "$confirm" != "RESET $name" ]]; then
      bos_info "Cancelled."
      return 0
    fi
  fi

  mv "$project_dir" "$backup_dir" || { bos_die "Could not move project to backup: $backup_dir"; return 1; }

  local init_args=( "$name" --template "$template" --path "$project_dir" --yes )
  [[ -n "$orm_override" ]] && init_args+=( --orm "$orm_override" )

  if bos_init "${init_args[@]}"; then
    bos_info "Reset complete."
    bos_info "Backup preserved at: $backup_dir"
    return 0
  fi

  bos_error "Reset failed while creating the new project."
  local failed_dir="$parent/$name.failed-reset-$stamp"
  if [[ -e "$project_dir" ]]; then
    mv "$project_dir" "$failed_dir" 2>/dev/null && bos_error "Partial reset output moved to: $failed_dir"
  fi
  if [[ ! -e "$project_dir" ]]; then
    mv "$backup_dir" "$project_dir" 2>/dev/null && bos_error "Original project restored: $project_dir"
  else
    bos_error "Backup remains at: $backup_dir"
  fi
  return 1
}

bos_project() {
  local sub="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$sub" in
    register) bos_project_register "$@" ;;
    reset) bos_project_reset "$@" ;;
    *) bos_die "Usage: bos project register [PATH|.] [--name NAME] [--type TYPE]
       bos project reset NAME|PATH|. [--template web] [--orm drizzle|prisma] [--yes]"; return 1 ;;
  esac
}

bos_prompt_value() {
  local prompt="$1" default="$2" answer
  print -u2 -n -r -- "$prompt [$default]: "
  read -r answer
  print -r -- "${answer:-$default}"
}

bos_node_version_ok() {
  local version="${1#v}" major minor rest
  major="${version%%.*}"
  rest="${version#*.}"
  minor="${rest%%.*}"
  [[ "$major" == <-> && "$minor" == <-> ]] || return 1
  (( major > 22 || (major == 22 && minor >= 13) ))
}

bos_use_managed_node() {
  local node_root="${XDG_DATA_HOME:-$HOME/.local/share}/builder-os/node/current"
  [[ -x "$node_root/bin/node" ]] || return 1
  export PATH="$node_root/bin:$PATH"
  rehash 2>/dev/null || true
}

bos_install_linux_node() {
  local data_root="${XDG_DATA_HOME:-$HOME/.local/share}/builder-os/node"
  local node_arch version archive url tmp install_dir

  case "$(uname -m)" in
    x86_64) node_arch="x64" ;;
    aarch64|arm64) node_arch="arm64" ;;
    *) bos_die "Unsupported Node.js architecture: $(uname -m)"; return 1 ;;
  esac

  bos_has curl || { bos_die "curl is required to install Node.js."; return 1; }
  bos_has tar || { bos_die "tar is required to install Node.js."; return 1; }

  bos_info "Installing latest Node.js LTS for Linux..."
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/bos-node.XXXXXX")"
  curl -fsSL https://nodejs.org/dist/index.tab -o "$tmp/index.tab" ||
    { rm -rf "$tmp"; bos_die "Could not download the Node.js release index."; return 1; }
  version="$(awk 'NR > 1 && $10 != "-" { print $1; exit }' "$tmp/index.tab")" ||
    { rm -rf "$tmp"; bos_die "Could not resolve the latest Node.js LTS release."; return 1; }
  [[ -n "$version" ]] || { bos_die "Could not resolve the latest Node.js LTS release."; return 1; }

  archive="node-${version}-linux-${node_arch}.tar.xz"
  url="https://nodejs.org/dist/${version}/${archive}"
  install_dir="$data_root/node-${version}-linux-${node_arch}"

  mkdir -p "$data_root"
  (
    cd "$tmp" &&
      curl -fsSLO "$url" &&
      tar -xJf "$archive" &&
      rm -rf "$install_dir" &&
      mv "${archive%.tar.xz}" "$install_dir"
  ) || {
    rm -rf "$tmp"
    bos_die "Node.js installation failed from $url."
    return 1
  }
  rm -rf "$tmp"
  ln -sfn "$install_dir" "$data_root/current"
  bos_use_managed_node || { bos_die "Node.js was installed, but could not be activated."; return 1; }
}

bos_install_web_tools() {
  bos_use_managed_node || true
  local node_version=""
  bos_has node && node_version="$(node -v 2>/dev/null || true)"

  if [[ -z "$node_version" ]] || ! bos_node_version_ok "$node_version"; then
    case "$BOS_PLATFORM" in
      darwin) bos_info "Installing Node.js with Homebrew..."; brew install node ;;
      linux) bos_install_linux_node ;;
    esac
    bos_has node || { bos_die "Node.js installation completed, but node is still unavailable."; return 1; }
    node_version="$(node -v 2>/dev/null || true)"
    bos_node_version_ok "$node_version" || { bos_die "Node.js $node_version is too old; BOS needs Node.js 22.13 or newer."; return 1; }
  fi
  if ! bos_has pnpm; then
    if bos_has corepack; then
      bos_info "Preparing pnpm with Corepack..."
      corepack prepare pnpm@10.12.1 --activate
    elif [[ "$BOS_PLATFORM" == "darwin" ]] && bos_has brew; then
      bos_info "Installing pnpm with Homebrew..."
      brew install pnpm
    elif [[ "$BOS_PLATFORM" == "linux" ]] && bos_has npm; then
      bos_info "Installing pnpm with npm..."
      npm install -g pnpm@10.12.1
    else
      bos_die "pnpm is missing. Install pnpm or enable Corepack, then rerun bos init."
      return 1
    fi
    bos_has pnpm || { bos_die "pnpm installation completed, but pnpm is still unavailable."; return 1; }
  fi
}

bos_init_recoverable_project() {
  local project_dir="$1" name="$2"
  [[ -f "$project_dir/.bos/project.json" ]] || return 1
  [[ ! -d "$project_dir/.git" ]] || return 1
  [[ "$(jq -r '.name // empty' "$project_dir/.bos/project.json" 2>/dev/null)" == "$name" ]] || return 1
}

bos_scaffold_web() {
  local project_dir="$1" name="$2" description="$3" visual="$4" database="$5" database_url="$6" orm="$7" auth="$8" infrastructure="$9"
  local example_database_url="$database_url" data_stack="$database" database_name="${name//-/_}" compose_database_url="$database_url"
  [[ "$orm" != "none" ]] && data_stack="$database with $orm"
  [[ "$database" == "postgresql" ]] && example_database_url="postgresql://postgres:postgres@localhost:5432/$database_name"
  [[ "$database" == "mongodb" ]] && example_database_url="mongodb://localhost:27017/$database_name"
  [[ "$database" == "postgresql" ]] && compose_database_url="postgresql://postgres:postgres@postgres:5432/$database_name"
  [[ "$database" == "mongodb" ]] && compose_database_url="mongodb://mongo:27017/$database_name"
  mkdir -p "$project_dir/apps/web/app" "$project_dir/apps/api/src/auth" "$project_dir/packages/contracts/src" "$project_dir/docs" "$project_dir/.bos"

  cat > "$project_dir/package.json" <<EOF
{
  "name": "$name",
  "private": true,
  "packageManager": "pnpm@10.12.1",
  "engines": {
    "node": ">=22.13"
  },
  "scripts": {
    "dev": "turbo dev",
    "dev:docker": "docker compose up --build",
    "dev:docker:down": "docker compose down",
    "dev:docker:reset": "docker compose down -v && docker compose up --build",
    "dev:infra": "docker compose up --build",
    "dev:infra:down": "docker compose down",
    "dev:infra:reset": "docker compose down -v && docker compose up --build",
    "build": "turbo build",
    "lint": "turbo lint",
    "test": "turbo test"
  },
  "devDependencies": {
    "turbo": "^2.5.4",
    "typescript": "^5.8.3"
  }
}
EOF
  print -r -- "24" > "$project_dir/.nvmrc"
  print -r -- "24" > "$project_dir/.node-version"
  cat > "$project_dir/pnpm-workspace.yaml" <<'EOF'
packages:
  - "apps/*"
  - "packages/*"
EOF
  cat > "$project_dir/turbo.json" <<'EOF'
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build": { "dependsOn": ["^build"], "outputs": [".next/**", "dist/**", ".buildstamp"] },
    "dev": { "cache": false, "persistent": true },
    "lint": { "dependsOn": ["^lint"] },
    "test": { "dependsOn": ["^test"] }
  }
}
EOF
  cat > "$project_dir/.gitignore" <<'EOF'
node_modules/
.next/
dist/
.turbo/
.env
.env.*
!.env.example
.buildstamp
.pnpm-store/
.pnpm-install.lock
.DS_Store
EOF
  cat > "$project_dir/.env.example" <<EOF
DATABASE_URL=$example_database_url
JWT_SECRET=replace-me
NEXT_PUBLIC_API_URL=http://localhost:3001
EOF
  cat > "$project_dir/.env.local" <<EOF
DATABASE_URL=$database_url
JWT_SECRET=local-development-only
NEXT_PUBLIC_API_URL=http://localhost:3001
EOF
  cat > "$project_dir/compose.yaml" <<EOF
services:
  web:
    image: node:24-bookworm-slim
    working_dir: /workspace
    user: "\${UID:-1000}:\${GID:-1000}"
    command: >
      sh -lc "corepack pnpm@10.12.1 config set store-dir /workspace/.pnpm-store &&
      CI=true flock /workspace/.pnpm-install.lock corepack pnpm@10.12.1 install --no-frozen-lockfile &&
      corepack pnpm@10.12.1 --filter @app/web exec next dev --hostname 0.0.0.0"
    environment:
      NEXT_PUBLIC_API_URL: http://localhost:3001
    ports:
      - "3000:3000"
    volumes:
      - .:/workspace
    depends_on:
      - api

  api:
    image: node:24-bookworm-slim
    working_dir: /workspace
    user: "\${UID:-1000}:\${GID:-1000}"
    command: >
      sh -lc "corepack pnpm@10.12.1 config set store-dir /workspace/.pnpm-store &&
      CI=true flock /workspace/.pnpm-install.lock corepack pnpm@10.12.1 install --no-frozen-lockfile &&
      corepack pnpm@10.12.1 --filter @app/api dev"
    environment:
      JWT_SECRET: local-development-only
      DATABASE_URL: $compose_database_url
    ports:
      - "3001:3001"
    volumes:
      - .:/workspace
EOF
  if [[ "$database" == "postgresql" ]]; then
    cat >> "$project_dir/compose.yaml" <<EOF
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:17-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: $database_name
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d $database_name"]
      interval: 5s
      timeout: 5s
      retries: 10

volumes:
  postgres-data:
EOF
  elif [[ "$database" == "mongodb" ]]; then
    cat >> "$project_dir/compose.yaml" <<'EOF'
    depends_on:
      mongo:
        condition: service_healthy

  mongo:
    image: mongo:7
    restart: unless-stopped
    ports:
      - "27017:27017"
    volumes:
      - mongo-data:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--quiet", "--eval", "db.adminCommand('ping').ok"]
      interval: 5s
      timeout: 5s
      retries: 10

volumes:
  mongo-data:
EOF
  else
    cat >> "$project_dir/compose.yaml" <<'EOF'
EOF
  fi
  cat > "$project_dir/README.md" <<EOF
# $name

$description

## Stack

Turbo, pnpm, Next.js, NestJS, shared Zod contracts, $data_stack, and $auth auth.

## Development

\`\`\`sh
bos dev
\`\`\`

This starts the web app, API, and local services with the Node version pinned by
the template. Open:

- Web: http://localhost:3000
- API health: http://localhost:3001/health

Stop or reset everything:

\`\`\`sh
bos dev stop
bos dev reset
\`\`\`

Under the hood, BOS runs Docker Compose from this project directory. Raw
\`docker compose ...\` commands work too.

Host development is also available when Node.js and pnpm match the template:

\`\`\`sh
pnpm dev
\`\`\`

See \`PRODUCT.md\` for the product and design brief.
EOF
  cat > "$project_dir/PRODUCT.md" <<EOF
# Product Brief

## Purpose

$description

## Visual Direction

$visual

## Architecture

- Web: Next.js App Router with Tailwind and a shadcn/ui-compatible component structure.
- API: NestJS with global validation, security headers, health endpoint, and JWT skeleton.
- Contracts: shared Zod schemas and inferred TypeScript types.
- Data: $data_stack.
- Local development: Docker Compose runs the web app, API, and local services.
- Future infrastructure target: $infrastructure.
EOF
  cat > "$project_dir/AGENTS.md" <<'EOF'
# Agent Instructions

- Inspect and plan before editing.
- Preserve the Turbo workspace boundaries.
- Put shared API schemas in `packages/contracts`.
- Validate external input with Zod or Nest validation.
- Keep secrets in `.env.local`; update `.env.example` with placeholders.
- Run relevant lint, test, and build commands before finishing.
EOF
  jq -n --arg name "$name" --arg description "$description" --arg visual "$visual" --arg database "$database" --arg orm "$orm" --arg auth "$auth" --arg infrastructure "$infrastructure" '
    {schema_version:2,name:$name,template:"web",description:$description,visual_direction:$visual,database:$database,orm:$orm,auth:$auth,infrastructure:$infrastructure}
  ' > "$project_dir/.bos/project.json"

  cat > "$project_dir/apps/web/package.json" <<'EOF'
{
  "name": "@app/web",
  "private": true,
  "scripts": { "dev": "next dev", "build": "next build", "lint": "next lint" },
  "dependencies": {
    "@app/contracts": "workspace:*",
    "next": "^15.3.3",
    "react": "^19.1.0",
    "react-dom": "^19.1.0",
    "zod": "^3.25.56"
  },
  "devDependencies": {
    "@types/node": "^22.15.29",
    "@types/react": "^19.1.6",
    "@types/react-dom": "^19.1.5",
    "autoprefixer": "^10.4.21",
    "postcss": "^8.5.4",
    "tailwindcss": "^4.1.8",
    "typescript": "^5.8.3"
  }
}
EOF
  cat > "$project_dir/apps/web/app/layout.tsx" <<'EOF'
import type { ReactNode } from "react";
import "./styles.css";

export default function Layout({ children }: { children: ReactNode }) {
  return <html lang="en"><body>{children}</body></html>;
}
EOF
  cat > "$project_dir/apps/web/app/page.tsx" <<EOF
export default function Home() {
  return <main><p className="eyebrow">Builder OS</p><h1>$name</h1><p>$description</p></main>;
}
EOF
  cat > "$project_dir/apps/web/app/styles.css" <<'EOF'
@import "tailwindcss";
:root { color-scheme: light; font-family: Inter, ui-sans-serif, system-ui; background: #f4f1ea; color: #17201b; }
body { margin: 0; }
main { max-width: 760px; margin: 20vh auto; padding: 2rem; }
h1 { font-size: clamp(3rem, 10vw, 7rem); letter-spacing: -.07em; margin: 0; }
p { max-width: 60ch; line-height: 1.7; }
.eyebrow { text-transform: uppercase; letter-spacing: .18em; font-size: .75rem; }
EOF
  cat > "$project_dir/apps/web/next.config.ts" <<'EOF'
import type { NextConfig } from "next";
export default { transpilePackages: ["@app/contracts"] } satisfies NextConfig;
EOF
  cat > "$project_dir/apps/web/tsconfig.json" <<'EOF'
{ "compilerOptions": { "target": "ES2022", "lib": ["dom", "dom.iterable", "esnext"], "strict": true, "noEmit": true, "allowJs": true, "skipLibCheck": true, "incremental": true, "esModuleInterop": true, "module": "esnext", "moduleResolution": "bundler", "resolveJsonModule": true, "isolatedModules": true, "jsx": "preserve", "plugins": [{ "name": "next" }] }, "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"], "exclude": ["node_modules"] }
EOF
  cat > "$project_dir/apps/web/next-env.d.ts" <<'EOF'
/// <reference types="next" />
/// <reference types="next/image-types/global" />
/// <reference path="./.next/types/routes.d.ts" />

// NOTE: This file should not be edited
// see https://nextjs.org/docs/app/api-reference/config/typescript for more information.
EOF
  cat > "$project_dir/apps/web/components.json" <<'EOF'
{ "$schema": "https://ui.shadcn.com/schema.json", "style": "new-york", "rsc": true, "tsx": true, "tailwind": { "css": "app/styles.css", "baseColor": "neutral", "cssVariables": true }, "aliases": { "components": "@/components", "utils": "@/lib/utils" } }
EOF

  cat > "$project_dir/packages/contracts/package.json" <<'EOF'
{ "name": "@app/contracts", "version": "0.0.0", "type": "module", "exports": { ".": "./src/index.ts" }, "scripts": { "lint": "tsc --noEmit", "build": "tsc --noEmit && touch .buildstamp" }, "dependencies": { "zod": "^3.25.56" }, "devDependencies": { "typescript": "^5.8.3" } }
EOF
  cat > "$project_dir/packages/contracts/tsconfig.json" <<'EOF'
{ "compilerOptions": { "target": "ES2022", "module": "ESNext", "moduleResolution": "Bundler", "strict": true, "noEmit": true }, "include": ["src"] }
EOF
  cat > "$project_dir/packages/contracts/src/index.ts" <<'EOF'
import { z } from "zod";
export const HealthSchema = z.object({ status: z.literal("ok") });
export type Health = z.infer<typeof HealthSchema>;
EOF

  cat > "$project_dir/apps/api/package.json" <<'EOF'
{
  "name": "@app/api",
  "private": true,
  "scripts": { "dev": "nest start --watch", "build": "nest build", "lint": "tsc --noEmit" },
  "dependencies": {
    "@app/contracts": "workspace:*",
    "@nestjs/common": "^11.1.2",
    "@nestjs/core": "^11.1.2",
    "@nestjs/jwt": "^11.0.0",
    "@nestjs/platform-express": "^11.1.2",
    "class-transformer": "^0.5.1",
    "class-validator": "^0.14.2",
    "helmet": "^8.1.0",
    "reflect-metadata": "^0.2.2",
    "rxjs": "^7.8.2"
  },
  "devDependencies": { "@nestjs/cli": "^11.0.7", "@types/node": "^22.15.29", "typescript": "^5.8.3" }
}
EOF
  cat > "$project_dir/apps/api/tsconfig.json" <<'EOF'
{ "compilerOptions": { "target": "ES2022", "module": "CommonJS", "moduleResolution": "Node", "strict": true, "experimentalDecorators": true, "emitDecoratorMetadata": true, "outDir": "dist", "skipLibCheck": true }, "include": ["src"] }
EOF
  cat > "$project_dir/apps/api/nest-cli.json" <<'EOF'
{ "collection": "@nestjs/schematics", "sourceRoot": "src" }
EOF
  cat > "$project_dir/apps/api/src/main.ts" <<'EOF'
import { ValidationPipe } from "@nestjs/common";
import { NestFactory } from "@nestjs/core";
import helmet from "helmet";
import { AppModule } from "./app.module";
async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.use(helmet());
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
  await app.listen(3001);
}
void bootstrap();
EOF
  cat > "$project_dir/apps/api/src/app.module.ts" <<'EOF'
import { Controller, Get, Module } from "@nestjs/common";
import { JwtModule } from "@nestjs/jwt";
@Controller("health")
class HealthController { @Get() health() { return { status: "ok" as const }; } }
@Module({ imports: [JwtModule.register({ global: true, secret: process.env.JWT_SECRET ?? "local-development-only" })], controllers: [HealthController] })
export class AppModule {}
EOF
  if [[ "$database" == "postgresql" && "$orm" == "drizzle" ]]; then
    mkdir -p "$project_dir/apps/api/src/db"
    cat > "$project_dir/apps/api/drizzle.config.ts" <<'EOF'
import { config } from "dotenv";
import { defineConfig } from "drizzle-kit";

config({ path: "../../.env.local" });

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/db/schema.ts",
  out: "./drizzle",
  dbCredentials: { url: process.env.DATABASE_URL ?? "" },
});
EOF
    cat > "$project_dir/apps/api/src/db/schema.ts" <<'EOF'
import { pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";

export const users = pgTable("users", {
  id: uuid("id").defaultRandom().primaryKey(),
  email: text("email").notNull().unique(),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});
EOF
    jq '.scripts["db:generate"]="drizzle-kit generate" | .scripts["db:migrate"]="drizzle-kit migrate" | .scripts["db:studio"]="drizzle-kit studio" | .dependencies["drizzle-orm"]="^0.44.2" | .dependencies.dotenv="^16.5.0" | .dependencies.pg="^8.16.0" | .devDependencies["drizzle-kit"]="^0.31.1" | .devDependencies["@types/pg"]="^8.15.4"' "$project_dir/apps/api/package.json" > "$project_dir/apps/api/package.json.next"
    mv "$project_dir/apps/api/package.json.next" "$project_dir/apps/api/package.json"
  elif [[ "$database" == "postgresql" && "$orm" == "prisma" ]]; then
    mkdir -p "$project_dir/apps/api/prisma"
    cat > "$project_dir/apps/api/prisma/schema.prisma" <<'EOF'
generator client { provider = "prisma-client-js" }
datasource db { provider = "postgresql"; url = env("DATABASE_URL") }
model User { id String @id @default(cuid()); email String @unique; createdAt DateTime @default(now()) }
EOF
    jq '.dependencies["@prisma/client"]="^6.9.0" | .devDependencies.prisma="^6.9.0"' "$project_dir/apps/api/package.json" > "$project_dir/apps/api/package.json.next"
    mv "$project_dir/apps/api/package.json.next" "$project_dir/apps/api/package.json"
  elif [[ "$database" == "mongodb" ]]; then
    jq '.dependencies["@nestjs/mongoose"]="^11.0.3" | .dependencies.mongoose="^8.15.1"' "$project_dir/apps/api/package.json" > "$project_dir/apps/api/package.json.next"
    mv "$project_dir/apps/api/package.json.next" "$project_dir/apps/api/package.json"
  fi
}

bos_init() {
  bos_ensure_dirs
  local name="${1:-}"
  [[ -n "$name" && "$name" != --* ]] || { bos_die "Usage: bos init <name> [--template web] [--path DIR] [--orm drizzle|prisma] [--yes]"; return 1; }
  shift
  local template="web" project_dir="$PWD/$name" explicit_path=0 orm_override="" yes=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --template) template="${2:-}"; shift 2 ;;
      --path) project_dir="${2:-}"; explicit_path=1; shift 2 ;;
      --orm) orm_override="${2:-}"; shift 2 ;;
      --yes) yes=1; shift ;;
      *) bos_die "Unknown init option: $1"; return 1 ;;
    esac
  done
  [[ -n "$project_dir" ]] || { bos_die "Project path cannot be empty."; return 1; }
  local template_file="$BOS_ROOT/config/templates/$template.json"
  [[ -f "$template_file" ]] || template_file="$BOS_CONFIG_HOME/templates/$template.json"
  [[ -f "$template_file" ]] || { bos_die "Unknown template: $template"; return 1; }
  local base_template="$(jq -r '.extends // .name // empty' "$template_file")"
  [[ "$base_template" == "web" ]] || { bos_die "Template $template requires an unsupported generator: $base_template"; return 1; }
  bos_install_web_tools
  if [[ "$yes" -eq 0 && "$explicit_path" -eq 0 ]]; then
    project_dir="$(bos_prompt_value "Project path" "$project_dir")"
    [[ -n "$project_dir" ]] || { bos_die "Project path cannot be empty."; return 1; }
  fi
  project_dir="${project_dir:A}"
  local resume_existing=0
  if [[ -e "$project_dir" && -n "$(find "$project_dir" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    if bos_init_recoverable_project "$project_dir" "$name"; then
      resume_existing=1
      bos_info "Resuming incomplete BOS project: $project_dir"
    else
      bos_die "Refusing to overwrite non-empty directory: $project_dir"
      return 1
    fi
  fi
  local description="$(jq -r '.defaults.description // "A thoughtfully designed web product"' "$template_file")"
  local visual="$(jq -r '.defaults.visual_direction // "Clean, accessible, responsive, and quietly confident"' "$template_file")"
  local database="$(jq -r '.defaults.database // "postgresql"' "$template_file")" database_url="postgresql://postgres:postgres@localhost:5432/${name//-/_}"
  local orm="${orm_override:-$(jq -r '.defaults.orm // "drizzle"' "$template_file")}"
  local auth="$(jq -r '.defaults.auth // "jwt"' "$template_file")" infrastructure="$(jq -r '.defaults.infrastructure // "azure"' "$template_file")"
  if (( resume_existing )); then
    description="$(jq -r '.description // "A thoughtfully designed web product"' "$project_dir/.bos/project.json")"
    visual="$(jq -r '.visual_direction // "Clean, accessible, responsive, and quietly confident"' "$project_dir/.bos/project.json")"
    database="$(jq -r '.database // "postgresql"' "$project_dir/.bos/project.json")"
    orm="$(jq -r '.orm // "drizzle"' "$project_dir/.bos/project.json")"
    auth="$(jq -r '.auth // "jwt"' "$project_dir/.bos/project.json")"
    infrastructure="$(jq -r '.infrastructure // "azure"' "$project_dir/.bos/project.json")"
    if [[ -f "$project_dir/.env.local" ]]; then
      database_url="$(sed -n 's/^DATABASE_URL=//p' "$project_dir/.env.local" | head -1)"
    fi
  elif [[ "$yes" -eq 0 ]]; then
    description="$(bos_prompt_value "Product description" "$description")"
    visual="$(bos_prompt_value "Visual direction" "$visual")"
    database="$(bos_prompt_value "Database (postgresql/mongodb/none)" "$database")"
    case "$database" in
      postgresql) database_url="postgresql://postgres:postgres@localhost:5432/${name//-/_}" ;;
      mongodb) database_url="mongodb://localhost:27017/${name//-/_}" ;;
      none) database_url="" ;;
      *) bos_die "Database must be postgresql, mongodb, or none."; return 1 ;;
    esac
    if [[ "$database" == "postgresql" && -z "$orm_override" ]]; then
      orm="$(bos_prompt_value "ORM (drizzle/prisma)" "$orm")"
    fi
    database_url="$(bos_prompt_value "Initial database URL" "$database_url")"
    auth="$(bos_prompt_value "Authentication" "$auth")"
    infrastructure="$(bos_prompt_value "Future infrastructure target" "$infrastructure")"
  fi
  if [[ "$database" == "postgresql" ]]; then
    [[ "$orm" == "drizzle" || "$orm" == "prisma" ]] || { bos_die "PostgreSQL ORM must be drizzle or prisma."; return 1; }
  else
    [[ -z "$orm_override" ]] || { bos_die "--orm is only supported with PostgreSQL."; return 1; }
    orm="none"
  fi
  cat <<EOF
Project:        $name
Path:           $project_dir
Template:       $template
Database:       $database
ORM:            $orm
Authentication: $auth
Infrastructure: $infrastructure
EOF
  if [[ "$yes" -eq 0 && "$resume_existing" -eq 0 ]]; then
    print -n "Create and install this project? [Y/n]: "
    local confirm; read -r confirm
    [[ "${confirm:l}" != "n" ]] || { bos_info "Cancelled."; return 0; }
  fi
  mkdir -p "$project_dir"
  bos_scaffold_web "$project_dir" "$name" "$description" "$visual" "$database" "$database_url" "$orm" "$auth" "$infrastructure"
  jq --arg template "$template" '.template=$template' "$project_dir/.bos/project.json" > "$project_dir/.bos/project.json.next"
  mv "$project_dir/.bos/project.json.next" "$project_dir/.bos/project.json"
  (cd "$project_dir" && pnpm install && git init -q && git add . && git -c user.name="Builder OS" -c user.email="builderos@local" commit -qm "Initialize $name")
  bos_register_project "$name" "$project_dir" "$template"
  bos_info "Created and registered $name."
  bos_info "Open it with: bos open $name"
}

bos_open() {
  bos_ensure_dirs
  local target="${1:-.}"
  [[ $# -gt 0 ]] && shift
  local project_dir
  project_dir="$(bos_resolve_project "$target")" || { bos_die "Project not found: $target"; return 1; }
  if ! bos_health; then
    print -n "No model is running. Start $(bos_selected_model)? [Y/n]: "
    local answer; read -r answer
    [[ "${answer:l}" != "n" ]] || return 1
    source "$BOS_ROOT/lib/bos/lifecycle.zsh"
    bos_start
  fi
  [[ -x "$BOS_OPENCODE_BIN" ]] || { bos_die "OpenCode not found: $BOS_OPENCODE_BIN"; return 1; }
  local active="$(bos_active_profile)"
  [[ -n "$active" ]] || { bos_die "The active model is unmanaged. Restart it through BOS."; return 1; }
  local model="$(bos_profile_value "$active" opencode_model)"
  local registered_name registered_type
  registered_name="$(jq -r --arg path "$project_dir" '.projects[] | select(.path==$path) | .name' "$BOS_PROJECTS" | head -1)"
  registered_type="$(jq -r --arg path "$project_dir" '.projects[] | select(.path==$path) | .type' "$BOS_PROJECTS" | head -1)"
  bos_register_project "${registered_name:-${project_dir:t}}" "$project_dir" "${registered_type:-$([[ -f "$project_dir/.bos/project.json" ]] && jq -r '.template' "$project_dir/.bos/project.json" || echo existing)}"
  bos_project_env
  cd "$project_dir"
  exec "$BOS_OPENCODE_BIN" --pure --model "$model" "$@" .
}

bos_dev_ready_summary() {
  local project_dir="$1"
  local services
  services="$(cd "$project_dir" && docker compose config --services 2>/dev/null || true)"

  print
  print -r -- "App ready:"
  if print -r -- "$services" | grep -qx web; then
    print -r -- "  Web:        http://localhost:3000"
  fi
  if print -r -- "$services" | grep -qx api; then
    print -r -- "  API:        http://localhost:3001"
    print -r -- "  API health: http://localhost:3001/health"
  fi
  if print -r -- "$services" | grep -qx postgres; then
    print -r -- "  PostgreSQL: postgresql://postgres:postgres@localhost:5432/$(jq -r '.name // empty' "$project_dir/.bos/project.json" 2>/dev/null | tr '-' '_' || true)"
  fi
  if print -r -- "$services" | grep -qx mongo; then
    print -r -- "  MongoDB:    mongodb://localhost:27017/$(jq -r '.name // empty' "$project_dir/.bos/project.json" 2>/dev/null | tr '-' '_' || true)"
  fi
  print
  print -r -- "Useful:"
  print -r -- "  bos dev \"$project_dir\" logs"
  print -r -- "  bos dev \"$project_dir\" stop"
  print -r -- "  bos dev \"$project_dir\" reset"
}

bos_dev() {
  bos_ensure_dirs
  local target="." action="start" verbose=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose|-v)
        verbose=1
        shift
        ;;
      start|up|stop|down|reset|restart|status|ps|logs)
        action="$1"
        shift
        ;;
      *)
        [[ "$target" == "." ]] || { bos_die "Usage: bos dev [PROJECT|PATH|.] [start|stop|reset|status|logs] [--verbose]"; return 1; }
        target="$1"
        shift
        if [[ $# -gt 0 ]]; then
          case "$1" in
            --verbose|-v) ;;
            start|up|stop|down|reset|restart|status|ps|logs) action="$1"; shift ;;
            *) bos_die "Usage: bos dev [PROJECT|PATH|.] [start|stop|reset|status|logs] [--verbose]"; return 1 ;;
          esac
        fi
        ;;
    esac
  done

  [[ $# -eq 0 ]] || { bos_die "Usage: bos dev [PROJECT|PATH|.] [start|stop|reset|status|logs] [--verbose]"; return 1; }

  local project_dir
  project_dir="$(bos_resolve_project "$target")" || { bos_die "Project not found: $target"; return 1; }
  [[ -f "$project_dir/compose.yaml" || -f "$project_dir/docker-compose.yml" || -f "$project_dir/docker-compose.yaml" ]] ||
    { bos_die "No Docker Compose file found in: $project_dir"; return 1; }
  bos_has docker || { bos_die "Docker is missing. Rerun ./install.sh from Builder OS."; return 1; }
  docker compose version >/dev/null 2>&1 ||
    { bos_die "Docker Compose is missing. Rerun ./install.sh from Builder OS."; return 1; }

  case "$action" in
    start|up)
      bos_info "Starting local app: $project_dir"
      if (( verbose )); then
        (cd "$project_dir" && docker compose up --build)
      else
        (cd "$project_dir" && docker compose up --build --detach --wait --quiet-pull && docker compose ps)
        bos_dev_ready_summary "$project_dir"
      fi
      ;;
    stop|down)
      bos_info "Stopping local app: $project_dir"
      (cd "$project_dir" && docker compose down)
      ;;
    reset|restart)
      bos_info "Resetting local app: $project_dir"
      if (( verbose )); then
        (cd "$project_dir" && docker compose down -v && docker compose up --build)
      else
        (cd "$project_dir" && docker compose down -v && docker compose up --build --detach --wait --quiet-pull && docker compose ps)
        bos_dev_ready_summary "$project_dir"
      fi
      ;;
    status|ps)
      (cd "$project_dir" && docker compose ps)
      ;;
    logs)
      (cd "$project_dir" && docker compose logs -f)
      ;;
    *)
      bos_die "Usage: bos dev [PROJECT|PATH|.] [start|stop|reset|status|logs] [--verbose]"
      return 1
      ;;
  esac
}
