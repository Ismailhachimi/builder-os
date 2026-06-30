# BOS Web Template

This is the shipped `web` template family used by `bos init`.

The generator is intentionally implemented in BOS so it can collect interactive
product and design decisions before writing files. Its versioned defaults and
stack description live in `config/templates/web.json`.

Generated projects are normal pnpm/Turbo repositories and do not depend on BOS
at runtime. BOS installs and runs them through Docker Compose by default, using
Docker-managed dependency volumes so host and container `node_modules` do not
conflict. Host `pnpm dev` remains an optional workflow when local Node.js and
pnpm match the template.

Future reusable software components and additional profiles should be added here
as ordinary, reviewable source material rather than hidden remote generators.

PostgreSQL projects use Drizzle ORM by default. Prisma remains available through
the interactive questionnaire or `bos init <name> --orm prisma`.
