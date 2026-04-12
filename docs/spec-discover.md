# Spec: Discover Step — v2

---

## Overview

**File**: `lib/discover.sh`
**Input**: Project root directory (current working directory)
**Output**: `.claude/harness/project-context.json`
**Executor**: Pure shell script (no LLM)
**Changes from v1**: Minimal — context schema version bumped to 2.0, output references updated.

---

## Detailed Detection Logic

### Language & Stack Detection

```bash
detect_stack() {
  local root="$1"
  local languages=""
  local frameworks=""
  local pkg_manager=""
  local test_fw=""
  local linter=""
  local formatter=""

  # --- Languages ---
  [ -f "$root/go.mod" ]                     && languages="$languages go"
  [ -f "$root/Cargo.toml" ]                 && languages="$languages rust"
  [ -f "$root/pom.xml" ] || [ -f "$root/build.gradle" ] && languages="$languages java"
  [ -f "$root/pyproject.toml" ] || [ -f "$root/requirements.txt" ] && languages="$languages python"

  # Node.js — check package.json for more detail
  if [ -f "$root/package.json" ]; then
    languages="$languages javascript"

    # TypeScript?
    [ -f "$root/tsconfig.json" ] && languages="$languages typescript"

    # Framework detection from dependencies
    local deps="$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' "$root/package.json" 2>/dev/null)"

    echo "$deps" | grep -q "^next$"          && frameworks="$frameworks nextjs"
    echo "$deps" | grep -q "^nuxt$"          && frameworks="$frameworks nuxt"
    echo "$deps" | grep -q "^react$"         && frameworks="$frameworks react"
    echo "$deps" | grep -q "^vue$"           && frameworks="$frameworks vue"
    echo "$deps" | grep -q "^svelte$"        && frameworks="$frameworks svelte"
    echo "$deps" | grep -q "^express$"       && frameworks="$frameworks express"
    echo "$deps" | grep -q "^fastify$"       && frameworks="$frameworks fastify"
    echo "$deps" | grep -q "^hono$"          && frameworks="$frameworks hono"

    # Package manager
    [ -f "$root/pnpm-lock.yaml" ]   && pkg_manager="pnpm"
    [ -f "$root/yarn.lock" ]        && pkg_manager="yarn"
    [ -f "$root/bun.lockb" ]        && pkg_manager="bun"
    [ -f "$root/package-lock.json" ] && [ -z "$pkg_manager" ] && pkg_manager="npm"

    # Test framework
    echo "$deps" | grep -q "^vitest$"        && test_fw="vitest"
    echo "$deps" | grep -q "^jest$"          && [ -z "$test_fw" ] && test_fw="jest"
    echo "$deps" | grep -q "^playwright$"    && test_fw="$test_fw playwright"
    echo "$deps" | grep -q "^cypress$"       && test_fw="$test_fw cypress"

    # Linter & formatter
    echo "$deps" | grep -q "^eslint$"        && linter="eslint"
    echo "$deps" | grep -q "^biome$"         && linter="biome"
    echo "$deps" | grep -q "^prettier$"      && formatter="prettier"
    echo "$deps" | grep -q "^@biomejs"       && formatter="biome"
  fi

  # Python specifics
  if [ -f "$root/pyproject.toml" ]; then
    grep -q "django" "$root/pyproject.toml"  && frameworks="$frameworks django"
    grep -q "fastapi" "$root/pyproject.toml" && frameworks="$frameworks fastapi"
    grep -q "flask" "$root/pyproject.toml"   && frameworks="$frameworks flask"
    grep -q "pytest" "$root/pyproject.toml"  && test_fw="pytest"
    grep -q "ruff" "$root/pyproject.toml"    && linter="ruff"
    grep -q "black" "$root/pyproject.toml"   && formatter="black"
  fi

  # Go specifics
  if [ -f "$root/go.mod" ]; then
    grep -q "gin-gonic" "$root/go.mod"       && frameworks="$frameworks gin"
    grep -q "fiber" "$root/go.mod"           && frameworks="$frameworks fiber"
    grep -q "echo" "$root/go.mod"            && frameworks="$frameworks echo"
    test_fw="go-test"
    linter="$(command -v golangci-lint >/dev/null 2>&1 && echo 'golangci-lint')"
  fi

  # Output as JSON fragment
  echo "{
    \"languages\": $(to_json_array $languages),
    \"frameworks\": $(to_json_array $frameworks),
    \"package_manager\": \"${pkg_manager:-unknown}\",
    \"test_framework\": \"$(echo $test_fw | xargs)\",
    \"linter\": \"${linter:-none}\",
    \"formatter\": \"${formatter:-none}\"
  }"
}
```

### Infrastructure Detection

