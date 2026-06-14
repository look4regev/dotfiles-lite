Dotfiles

## Company macOS setup (Apple Silicon)

Run on a fresh MacBook (M-series chip):

```sh
./setup.sh
```

The script is idempotent — re-run it any time, already-installed items are skipped.

It installs/configures:

- Xcode Command Line Tools
- Homebrew
- Packages via `Brewfile`: git, gh, python, openssl@3, node, go, diff-so-fancy,
  zsh-autosuggestions, jq
- Casks via `Brewfile`: iterm2, maccy, flutter, gcloud-cli
- oh-my-zsh + zsh-autosuggestions wired into `~/.zshrc`
- diff-so-fancy as the default git pager
- macOS firewall (enabled)
- Screen lock after 10 minutes idle, password required immediately on wake
- Git identity (`user.name`, `user.email`, `init.defaultBranch=main`)
- A new `ed25519` SSH key (`~/.ssh/id_ed25519`) for GitHub, with instructions
  to add the public key to your GitHub account

If Xcode Command Line Tools aren't installed yet, the script triggers the
install popup and exits — re-run it once that finishes.
