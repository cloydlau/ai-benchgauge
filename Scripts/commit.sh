#!/bin/zsh
# Commits with the model name as author and the human as co-author.
#
# The model is re-detected from the Codex config on every run, so a commit
# always credits the model that actually wrote the code. Each vendor gets its
# own noreply address; anything unrecognised falls back to
# <model>@users.noreply.github.com, which GitHub shows as an unlinked
# contributor because no account owns that address.
#
# Usage:
#   Scripts/commit.sh -m "message"        any git commit argument works
#   Scripts/commit.sh --identity          show who would be credited
#   MODEL_NAME=glm-5.3 Scripts/commit.sh --identity

set -euo pipefail

ROOT=${0:A:h:h}
CONFIG="$HOME/.codex/config.toml"
HUMAN_NAME="Cloyd Lau"
HUMAN_EMAIL="31238760+cloydlau@users.noreply.github.com"

detected_model() {
  [[ -f "$CONFIG" ]] || return 0
  sed -nE 's/^model[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$CONFIG" | head -1
}

# Vendor noreply address for a model name; extend as new models show up.
email_for_model() {
  case "${1:l}" in
    *deepseek*)              print -r -- noreply@deepseek.com ;;
    *glm*|*zhipu*|*zai*)     print -r -- noreply@z.ai ;;
    *qwen*|*tongyi*)         print -r -- noreply@qwen.ai ;;
    *claude*|*anthropic*)    print -r -- noreply@anthropic.com ;;
    *gpt*|*openai*|*codex*|*o1*|*o3*|*o4*) print -r -- noreply@openai.com ;;
    *gemini*|*google*)       print -r -- noreply@google.com ;;
    *grok*|*xai*)            print -r -- noreply@x.ai ;;
    *kimi*|*moonshot*)       print -r -- noreply@kimi.com ;;
    *minimax*)               print -r -- noreply@minimax.io ;;
    *mistral*)               print -r -- noreply@mistral.ai ;;
    *llama*|*meta*)          print -r -- noreply@meta.com ;;
    *cursor*)                print -r -- cursoragent@cursor.com ;;
    *)                       print -r -- "${1:l}@users.noreply.github.com" ;;
  esac
}

model=${MODEL_NAME:-$(detected_model)}
model=${model:-codex}
model_email=$(email_for_model "$model")

if [[ "${1:-}" == "--identity" ]]; then
  printf 'author:      %s <%s>\n' "$model" "$model_email"
  printf 'committer:   %s <%s>\n' "$HUMAN_NAME" "$HUMAN_EMAIL"
  printf 'co-authored: %s <%s>\n' "$HUMAN_NAME" "$HUMAN_EMAIL"
  exit 0
fi

printf 'Committing as: %s <%s> + %s\n' "$model" "$model_email" "$HUMAN_NAME"

git -C "$ROOT" commit \
  --author "$model <$model_email>" \
  --trailer "Co-authored-by: $HUMAN_NAME <$HUMAN_EMAIL>" \
  "$@"