```bash
detect_infrastructure() {
  local root="$1"
  local containerized=false
  local ci_cd="none"
  local deployment="none"
  local database="none"

  # Containerization
  [ -f "$root/Dockerfile" ] || [ -f "$root/docker-compose.yml" ] || [ -f "$root/docker-compose.yaml" ] && containerized=true

  # CI/CD
  [ -d "$root/.github/workflows" ] && [ "$(ls -A "$root/.github/workflows" 2>/dev/null)" ] && ci_cd="github-actions"
  [ -f "$root/.gitlab-ci.yml" ]    && ci_cd="gitlab-ci"
  [ -f "$root/.circleci/config.yml" ] && ci_cd="circleci"
  [ -f "$root/Jenkinsfile" ]       && ci_cd="jenkins"

  # Deployment
  [ -f "$root/vercel.json" ] || [ -f "$root/.vercel" ] && deployment="vercel"
  [ -f "$root/netlify.toml" ]      && deployment="netlify"
  [ -f "$root/fly.toml" ]         && deployment="fly"
  [ -f "$root/railway.json" ]     && deployment="railway"
  [ -f "$root/render.yaml" ]      && deployment="render"

  # Database (check for ORMs, migration dirs, config files)
  if [ -f "$root/package.json" ]; then
    local deps="$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' "$root/package.json" 2>/dev/null)"
    echo "$deps" | grep -q "^prisma$"        && database="postgresql"
    echo "$deps" | grep -q "^drizzle-orm$"   && database="postgresql"
    echo "$deps" | grep -q "^mongoose$"      && database="mongodb"
    echo "$deps" | grep -q "^@supabase"      && database="supabase"
  fi
  [ -f "$root/supabase/config.toml" ]        && database="supabase"
  [ -d "$root/migrations" ] || [ -d "$root/prisma" ] && [ "$database" = "none" ] && database="unknown-sql"

  echo "{
    \"containerized\": $containerized,
    \"ci_cd\": \"$ci_cd\",
    \"deployment\": \"$deployment\",
    \"database\": \"$database\"
  }"
}
```

### Project Shape Detection

```bash
detect_shape() {
  local root="$1"
  local type="single"
  local services=""

  # Monorepo detection
  [ -f "$root/turbo.json" ]              && type="monorepo"
  [ -f "$root/lerna.json" ]              && type="monorepo"
  [ -f "$root/pnpm-workspace.yaml" ]     && type="monorepo"
  [ -f "$root/nx.json" ]                && type="monorepo"

  # Service detection
  if [ -f "$root/docker-compose.yml" ] || [ -f "$root/docker-compose.yaml" ]; then
    local compose_file="$([ -f "$root/docker-compose.yml" ] && echo "$root/docker-compose.yml" || echo "$root/docker-compose.yaml")"
    services="$(jq -r '.services | keys[]' "$compose_file" 2>/dev/null || yq -r '.services | keys[]' "$compose_file" 2>/dev/null)"
  fi

  # Monorepo package detection
  if [ "$type" = "monorepo" ]; then
    if [ -d "$root/apps" ]; then
      services="$(ls -1 "$root/apps" 2>/dev/null | head -20)"
    elif [ -d "$root/packages" ]; then
      services="$(ls -1 "$root/packages" 2>/dev/null | head -20)"
    fi
  fi

  # Top-level directory listing (source dirs only)
  local top_dirs="$(ls -1d "$root"/*/ 2>/dev/null | xargs -I{} basename {} | grep -v -E '^(node_modules|\.git|dist|build|\.next|\.nuxt|vendor|target|__pycache__)$' | head -20)"

  # Estimated file count (fast, respects .harnessignore)
  local file_count="$(find_with_ignore "$root" -type f 2>/dev/null | wc -l | xargs)"

  echo "{
    \"type\": \"$type\",
    \"services\": $(echo "$services" | to_json_array_from_lines),
    \"top_level_dirs\": $(echo "$top_dirs" | to_json_array_from_lines),
    \"estimated_file_count\": $file_count
  }"
}
```

### AI/Agent Indicator Detection

