#!/usr/bin/env bash
# _scripts/cli-registry.sh — the single declarative source of truth for the
# ecosystem CLIs managed by the npm/uv/go channels.
#
# Sourced (never executed): common.sh must be sourced first so eco_cli is
# defined. Every row carries its owning channel, so the framework can route a
# bin to the one channel that owns it — and no channel ever has to recognize
# another ecosystem's tools.
#
#   eco_cli <channel> <bin> <pkg> <flag|""> --always|--prompt
#
# Declaration order within a channel is execution order; --always rows must
# precede --prompt rows *within their channel* so baseline installs land
# before any question.

# ── npm channel ───────────────────────────────────────────────────
eco_cli npm biome     @biomejs/biome                   ""                          --always
eco_cli npm stylua    @johnnymorganz/stylua-bin        ""                          --always
eco_cli npm pi        @earendil-works/pi-coding-agent  --ignore-scripts            --prompt
eco_cli npm codex     @openai/codex                    ""                          --prompt
eco_cli npm opencode  opencode-ai                      --allow-scripts=opencode-ai --prompt
eco_cli npm mimo      @mimo-ai/cli                     --allow-scripts=@mimo-ai/cli --prompt
eco_cli npm codegraph @colbymchenry/codegraph          ""                          --prompt
eco_cli npm wrangler  wrangler                         --allow-scripts=esbuild,workerd --prompt
eco_cli npm rea       rea-agents                       ""                          --prompt
eco_cli npm ocr       @alibaba-group/open-code-review  --allow-scripts=@alibaba-group/open-code-review --prompt

# ── uv channel ────────────────────────────────────────────────────
eco_cli uv ruff    ruff    ""  --always
eco_cli uv yt-dlp  yt-dlp  ""  --always

# ── go channel ────────────────────────────────────────────────────
eco_cli go gopls    golang.org/x/tools/gopls  ""  --always
eco_cli go gofumpt  mvdan.cc/gofumpt          ""  --always
