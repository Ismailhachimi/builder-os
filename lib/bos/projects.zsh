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

bos_project() {
  local sub="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$sub" in
    register) bos_project_register "$@" ;;
    *) bos_die "Usage: bos project register [PATH|.] [--name NAME] [--type TYPE]"; return 1 ;;
  esac
}

bos_prompt_value() {
  local prompt="$1" default="$2" answer
  print -u2 -n -r -- "$prompt [$default]: "
  read -r answer
  print -r -- "${answer:-$default}"
}

bos_install_web_tools() {
  if ! bos_has node; then
    case "$BOS_PLATFORM" in
      darwin) bos_info "Installing Node.js with Homebrew..."; brew install node ;;
      linux)
        bos_has corepack || { bos_die "Node.js is missing. Install a current Node.js release, then rerun bos init."; return 1; }
        ;;
    esac
  fi
  if ! bos_has pnpm; then
    if bos_has corepack; then
      bos_info "Enabling pnpm with Corepack..."
      corepack enable pnpm
    elif [[ "$BOS_PLATFORM" == "darwin" ]] && bos_has brew; then
      bos_info "Installing pnpm with Homebrew..."
      brew install pnpm
    else
      bos_die "pnpm is missing. Install pnpm or enable Corepack, then rerun bos init."
      return 1
    fi
  fi
}

bos_scaffold_web() {
  local project_dir="$1" name="$2" description="$3" visual="$4" database="$5" database_url="$6" orm="$7" auth="$8" infrastructure="$9"
  local example_database_url="$database_url" data_stack="$database"
  [[ "$orm" != "none" ]] && data_stack="$database with $orm"
  [[ "$database" == "postgresql" ]] && example_database_url="postgresql://postgres:postgres@localhost:5432/app"
  [[ "$database" == "mongodb" ]] && example_database_url="mongodb://localhost:27017/app"
  mkdir -p "$project_dir/apps/web/app" "$project_dir/apps/api/src/auth" "$project_dir/packages/contracts/src" "$project_dir/docs" "$project_dir/.bos"

  cat > "$project_dir/package.json" <<EOF
{
  "name": "$name",
  "private": true,
  "packageManager": "pnpm@10.12.1",
  "scripts": {
    "dev": "turbo dev",
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
  cat > "$project_dir/README.md" <<EOF
# $name

$description

## Stack

Turbo, pnpm, Next.js, NestJS, shared Zod contracts, $data_stack, and $auth auth.

## Development

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
  if [[ "$yes" -eq 0 && "$explicit_path" -eq 0 ]]; then
    project_dir="$(bos_prompt_value "Project path" "$project_dir")"
    [[ -n "$project_dir" ]] || { bos_die "Project path cannot be empty."; return 1; }
  fi
  project_dir="${project_dir:A}"
  [[ ! -e "$project_dir" || -z "$(find "$project_dir" -mindepth 1 -print -quit 2>/dev/null)" ]] || { bos_die "Refusing to overwrite non-empty directory: $project_dir"; return 1; }
  local description="$(jq -r '.defaults.description // "A thoughtfully designed web product"' "$template_file")"
  local visual="$(jq -r '.defaults.visual_direction // "Clean, accessible, responsive, and quietly confident"' "$template_file")"
  local database="$(jq -r '.defaults.database // "postgresql"' "$template_file")" database_url="postgresql://postgres:postgres@localhost:5432/${name//-/_}"
  local orm="${orm_override:-$(jq -r '.defaults.orm // "drizzle"' "$template_file")}"
  local auth="$(jq -r '.defaults.auth // "jwt"' "$template_file")" infrastructure="$(jq -r '.defaults.infrastructure // "azure"' "$template_file")"
  if [[ "$yes" -eq 0 ]]; then
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
  if [[ "$yes" -eq 0 ]]; then
    print -n "Create and install this project? [Y/n]: "
    local confirm; read -r confirm
    [[ "${confirm:l}" != "n" ]] || { bos_info "Cancelled."; return 0; }
  fi
  bos_install_web_tools
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
