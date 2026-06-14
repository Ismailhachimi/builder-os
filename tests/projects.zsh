#!/bin/zsh

source "${0:A:h}/test-helper.zsh"

for command_name in node pnpm brew; do
  cat > "$TEST_TMP/bin/$command_name" <<'EOF'
#!/bin/zsh
exit 0
EOF
done
cat > "$TEST_TMP/bin/git" <<'EOF'
#!/bin/zsh
exit 0
EOF
chmod +x "$TEST_TMP/bin/"*

target="$TEST_TMP/generated"
output="$("$BOS_ROOT/bin/bos" init demo --path "$target" --yes)"
assert_contains "$output" "Created and registered demo"
[[ -f "$target/.bos/project.json" ]] && project_exists=yes || project_exists=no
assert_eq "$project_exists" "yes"
assert_eq "$(jq -r .database "$target/.bos/project.json")" "postgresql"
assert_eq "$(jq -r .orm "$target/.bos/project.json")" "drizzle"
assert_eq "$(jq -r .schema_version "$target/.bos/project.json")" "2"
assert_eq "$(jq -r .template "$target/.bos/project.json")" "web"
[[ -f "$target/apps/api/drizzle.config.ts" && -f "$target/apps/api/src/db/schema.ts" ]] && drizzle_exists=yes || drizzle_exists=no
assert_eq "$drizzle_exists" "yes"
assert_eq "$(jq -r '.dependencies["drizzle-orm"]' "$target/apps/api/package.json")" "^0.44.2"
[[ ! -d "$target/apps/api/prisma" ]] && no_prisma=yes || no_prisma=no
assert_eq "$no_prisma" "yes"
[[ -f "$target/.env.local" && -f "$target/.env.example" ]] && env_exists=yes || env_exists=no
assert_eq "$env_exists" "yes"
assert_eq "$(jq -r '.projects[0].name' "$BOS_CONFIG_HOME/projects.json")" "demo"

mkdir -p "$TEST_TMP/workspace"
output="$(cd "$TEST_TMP/workspace" && "$BOS_ROOT/bin/bos" init local-demo --yes)"
default_target="$TEST_TMP/workspace/local-demo"
default_target="${default_target:A}"
assert_contains "$output" "Path:           $default_target"
[[ -f "$TEST_TMP/workspace/local-demo/.bos/project.json" ]] && default_path_exists=yes || default_path_exists=no
assert_eq "$default_path_exists" "yes"

interactive_target="$TEST_TMP/custom-location"
interactive_target="${interactive_target:A}"
output="$(cd "$TEST_TMP/workspace" && printf '%s\n\n\n\n\n\n\n\n\n' "$interactive_target" | "$BOS_ROOT/bin/bos" init interactive-demo)"
assert_contains "$output" "Path:           $interactive_target"
[[ -f "$interactive_target/.bos/project.json" ]] && interactive_path_exists=yes || interactive_path_exists=no
assert_eq "$interactive_path_exists" "yes"
assert_eq "$(jq -r .orm "$interactive_target/.bos/project.json")" "drizzle"

prisma_target="$TEST_TMP/prisma-project"
output="$("$BOS_ROOT/bin/bos" init prisma-demo --path "$prisma_target" --orm prisma --yes)"
assert_contains "$output" "ORM:            prisma"
assert_eq "$(jq -r .orm "$prisma_target/.bos/project.json")" "prisma"
[[ -f "$prisma_target/apps/api/prisma/schema.prisma" && ! -f "$prisma_target/apps/api/drizzle.config.ts" ]] && prisma_exists=yes || prisma_exists=no
assert_eq "$prisma_exists" "yes"

none_template="$BOS_CONFIG_HOME/templates/no-db.json"
mkdir -p "${none_template:h}"
print -r -- '{"name":"no-db","extends":"web","defaults":{"database":"none"}}' > "$none_template"
none_target="$TEST_TMP/no-db-project"
"$BOS_ROOT/bin/bos" init no-db-demo --template no-db --path "$none_target" --yes >/dev/null
assert_eq "$(jq -r .orm "$none_target/.bos/project.json")" "none"
[[ ! -d "$none_target/apps/api/prisma" && ! -f "$none_target/apps/api/drizzle.config.ts" ]] && no_orm_files=yes || no_orm_files=no
assert_eq "$no_orm_files" "yes"

if "$BOS_ROOT/bin/bos" init invalid-orm --path "$TEST_TMP/invalid-orm" --orm sequel --yes >/dev/null 2>&1; then
  invalid_orm_rejected=no
else
  invalid_orm_rejected=yes
fi
assert_eq "$invalid_orm_rejected" "yes"
[[ ! -e "$TEST_TMP/invalid-orm" ]] && invalid_orm_clean=yes || invalid_orm_clean=no
assert_eq "$invalid_orm_clean" "yes"

mkdir -p "$TEST_TMP/existing-project"
output="$("$BOS_ROOT/bin/bos" project register "$TEST_TMP/existing-project")"
assert_contains "$output" "Registered project: existing-project"
assert_eq "$(jq -r '.projects[] | select(.name=="existing-project") | .type' "$BOS_CONFIG_HOME/projects.json")" "existing"

mkdir -p "$TEST_TMP/moved-project/.bos"
print -r -- '{"template":"custom-web"}' > "$TEST_TMP/moved-project/.bos/project.json"
output="$(cd "$TEST_TMP/moved-project" && "$BOS_ROOT/bin/bos" project register . --name existing-project)"
assert_contains "$output" "Type: custom-web"
assert_eq "$(jq -r '.projects[] | select(.name=="existing-project") | .path' "$BOS_CONFIG_HOME/projects.json")" "${TEST_TMP:A}/moved-project"
assert_eq "$(jq '[.projects[] | select(.name=="existing-project")] | length' "$BOS_CONFIG_HOME/projects.json")" "1"

output="$("$BOS_ROOT/bin/bos" project register "$TEST_TMP/existing-project" --name legacy --type api)"
assert_contains "$output" "Type: api"
assert_eq "$(jq -r '.projects[] | select(.name=="legacy") | .type' "$BOS_CONFIG_HOME/projects.json")" "api"

finish_tests