```bash
detect_ai_indicators() {
  local root="$1"
  local has_agents=false
  local has_mcp=false
  local ai_sdk=""

  # Agent directories
  [ -d "$root/agents" ] || [ -d "$root/agent" ] && has_agents=true

  # MCP config
  [ -f "$root/.mcp.json" ] || [ -d "$root/mcp" ] || [ -f "$root/mcp.json" ] && has_mcp=true

  # AI SDK detection
  if find_with_ignore "$root" -name "*.ts" -o -name "*.js" -o -name "*.py" 2>/dev/null | head -500 | xargs grep -l "@ai-sdk\|langchain\|openai\|anthropic\|@google/generative" 2>/dev/null | head -1 > /dev/null; then
    find_with_ignore "$root" -name "*.ts" -o -name "*.js" 2>/dev/null | head -500 | xargs grep -h "from ['\"]@ai-sdk\|from ['\"]openai\|from ['\"]anthropic\|from ['\"]langchain" 2>/dev/null | sort -u | while read -r line; do
      case "$line" in
        *@ai-sdk*)    echo "@ai-sdk" ;;
        *openai*)     echo "openai" ;;
        *anthropic*)  echo "anthropic" ;;
        *langchain*)  echo "langchain" ;;
      esac
    done | sort -u > /tmp/harness_ai_sdk
    ai_sdk="$(cat /tmp/harness_ai_sdk 2>/dev/null)"
    rm -f /tmp/harness_ai_sdk
    [ -n "$ai_sdk" ] && has_agents=true
  fi

  # CLAUDE.md already exists = likely uses AI agents
  [ -f "$root/CLAUDE.md" ] && has_agents=true

  echo "{
    \"has_agents\": $has_agents,
    \"has_mcp\": $has_mcp,
    \"ai_sdk\": $(echo "$ai_sdk" | to_json_array_from_lines)
  }"
}
```

### Collaboration Detection

```bash
detect_collaboration() {
  local root="$1"
  local team_size="unknown"
  local has_codeowners=false
  local has_pr_template=false
  local contributor_count=0

  [ -f "$root/CODEOWNERS" ] || [ -f "$root/.github/CODEOWNERS" ] && has_codeowners=true
  [ -f "$root/.github/pull_request_template.md" ] || [ -d "$root/.github/PULL_REQUEST_TEMPLATE" ] && has_pr_template=true

  # Git contributor count (fast, last 6 months)
  if command -v git >/dev/null 2>&1 && [ -d "$root/.git" ]; then
    contributor_count="$(git -C "$root" shortlog -sn --since="6 months ago" 2>/dev/null | wc -l | xargs)"
  fi

  # Infer team size
  if [ "$contributor_count" -gt 5 ]; then
    team_size="5+"
  elif [ "$contributor_count" -gt 1 ]; then
    team_size="2-5"
  elif [ "$contributor_count" -eq 1 ]; then
    team_size="1"
  fi

  echo "{
    \"team_size\": \"$team_size\",
    \"has_codeowners\": $has_codeowners,
    \"has_pr_template\": $has_pr_template,
    \"contributor_count\": $contributor_count
  }"
}
```

### Convention Detection

```bash
detect_conventions() {
  local root="$1"

  local has_eslint=false
  local has_prettier=false
  local has_editorconfig=false
  local ts_strict=false
  local test_pattern=""

  [ -f "$root/.eslintrc" ] || [ -f "$root/.eslintrc.js" ] || [ -f "$root/.eslintrc.json" ] || [ -f "$root/eslint.config.js" ] || [ -f "$root/eslint.config.mjs" ] && has_eslint=true
  [ -f "$root/.prettierrc" ] || [ -f "$root/.prettierrc.js" ] || [ -f "$root/.prettierrc.json" ] || [ -f "$root/prettier.config.js" ] && has_prettier=true
  [ -f "$root/.editorconfig" ] && has_editorconfig=true

  # TypeScript strictness
  if [ -f "$root/tsconfig.json" ]; then
    local strict="$(jq -r '.compilerOptions.strict // false' "$root/tsconfig.json" 2>/dev/null)"
    [ "$strict" = "true" ] && ts_strict=true
  fi

  # Test pattern inference
  if find_with_ignore "$root" -name "*.test.ts" 2>/dev/null | head -1 > /dev/null; then
    test_pattern="**/*.test.ts"
  elif find_with_ignore "$root" -name "*.spec.ts" 2>/dev/null | head -1 > /dev/null; then
    test_pattern="**/*.spec.ts"
  elif find_with_ignore "$root" -name "*_test.go" 2>/dev/null | head -1 > /dev/null; then
    test_pattern="**/*_test.go"
  elif find_with_ignore "$root" -name "test_*.py" 2>/dev/null | head -1 > /dev/null; then
    test_pattern="**/test_*.py"
  fi

  echo "{
    \"has_eslint\": $has_eslint,
    \"has_prettier\": $has_prettier,
    \"has_editorconfig\": $has_editorconfig,
    \"typescript_strict\": $ts_strict,
    \"test_pattern\": \"$test_pattern\"
  }"
}
```

---

## Fixed Questions Logic

Questions are only asked when specific signals are ambiguous. NOT all questions every time.

