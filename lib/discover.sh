#!/bin/sh
# harness discover — Project discovery engine
# Detects stack, infrastructure, shape, AI indicators, collaboration, conventions
# Output: .claude/harness/project-context.json

# ── Stack Detection ──────────────────────────────────────────────────────────

detect_stack() {
    log_step "Detecting stack..."

    # Languages
    _languages=""
    [ -f "$PROJECT_ROOT/go.mod" ] && _languages="${_languages}\"go\","
    [ -f "$PROJECT_ROOT/Cargo.toml" ] && _languages="${_languages}\"rust\","
    [ -f "$PROJECT_ROOT/pom.xml" ] || [ -f "$PROJECT_ROOT/build.gradle" ] && _languages="${_languages}\"java\","
    [ -f "$PROJECT_ROOT/requirements.txt" ] || [ -f "$PROJECT_ROOT/pyproject.toml" ] || [ -f "$PROJECT_ROOT/setup.py" ] || [ -f "$PROJECT_ROOT/Pipfile" ] && _languages="${_languages}\"python\","
    [ -f "$PROJECT_ROOT/tsconfig.json" ] && _languages="${_languages}\"typescript\","
    [ -f "$PROJECT_ROOT/package.json" ] && ! [ -f "$PROJECT_ROOT/tsconfig.json" ] && _languages="${_languages}\"javascript\","
    [ -f "$PROJECT_ROOT/Gemfile" ] && _languages="${_languages}\"ruby\","
    [ -f "$PROJECT_ROOT/mix.exs" ] && _languages="${_languages}\"elixir\","
    _languages=$(printf '%s' "$_languages" | sed 's/,$//')

    # Frameworks
    _frameworks=""
    if [ -f "$PROJECT_ROOT/package.json" ]; then
        _pkg=$(cat "$PROJECT_ROOT/package.json")
        printf '%s' "$_pkg" | grep -q '"next"' && _frameworks="${_frameworks}\"nextjs\","
        printf '%s' "$_pkg" | grep -q '"nuxt"' && _frameworks="${_frameworks}\"nuxt\","
        printf '%s' "$_pkg" | grep -q '"react"' && ! printf '%s' "$_pkg" | grep -q '"next"' && _frameworks="${_frameworks}\"react\","
        printf '%s' "$_pkg" | grep -q '"vue"' && ! printf '%s' "$_pkg" | grep -q '"nuxt"' && _frameworks="${_frameworks}\"vue\","
        printf '%s' "$_pkg" | grep -q '"svelte"' && _frameworks="${_frameworks}\"svelte\","
        printf '%s' "$_pkg" | grep -q '"express"' && _frameworks="${_frameworks}\"express\","
        printf '%s' "$_pkg" | grep -q '"fastify"' && _frameworks="${_frameworks}\"fastify\","
        printf '%s' "$_pkg" | grep -q '"hono"' && _frameworks="${_frameworks}\"hono\","
        printf '%s' "$_pkg" | grep -q '"@angular/core"' && _frameworks="${_frameworks}\"angular\","
    fi
    if [ -f "$PROJECT_ROOT/requirements.txt" ] || [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
        _pyfiles="$PROJECT_ROOT/requirements.txt $PROJECT_ROOT/pyproject.toml"
        for _pf in $_pyfiles; do
            if [ -f "$_pf" ]; then
                grep -qi 'django' "$_pf" 2>/dev/null && _frameworks="${_frameworks}\"django\","
                grep -qi 'fastapi' "$_pf" 2>/dev/null && _frameworks="${_frameworks}\"fastapi\","
                grep -qi 'flask' "$_pf" 2>/dev/null && _frameworks="${_frameworks}\"flask\","
            fi
        done
    fi
    if [ -f "$PROJECT_ROOT/go.mod" ]; then
        grep -q 'gin-gonic/gin' "$PROJECT_ROOT/go.mod" 2>/dev/null && _frameworks="${_frameworks}\"gin\","
        grep -q 'gofiber/fiber' "$PROJECT_ROOT/go.mod" 2>/dev/null && _frameworks="${_frameworks}\"fiber\","
        grep -q 'labstack/echo' "$PROJECT_ROOT/go.mod" 2>/dev/null && _frameworks="${_frameworks}\"echo\","
    fi
    _frameworks=$(printf '%s' "$_frameworks" | sed 's/,$//')

    # Package manager
    _pkg_manager="null"
    if [ -f "$PROJECT_ROOT/pnpm-lock.yaml" ]; then
        _pkg_manager="\"pnpm\""
    elif [ -f "$PROJECT_ROOT/yarn.lock" ]; then
        _pkg_manager="\"yarn\""
    elif [ -f "$PROJECT_ROOT/bun.lockb" ] || [ -f "$PROJECT_ROOT/bun.lock" ]; then
        _pkg_manager="\"bun\""
    elif [ -f "$PROJECT_ROOT/package-lock.json" ]; then
        _pkg_manager="\"npm\""
    elif [ -f "$PROJECT_ROOT/go.mod" ]; then
        _pkg_manager="\"go-modules\""
    elif [ -f "$PROJECT_ROOT/Cargo.lock" ]; then
        _pkg_manager="\"cargo\""
    elif [ -f "$PROJECT_ROOT/Pipfile.lock" ]; then
        _pkg_manager="\"pipenv\""
    elif [ -f "$PROJECT_ROOT/poetry.lock" ]; then
        _pkg_manager="\"poetry\""
    elif [ -f "$PROJECT_ROOT/uv.lock" ]; then
        _pkg_manager="\"uv\""
    fi

    # Test framework
    _test_framework="null"
    if [ -f "$PROJECT_ROOT/package.json" ]; then
        _pkg=$(cat "$PROJECT_ROOT/package.json")
        printf '%s' "$_pkg" | grep -q '"vitest"' && _test_framework="\"vitest\""
        printf '%s' "$_pkg" | grep -q '"jest"' && [ "$_test_framework" = "null" ] && _test_framework="\"jest\""
        printf '%s' "$_pkg" | grep -q '"playwright"' && _test_framework="\"playwright\""
        printf '%s' "$_pkg" | grep -q '"cypress"' && [ "$_test_framework" = "null" ] && _test_framework="\"cypress\""
    fi
    [ -f "$PROJECT_ROOT/go.mod" ] && [ "$_test_framework" = "null" ] && _test_framework="\"go-test\""
    [ -f "$PROJECT_ROOT/pytest.ini" ] || [ -f "$PROJECT_ROOT/pyproject.toml" ] && grep -qi 'pytest' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null && [ "$_test_framework" = "null" ] && _test_framework="\"pytest\""

    # Linter
    _linter="null"
    if [ -f "$PROJECT_ROOT/.eslintrc.json" ] || [ -f "$PROJECT_ROOT/.eslintrc.js" ] || [ -f "$PROJECT_ROOT/.eslintrc.cjs" ] || [ -f "$PROJECT_ROOT/eslint.config.js" ] || [ -f "$PROJECT_ROOT/eslint.config.mjs" ] || [ -f "$PROJECT_ROOT/eslint.config.ts" ]; then
        _linter="\"eslint\""
    fi
    if [ -f "$PROJECT_ROOT/biome.json" ] || [ -f "$PROJECT_ROOT/biome.jsonc" ]; then
        _linter="\"biome\""
    fi
    [ -f "$PROJECT_ROOT/ruff.toml" ] || ([ -f "$PROJECT_ROOT/pyproject.toml" ] && grep -qi '\[tool.ruff\]' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null) && _linter="\"ruff\""
    [ -f "$PROJECT_ROOT/.golangci.yml" ] || [ -f "$PROJECT_ROOT/.golangci.yaml" ] && _linter="\"golangci-lint\""

    # Formatter
    _formatter="null"
    if [ -f "$PROJECT_ROOT/.prettierrc" ] || [ -f "$PROJECT_ROOT/.prettierrc.json" ] || [ -f "$PROJECT_ROOT/.prettierrc.js" ] || [ -f "$PROJECT_ROOT/.prettierrc.cjs" ] || [ -f "$PROJECT_ROOT/prettier.config.js" ] || [ -f "$PROJECT_ROOT/prettier.config.mjs" ]; then
        _formatter="\"prettier\""
    fi
    [ "$_linter" = '"biome"' ] && _formatter="\"biome\""
    [ "$_linter" = '"ruff"' ] && _formatter="\"ruff\""
    ([ -f "$PROJECT_ROOT/pyproject.toml" ] && grep -qi '\[tool.black\]' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null) && _formatter="\"black\""
    [ -f "$PROJECT_ROOT/rustfmt.toml" ] && _formatter="\"rustfmt\""
    [ -f "$PROJECT_ROOT/.gofmt" ] || [ -f "$PROJECT_ROOT/go.mod" ] && [ "$_formatter" = "null" ] && _formatter="\"gofmt\""

    STACK_JSON=$(cat <<EOF
{
    "languages": [${_languages}],
    "frameworks": [${_frameworks}],
    "package_manager": ${_pkg_manager},
    "test_framework": ${_test_framework},
    "linter": ${_linter},
    "formatter": ${_formatter}
}
EOF
)
    log_verbose "Stack: $_languages | Frameworks: $_frameworks"
}

# ── Infrastructure Detection ─────────────────────────────────────────────────

detect_infrastructure() {
    log_step "Detecting infrastructure..."

    # Containerization
    _containerized=false
    if [ -f "$PROJECT_ROOT/Dockerfile" ] || [ -f "$PROJECT_ROOT/docker-compose.yml" ] || [ -f "$PROJECT_ROOT/docker-compose.yaml" ] || [ -f "$PROJECT_ROOT/compose.yml" ] || [ -f "$PROJECT_ROOT/compose.yaml" ]; then
        _containerized=true
    fi

    # CI/CD
    _ci_cd="null"
    [ -d "$PROJECT_ROOT/.github/workflows" ] && _ci_cd="\"github-actions\""
    [ -f "$PROJECT_ROOT/.gitlab-ci.yml" ] && _ci_cd="\"gitlab-ci\""
    [ -f "$PROJECT_ROOT/.circleci/config.yml" ] && _ci_cd="\"circleci\""
    [ -f "$PROJECT_ROOT/Jenkinsfile" ] && _ci_cd="\"jenkins\""
    [ -f "$PROJECT_ROOT/bitbucket-pipelines.yml" ] && _ci_cd="\"bitbucket\""

    # Deployment
    _deployment="null"
    [ -f "$PROJECT_ROOT/vercel.json" ] && _deployment="\"vercel\""
    [ -f "$PROJECT_ROOT/netlify.toml" ] && _deployment="\"netlify\""
    [ -f "$PROJECT_ROOT/fly.toml" ] && _deployment="\"fly\""
    [ -f "$PROJECT_ROOT/railway.json" ] || [ -f "$PROJECT_ROOT/railway.toml" ] && _deployment="\"railway\""
    [ -f "$PROJECT_ROOT/render.yaml" ] && _deployment="\"render\""
    [ -f "$PROJECT_ROOT/app.yaml" ] || [ -f "$PROJECT_ROOT/app.yml" ] && _deployment="\"gcp\""
    [ -f "$PROJECT_ROOT/serverless.yml" ] || [ -f "$PROJECT_ROOT/serverless.yaml" ] && _deployment="\"serverless\""

    # Check package.json scripts for deployment hints
    if [ "$_deployment" = "null" ] && [ -f "$PROJECT_ROOT/package.json" ]; then
        _pkg=$(cat "$PROJECT_ROOT/package.json")
        printf '%s' "$_pkg" | grep -q '"vercel"' && _deployment="\"vercel\""
    fi

    # Next.js auto-implies vercel if no other deployment
    if [ "$_deployment" = "null" ] && printf '%s' "$_frameworks" | grep -q 'nextjs'; then
        _deployment="\"vercel\""
    fi

    # Database
    _database="null"
    if [ -f "$PROJECT_ROOT/prisma/schema.prisma" ]; then
        _database="\"prisma\""
    elif [ -f "$PROJECT_ROOT/drizzle.config.ts" ] || [ -f "$PROJECT_ROOT/drizzle.config.js" ]; then
        _database="\"drizzle\""
    fi
    if [ -f "$PROJECT_ROOT/package.json" ]; then
        _pkg=$(cat "$PROJECT_ROOT/package.json")
        printf '%s' "$_pkg" | grep -q '"@supabase/supabase-js"' && _database="\"supabase\""
        printf '%s' "$_pkg" | grep -q '"mongoose"' && [ "$_database" = "null" ] && _database="\"mongodb\""
    fi
    if [ -f "$PROJECT_ROOT/docker-compose.yml" ] || [ -f "$PROJECT_ROOT/docker-compose.yaml" ]; then
        _compose="${PROJECT_ROOT}/docker-compose.yml"
        [ ! -f "$_compose" ] && _compose="${PROJECT_ROOT}/docker-compose.yaml"
        if [ -f "$_compose" ]; then
            grep -q 'postgres' "$_compose" 2>/dev/null && [ "$_database" = "null" ] && _database="\"postgresql\""
            grep -q 'mysql' "$_compose" 2>/dev/null && [ "$_database" = "null" ] && _database="\"mysql\""
            grep -q 'mongo' "$_compose" 2>/dev/null && [ "$_database" = "null" ] && _database="\"mongodb\""
            grep -q 'redis' "$_compose" 2>/dev/null && [ "$_database" = "null" ] && _database="\"redis\""
        fi
    fi

    INFRA_JSON=$(cat <<EOF
{
    "containerized": ${_containerized},
    "ci_cd": ${_ci_cd},
    "deployment": ${_deployment},
    "database": ${_database}
}
EOF
)
    log_verbose "Infra: container=$_containerized ci=$_ci_cd deploy=$_deployment db=$_database"
}

# ── Shape Detection ──────────────────────────────────────────────────────────

detect_shape() {
    log_step "Detecting project shape..."

    # Monorepo indicators
    _type="single"
    if [ -f "$PROJECT_ROOT/pnpm-workspace.yaml" ] || [ -f "$PROJECT_ROOT/lerna.json" ] || [ -f "$PROJECT_ROOT/turbo.json" ] || [ -f "$PROJECT_ROOT/nx.json" ]; then
        _type="monorepo"
    fi
    # Check for apps/ or packages/ directories
    if [ -d "$PROJECT_ROOT/apps" ] && [ -d "$PROJECT_ROOT/packages" ]; then
        _type="monorepo"
    fi

    # Services (from docker-compose or apps/)
    _services=""
    if [ "$_type" = "monorepo" ] && [ -d "$PROJECT_ROOT/apps" ]; then
        for _dir in "$PROJECT_ROOT/apps"/*/; do
            if [ -d "$_dir" ]; then
                _name=$(basename "$_dir")
                _services="${_services}\"${_name}\","
            fi
        done
    fi
    # Also check docker-compose for services
    _compose_file=""
    for _cf in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        if [ -f "$PROJECT_ROOT/$_cf" ]; then
            _compose_file="$PROJECT_ROOT/$_cf"
            break
        fi
    done
    if [ -n "$_compose_file" ] && [ -z "$_services" ]; then
        # Extract service names (lines that start with exactly 2 spaces followed by word and colon under services:)
        _in_services=false
        while IFS= read -r line; do
            case "$line" in
                "services:"*) _in_services=true ;;
                [a-z]*:*) _in_services=false ;;
            esac
            if [ "$_in_services" = true ]; then
                _svc=$(printf '%s' "$line" | grep -E '^  [a-zA-Z]' | sed 's/:.*//' | tr -d ' ')
                if [ -n "$_svc" ] && [ "$_svc" != "services" ]; then
                    _services="${_services}\"${_svc}\","
                fi
            fi
        done < "$_compose_file"
    fi
    _services=$(printf '%s' "$_services" | sed 's/,$//')

    # Top-level directories
    _top_dirs=""
    for _dir in "$PROJECT_ROOT"/*/; do
        if [ -d "$_dir" ]; then
            _name=$(basename "$_dir")
            case "$_name" in
                node_modules|.git|.next|.nuxt|dist|build|__pycache__|.venv|vendor|target|.terraform|.claude)
                    continue ;;
            esac
            _top_dirs="${_top_dirs}\"${_name}\","
        fi
    done
    _top_dirs=$(printf '%s' "$_top_dirs" | sed 's/,$//')

    # File count estimate (fast, skip ignored dirs)
    _file_count=$(find "$PROJECT_ROOT" -maxdepth 4 -type f \
        -not -path '*/node_modules/*' \
        -not -path '*/.git/*' \
        -not -path '*/dist/*' \
        -not -path '*/build/*' \
        -not -path '*/.next/*' \
        -not -path '*/__pycache__/*' \
        -not -path '*/vendor/*' \
        -not -path '*/target/*' \
        2>/dev/null | wc -l | tr -d ' ')

    SHAPE_JSON=$(cat <<EOF
{
    "type": "${_type}",
    "services": [${_services}],
    "top_level_dirs": [${_top_dirs}],
    "estimated_file_count": ${_file_count}
}
EOF
)
    log_verbose "Shape: type=$_type files=$_file_count"
}

# ── AI Indicator Detection ───────────────────────────────────────────────────

detect_ai_indicators() {
    log_step "Detecting AI indicators..."

    _has_agents=false
    [ -d "$PROJECT_ROOT/agents" ] || [ -d "$PROJECT_ROOT/agent" ] && _has_agents=true

    _has_mcp=false
    [ -f "$PROJECT_ROOT/.mcp.json" ] || [ -f "$PROJECT_ROOT/mcp.json" ] || [ -d "$PROJECT_ROOT/mcp" ] && _has_mcp=true
    [ -f "$PROJECT_ROOT/.claude/settings.json" ] && grep -q 'mcpServers' "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null && _has_mcp=true

    _ai_sdk=""
    if [ -f "$PROJECT_ROOT/package.json" ]; then
        _pkg=$(cat "$PROJECT_ROOT/package.json")
        printf '%s' "$_pkg" | grep -q '"ai"' && _ai_sdk="${_ai_sdk}\"ai-sdk\","
        printf '%s' "$_pkg" | grep -q '"@ai-sdk/' && _ai_sdk="${_ai_sdk}\"ai-sdk\","
        printf '%s' "$_pkg" | grep -q '"openai"' && _ai_sdk="${_ai_sdk}\"openai\","
        printf '%s' "$_pkg" | grep -q '"@anthropic-ai/sdk"' && _ai_sdk="${_ai_sdk}\"anthropic\","
        printf '%s' "$_pkg" | grep -q '"langchain"' && _ai_sdk="${_ai_sdk}\"langchain\","
    fi
    if [ -f "$PROJECT_ROOT/requirements.txt" ]; then
        grep -qi 'openai' "$PROJECT_ROOT/requirements.txt" 2>/dev/null && _ai_sdk="${_ai_sdk}\"openai\","
        grep -qi 'anthropic' "$PROJECT_ROOT/requirements.txt" 2>/dev/null && _ai_sdk="${_ai_sdk}\"anthropic\","
        grep -qi 'langchain' "$PROJECT_ROOT/requirements.txt" 2>/dev/null && _ai_sdk="${_ai_sdk}\"langchain\","
    fi
    # Deduplicate
    _ai_sdk=$(printf '%s' "$_ai_sdk" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')

    _has_claude_md=false
    [ -f "$PROJECT_ROOT/CLAUDE.md" ] && _has_claude_md=true

    AI_JSON=$(cat <<EOF
{
    "has_agents": ${_has_agents},
    "has_mcp": ${_has_mcp},
    "ai_sdk": [${_ai_sdk}],
    "has_existing_claude_md": ${_has_claude_md}
}
EOF
)
    log_verbose "AI: agents=$_has_agents mcp=$_has_mcp claude_md=$_has_claude_md"
}

# ── Collaboration Detection ──────────────────────────────────────────────────

detect_collaboration() {
    log_step "Detecting collaboration signals..."

    _team_size="unknown"
    _contributor_count=0

    # Try git contributor count (last 6 months)
    if command -v git >/dev/null 2>&1 && [ -d "$PROJECT_ROOT/.git" ]; then
        _contributor_count=$(git -C "$PROJECT_ROOT" log --since="6 months ago" --format='%ae' 2>/dev/null | sort -u | wc -l | tr -d ' ')
        if [ "$_contributor_count" -eq 1 ]; then
            _team_size="1"
        elif [ "$_contributor_count" -le 5 ]; then
            _team_size="2-5"
        elif [ "$_contributor_count" -gt 5 ]; then
            _team_size="5+"
        fi
    fi

    _has_codeowners=false
    [ -f "$PROJECT_ROOT/CODEOWNERS" ] || [ -f "$PROJECT_ROOT/.github/CODEOWNERS" ] || [ -f "$PROJECT_ROOT/docs/CODEOWNERS" ] && _has_codeowners=true

    _has_pr_template=false
    [ -f "$PROJECT_ROOT/.github/pull_request_template.md" ] || [ -d "$PROJECT_ROOT/.github/PULL_REQUEST_TEMPLATE" ] && _has_pr_template=true

    COLLAB_JSON=$(cat <<EOF
{
    "team_size": "${_team_size}",
    "has_codeowners": ${_has_codeowners},
    "has_pr_template": ${_has_pr_template},
    "contributor_count": ${_contributor_count}
}
EOF
)
    log_verbose "Collaboration: team=$_team_size contributors=$_contributor_count"
}

# ── Convention Detection ─────────────────────────────────────────────────────

detect_conventions() {
    log_step "Detecting conventions..."

    _has_eslint=false
    [ -f "$PROJECT_ROOT/.eslintrc.json" ] || [ -f "$PROJECT_ROOT/.eslintrc.js" ] || [ -f "$PROJECT_ROOT/.eslintrc.cjs" ] || [ -f "$PROJECT_ROOT/eslint.config.js" ] || [ -f "$PROJECT_ROOT/eslint.config.mjs" ] || [ -f "$PROJECT_ROOT/eslint.config.ts" ] && _has_eslint=true

    _has_prettier=false
    [ -f "$PROJECT_ROOT/.prettierrc" ] || [ -f "$PROJECT_ROOT/.prettierrc.json" ] || [ -f "$PROJECT_ROOT/.prettierrc.js" ] || [ -f "$PROJECT_ROOT/.prettierrc.cjs" ] || [ -f "$PROJECT_ROOT/prettier.config.js" ] || [ -f "$PROJECT_ROOT/prettier.config.mjs" ] && _has_prettier=true

    _has_editorconfig=false
    [ -f "$PROJECT_ROOT/.editorconfig" ] && _has_editorconfig=true

    _ts_strict=false
    if [ -f "$PROJECT_ROOT/tsconfig.json" ]; then
        grep -q '"strict"' "$PROJECT_ROOT/tsconfig.json" 2>/dev/null && \
        grep -q '"strict"\s*:\s*true' "$PROJECT_ROOT/tsconfig.json" 2>/dev/null && _ts_strict=true
    fi

    # Detect test file pattern
    _test_pattern="null"
    if find "$PROJECT_ROOT" -maxdepth 3 -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.js' 2>/dev/null | head -1 | grep -q '.'; then
        _test_pattern="\"*.test.{ts,tsx,js}\""
    elif find "$PROJECT_ROOT" -maxdepth 3 -name '*.spec.ts' -o -name '*.spec.tsx' -o -name '*.spec.js' 2>/dev/null | head -1 | grep -q '.'; then
        _test_pattern="\"*.spec.{ts,tsx,js}\""
    elif find "$PROJECT_ROOT" -maxdepth 3 -name '*_test.go' 2>/dev/null | head -1 | grep -q '.'; then
        _test_pattern="\"*_test.go\""
    elif find "$PROJECT_ROOT" -maxdepth 3 -name 'test_*.py' 2>/dev/null | head -1 | grep -q '.'; then
        _test_pattern="\"test_*.py\""
    fi

    CONV_JSON=$(cat <<EOF
{
    "has_eslint": ${_has_eslint},
    "has_prettier": ${_has_prettier},
    "has_editorconfig": ${_has_editorconfig},
    "typescript_strict": ${_ts_strict},
    "test_pattern": ${_test_pattern}
}
EOF
)
    log_verbose "Conventions: eslint=$_has_eslint prettier=$_has_prettier ts_strict=$_ts_strict"
}

# ── Interactive Questions ────────────────────────────────────────────────────

ask_questions() {
    log_step "Checking if additional questions needed..."

    USER_ANSWERS="{}"

    # Q1: Autonomous agents — only if tools/ dir exists but no agents detected
    if [ -d "$PROJECT_ROOT/tools" ] && [ "$_has_agents" = false ]; then
        _answer=$(ask "Do you have AI agents running autonomously? (yes/no)" "no")
        USER_ANSWERS=$(printf '%s' "$USER_ANSWERS" | jq --arg v "$_answer" '. + {autonomous_agents: $v}')
    fi

    # Q2: Team size — only if git history unavailable
    if [ "$_team_size" = "unknown" ]; then
        _answer=$(ask "How many people work on this project? (1/2-5/5+)" "1")
        USER_ANSWERS=$(printf '%s' "$USER_ANSWERS" | jq --arg v "$_answer" '. + {team_size: $v}')
        _team_size="$_answer"
    fi

    # Q3: Side effects — only if agents exist but no deployment/database
    if [ "$_has_agents" = true ] && [ "$_deployment" = "null" ] && [ "$_database" = "null" ]; then
        _answer=$(ask "Does the agent have real side effects? (file writes, API calls, etc.) (yes/no)" "yes")
        USER_ANSWERS=$(printf '%s' "$USER_ANSWERS" | jq --arg v "$_answer" '. + {has_side_effects: $v}')
    fi
}

# ── Assembly ─────────────────────────────────────────────────────────────────

assemble_context() {
    log_step "Assembling project context..."

    _project_name=$(basename "$PROJECT_ROOT")
    _timestamp=$(iso_timestamp)

    ensure_dir "$HARNESS_DIR"

    # Build the full context JSON
    cat > "$CONTEXT_FILE" <<CTXEOF
{
    "version": "2.0",
    "generated_at": "${_timestamp}",
    "project": {
        "root": "${PROJECT_ROOT}",
        "name": "${_project_name}"
    },
    "stack": ${STACK_JSON},
    "infrastructure": ${INFRA_JSON},
    "shape": ${SHAPE_JSON},
    "ai_indicators": ${AI_JSON},
    "collaboration": ${COLLAB_JSON},
    "conventions": ${CONV_JSON},
    "user_answers": ${USER_ANSWERS},
    "hash": ""
}
CTXEOF

    # Compute and set hash
    _hash=$(hash_context "$CONTEXT_FILE")
    json_set "$CONTEXT_FILE" '.hash' "\"sha256:${_hash}\""

    # Pretty-print
    _tmp=$(mktemp)
    jq '.' "$CONTEXT_FILE" > "$_tmp" && mv "$_tmp" "$CONTEXT_FILE"

    log_verbose "Context written to $CONTEXT_FILE"
    log_verbose "Hash: sha256:${_hash}"
}

# ── Main ─────────────────────────────────────────────────────────────────────

run_discover() {
    log_info "Discovering project..."

    detect_stack
    detect_infrastructure
    detect_shape
    detect_ai_indicators
    detect_collaboration
    detect_conventions

    if [ "$FLAG_SKIP_QUESTIONS" != true ]; then
        ask_questions
    else
        USER_ANSWERS="{}"
    fi

    assemble_context

    # Summary
    _lang_count=$(printf '%s' "$STACK_JSON" | jq '.languages | length')
    _fw_count=$(printf '%s' "$STACK_JSON" | jq '.frameworks | length')
    log_step "Detected: ${_lang_count} language(s), ${_fw_count} framework(s)"

    _pkg_mgr=$(printf '%s' "$STACK_JSON" | jq -r '.package_manager // "none"')
    [ "$_pkg_mgr" != "null" ] && [ "$_pkg_mgr" != "none" ] && log_step "Package manager: $_pkg_mgr"

    _deploy=$(printf '%s' "$INFRA_JSON" | jq -r '.deployment // "none"')
    [ "$_deploy" != "null" ] && [ "$_deploy" != "none" ] && log_step "Deployment: $_deploy"

    _shape_type=$(printf '%s' "$SHAPE_JSON" | jq -r '.type')
    log_step "Project type: $_shape_type"
}
