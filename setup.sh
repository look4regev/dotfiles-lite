#!/usr/bin/env bash
#
# Company macOS setup (Apple Silicon only, e.g. MacBook with M-series chip).
# Safe to re-run: every step skips cleanly if already done.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33mwarning: %s\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script only supports macOS." >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  warn "Non-Apple Silicon Mac detected. This script only targets arm64 (M-series). Continuing anyway, but some steps may need adjustment."
fi

# ---------------------------------------------------------------------------
# 1. Xcode Command Line Tools
# ---------------------------------------------------------------------------
log "Checking Xcode Command Line Tools"
if xcode-select -p &>/dev/null; then
  echo "Xcode Command Line Tools already installed."
else
  echo "Triggering Xcode Command Line Tools install (a GUI dialog will appear)..."
  xcode-select --install || true
  echo "Please complete the install in the popup window, then re-run this script."
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Homebrew
# ---------------------------------------------------------------------------
log "Checking Homebrew"
if command -v brew &>/dev/null; then
  echo "Homebrew already installed."
else
  echo "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

BREW_SHELLENV='eval "$(/opt/homebrew/bin/brew shellenv)"'
if ! grep -qF "$BREW_SHELLENV" "$HOME/.zprofile" 2>/dev/null; then
  echo "$BREW_SHELLENV" >> "$HOME/.zprofile"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

# ---------------------------------------------------------------------------
# 3. Brew packages and casks
# ---------------------------------------------------------------------------
log "Installing formulae and casks via Brewfile"
brew bundle --file="$SCRIPT_DIR/Brewfile"

# ---------------------------------------------------------------------------
# 4. oh-my-zsh
# ---------------------------------------------------------------------------
log "Checking oh-my-zsh"
if [[ -d "$HOME/.oh-my-zsh" ]]; then
  echo "oh-my-zsh already installed."
else
  echo "Installing oh-my-zsh..."
  KEEP_ZSHRC=yes RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# ---------------------------------------------------------------------------
# 5. zsh-autosuggestions (brew-installed, sourced from .zshrc)
# ---------------------------------------------------------------------------
log "Configuring zsh-autosuggestions"
AUTOSUGGEST_LINE='source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh'
if grep -qF "zsh-autosuggestions.zsh" "$HOME/.zshrc" 2>/dev/null; then
  echo "zsh-autosuggestions already configured in .zshrc."
else
  {
    echo ""
    echo "# zsh-autosuggestions (installed via Homebrew)"
    echo "$AUTOSUGGEST_LINE"
  } >> "$HOME/.zshrc"
  echo "Added zsh-autosuggestions to .zshrc."
fi

# ---------------------------------------------------------------------------
# 6. diff-so-fancy git integration
# ---------------------------------------------------------------------------
log "Configuring diff-so-fancy for git"
git config --global core.pager "diff-so-fancy | less --tabs=4 -RFX"
git config --global interactive.diffFilter "diff-so-fancy --patch"

# ---------------------------------------------------------------------------
# 7. macOS firewall
# ---------------------------------------------------------------------------
log "Checking macOS firewall"
FW_STATE="$(sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate || true)"
if [[ "$FW_STATE" == *enabled* ]]; then
  echo "Firewall already enabled."
else
  echo "Enabling macOS firewall..."
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
fi

# ---------------------------------------------------------------------------
# 8. Auto-lock after idle time
# ---------------------------------------------------------------------------
log "Configuring screen lock after idle time"
IDLE_SECONDS=600 # 10 minutes
defaults -currentHost write com.apple.screensaver idleTime -int "$IDLE_SECONDS"
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0
killall cfprefsd &>/dev/null || true
echo "Screen saver idle time set to ${IDLE_SECONDS}s, password required immediately on wake."

# ---------------------------------------------------------------------------
# 9. Git identity
# ---------------------------------------------------------------------------
log "Configuring git identity"
CURRENT_NAME="$(git config --global user.name || true)"
CURRENT_EMAIL="$(git config --global user.email || true)"

if [[ -n "$CURRENT_NAME" && -n "$CURRENT_EMAIL" ]]; then
  echo "Git identity already set: $CURRENT_NAME <$CURRENT_EMAIL>"
else
  read -r -p "Enter your full name for git commits: " GIT_NAME
  read -r -p "Enter your email for git commits / SSH key: " GIT_EMAIL
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
fi

git config --global init.defaultBranch main
git config --global pull.rebase false

# ---------------------------------------------------------------------------
# 10. GitHub SSH key
# ---------------------------------------------------------------------------
log "Setting up GitHub SSH key"
SSH_KEY="$HOME/.ssh/id_ed25519"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ -f "$SSH_KEY" ]]; then
  echo "SSH key already exists at $SSH_KEY, skipping generation."
else
  SSH_EMAIL="${GIT_EMAIL:-}"
  if [[ -z "$SSH_EMAIL" ]]; then
    read -r -p "Enter your email for the SSH key comment: " SSH_EMAIL
  fi
  ssh-keygen -t ed25519 -C "$SSH_EMAIL" -f "$SSH_KEY" -N "" -q
  echo "Generated new SSH key at $SSH_KEY"
fi

SSH_CONFIG="$HOME/.ssh/config"
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"
if ! grep -qF "Host github.com" "$SSH_CONFIG"; then
  {
    echo ""
    echo "Host github.com"
    echo "  AddKeysToAgent yes"
    echo "  UseKeychain yes"
    echo "  IdentityFile $SSH_KEY"
  } >> "$SSH_CONFIG"
fi

eval "$(ssh-agent -s)" &>/dev/null || true
ssh-add --apple-use-keychain "$SSH_KEY" &>/dev/null || true

log "Your SSH public key (add this to GitHub):"
cat "$SSH_KEY.pub"
echo ""
if command -v pbcopy &>/dev/null; then
  pbcopy < "$SSH_KEY.pub"
  echo "(copied to clipboard)"
fi

cat <<'EOF'

To add this key to GitHub:
  1. Go to https://github.com/settings/ssh/new
  2. Title: e.g. your Mac's name
  3. Key type: Authentication Key
  4. Paste the public key printed above (already in your clipboard)
  5. Save

Or, with the GitHub CLI (after `gh auth login`):
  gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(scutil --get ComputerName)"

Then test with:
  ssh -T git@github.com
EOF

log "Setup complete!"
echo "Restart your terminal (or run 'exec zsh') to pick up the new shell config."