```bash
ask_questions_if_needed() {
  local context_file="$1"

  # Question 1: Autonomous agents — only ask if has_agents=false but has tools/ or mcp/
  local has_agents="$(json_get "$context_file" ".ai_indicators.has_agents")"
  local has_tools_dir="$([ -d "$PROJECT_ROOT/tools" ] && echo true || echo false)"

  if [ "$has_agents" = "false" ] && [ "$has_tools_dir" = "true" ]; then
    if [ "$HARNESS_FLAG_SKIP_QUESTIONS" != "1" ]; then
      printf "Does this project have AI agents running autonomously? [y/N] "
      read -r answer
      [ "$answer" = "y" ] || [ "$answer" = "Y" ] && json_set "$context_file" ".user_answers.autonomous_agents" 'true'
    fi
  fi

  # Question 2: Team size — only ask if git history unavailable or contributor_count=0
  local team_size="$(json_get "$context_file" ".collaboration.team_size")"
  if [ "$team_size" = "unknown" ]; then
    if [ "$HARNESS_FLAG_SKIP_QUESTIONS" != "1" ]; then
      printf "How many people work on this project? [1/2-5/5+] "
      read -r answer
      case "$answer" in
        1)    json_set "$context_file" ".collaboration.team_size" '"1"' ;;
        2-5)  json_set "$context_file" ".collaboration.team_size" '"2-5"' ;;
        5+)   json_set "$context_file" ".collaboration.team_size" '"5+"' ;;
        *)    json_set "$context_file" ".collaboration.team_size" '"1"' ;;
      esac
    else
      json_set "$context_file" ".collaboration.team_size" '"1"'
    fi
  fi

  # Question 3: Side effects — only ask if has_agents=true but no deployment/database detected
  if [ "$has_agents" = "true" ]; then
    local deployment="$(json_get "$context_file" ".infrastructure.deployment")"
    local database="$(json_get "$context_file" ".infrastructure.database")"
    if [ "$deployment" = "none" ] && [ "$database" = "none" ]; then
      if [ "$HARNESS_FLAG_SKIP_QUESTIONS" != "1" ]; then
        printf "Does the agent have real side effects? (file write / API call / deploy) [y/N] "
        read -r answer
        [ "$answer" = "y" ] || [ "$answer" = "Y" ] && json_set "$context_file" ".user_answers.side_effects" '["file_write","api_call"]'
      fi
    fi
  fi
}
```

---

## `.harnessignore` Integration

```bash
find_with_ignore() {
  local root="$1"
  shift
  local ignore_file="$root/.harnessignore"

  local exclude_args=""
  if [ -f "$ignore_file" ]; then
    while IFS= read -r pattern; do
      [ -z "$pattern" ] || [ "${pattern#\#}" != "$pattern" ] && continue
      exclude_args="$exclude_args -not -path '*/$pattern/*' -not -path '*/$pattern'"
    done < "$ignore_file"
  else
    for p in node_modules .git dist build .next .nuxt __pycache__ vendor target .terraform; do
      exclude_args="$exclude_args -not -path '*/$p/*'"
    done
  fi

  eval "find \"$root\" $exclude_args $*"
}
```

---

## Assembly — project-context.json

```bash
assemble_context() {
  local root="$1"
  local output="$root/.claude/harness/project-context.json"

  mkdir -p "$root/.claude/harness"

  local stack="$(detect_stack "$root")"
  local infra="$(detect_infrastructure "$root")"
  local shape="$(detect_shape "$root")"
  local ai="$(detect_ai_indicators "$root")"
  local collab="$(detect_collaboration "$root")"
  local conventions="$(detect_conventions "$root")"

  # Assemble — version 2.0
  jq -n \
    --arg version "2.0" \
    --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg root "$root" \
    --arg name "$(basename "$root")" \
    --argjson stack "$stack" \
    --argjson infra "$infra" \
    --argjson shape "$shape" \
    --argjson ai "$ai" \
    --argjson collab "$collab" \
    --argjson conventions "$conventions" \
    '{
      version: $version,
      generated_at: $generated_at,
      project: { root: $root, name: $name },
      stack: $stack,
      infrastructure: $infra,
      shape: $shape,
      ai_indicators: $ai,
      collaboration: $collab,
      conventions: $conventions,
      user_answers: {}
    }' > "$output"

  # Ask questions if needed
  ask_questions_if_needed "$output"

  # Add hash
  local hash="$(hash_file "$output")"
  json_set "$output" ".hash" "\"sha256:$hash\""

  log_success "Discovery complete: $output"
}
```

---

## Edge Cases

| Case | Handling |
|---|---|
| Empty directory | Exit 2: "No project files found" |
| Only .git exists | Exit 2: "No recognizable project" |
| Very large project (10k+ files) | find_with_ignore has timeout + .harnessignore. Discovery still works but skips deep grep for AI SDK |
| Binary/media project | Stack detection returns empty → tier defaults to minimal |
| Multiple package.json (monorepo) | Read root package.json only for stack. Detect monorepo via turbo.json etc. |
| No git history | collaboration.team_size = "unknown" → triggers question |
| CLAUDE.md already exists | ai_indicators.has_agents = true. Existing content preserved by write step |
| Read permission denied | Skip that file/dir, log warning, continue discovery |
