# Where your Foyer Drop server is, for the tools that copy files to it (sourced, not run).
# Set it once with FOYER_DROP_SSH=user@host, or it's asked for and kept in ~/.foyer-drop-ssh
# (on your computer, never in the repo).
# DROP_SSH_ASK=0 skips asking (then DROP_SSH is empty when it isn't set).
DROP_SSH="${FOYER_DROP_SSH:-$(cat "$HOME/.foyer-drop-ssh" 2>/dev/null)}"
if [ -z "$DROP_SSH" ] && [ "${DROP_SSH_ASK:-1}" = "1" ]; then
  read -r -p "Your Foyer Drop server's SSH address (like me@192.168.1.20): " DROP_SSH
  [ -n "$DROP_SSH" ] && printf %s "$DROP_SSH" > "$HOME/.foyer-drop-ssh" && echo "Saved in ~/.foyer-drop-ssh"
fi
