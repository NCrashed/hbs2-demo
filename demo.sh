#!/usr/bin/env bash
# hbs2-hub, end to end, on your own machine.
#
# Two people, two hbs2 peers, one project: the owner publishes a repository
# and opens it to contributions, a contributor clones it, files an issue and
# sends a fix, and the owner takes both into the project's record.
#
# Nothing here touches your real setup. Each person gets a temporary HOME with
# its own keys, peer config and storage; both peers listen on 127.0.0.1 only,
# with multicast and bootstrap off, so they talk to each other and to nobody
# else. Everything is deleted at the end (KEEP=1 keeps it).
#
# Usage:
#   ./demo.sh                 hbs2 tools on PATH
#   BIN=/path/to/bin ./demo.sh
#
# Needs: hbs2-peer hbs2-cli hbs2-keyman hbs2-git3 git-remote-hbs23 hbs2-hub, git.
# PAUSE=1 waits for Enter between steps.

set -euo pipefail

[ -n "${BIN:-}" ] && export PATH="$BIN:$PATH"
for t in hbs2-peer hbs2-cli hbs2-keyman hbs2-git3 git-remote-hbs23 hbs2-hub git; do
  command -v "$t" >/dev/null || { echo "missing: $t (put the hbs2 tools on PATH or set BIN)" >&2; exit 1; }
done

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/hbs2-hub-demo.XXXXXX")
PIDS=()

cleanup() {
  for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null || true; done
  for p in "${PIDS[@]:-}"; do [ -n "$p" ] && wait "$p" 2>/dev/null || true; done
  if [ "${KEEP:-}" = 1 ]; then echo "kept $ROOT"; else rm -rf "$ROOT"; fi
}
trap cleanup EXIT

# --- narration ---------------------------------------------------------------

if [ -t 1 ]; then B=$'\e[1m'; D=$'\e[2m'; C=$'\e[36m'; R=$'\e[0m'; else B= D= C= R=; fi

N=0
step() {
  N=$((N+1))
  [ "${PAUSE:-}" = 1 ] && [ "$N" -gt 1 ] && { read -rp "${D}-- Enter for the next step --${R}" _ </dev/null || true; }
  printf '\n%s== %d. %s ==%s\n' "$B" "$N" "$*" "$R"
}
note() { printf '%s%s%s\n' "$D" "$*" "$R"; }
die()  { echo "demo failed: $*" >&2; [ -n "${WHO:-}" ] && tail -20 "$ROOT/$WHO/peer.log" >&2; exit 1; }

# --- the two people ------------------------------------------------------------

# Everything a command needs to run as one of them.
env_of() {
  local who=$1 h="$ROOT/$1/home"
  export HOME="$h"
  export XDG_CONFIG_HOME="$h/.config" XDG_DATA_HOME="$h/.local/share"
  export XDG_STATE_HOME="$h/.local/state" XDG_CACHE_HOME="$h/.cache"
  export GIT_CONFIG_GLOBAL="$h/.gitconfig" GIT_CONFIG_NOSYSTEM=1
  export HBS2_GIT_REPO_WAIT=60
  unset GIT_DIR GIT_WORK_TREE HBS2TRACE
}

# `as owner` / `as contrib`: whose shell the next commands run in.
WHO=
as() { WHO=$1; printf '\n%s[%s]%s\n' "$C" "$1" "$R"; }

# Print a command the way you would type it, then run it as $WHO, in their
# project directory when they have one. Variables are shown by name.
run() {
  printf '%s$ %s%s\n' "$B" "$1" "$R"
  local rc=0
  ( env_of "$WHO"
    cd "$ROOT/$WHO"; if [ -d project ]; then cd project; fi
    eval "$1" ) >"$ROOT/out" 2>&1 || rc=$?
  # git-remote-hbs23 redraws one status line in place. Show what a terminal
  # would be left showing, not every redraw.
  perl -ne 's/\r/\e[1G/g; my @s = grep { /\S/ } split /\e\[1G/;
            $_ = @s ? $s[-1] : ""; s/\e\[[0-9;]*[A-Za-z]//g; print if /\S/' \
       "$ROOT/out" || true
  [ "$rc" = 0 ] || die "$1 (exit $rc)"
}

# The same, quietly, for a value the script needs.
get() { ( env_of "$WHO"; cd "$ROOT/$WHO"; if [ -d project ]; then cd project; fi; eval "$1" ) 2>/dev/null; }

# Retry a quiet check until it passes: the network takes a moment.
wait_for() {
  local what=$1 cmd=$2 i
  for i in $(seq 1 "${3:-60}"); do get "$cmd" >/dev/null && return 0; sleep 1; done
  die "timed out waiting for $what"
}

start_peer() {
  local who=$1 udp=$2 tcp=$3 known=${4:-}
  mkdir -p "$ROOT/$who/home"
  ( env_of "$who"
    git config --global user.name "$who"
    git config --global user.email "$who@example.invalid"
    git config --global commit.gpgsign false
    git config --global init.defaultBranch master
    hbs2-peer init >/dev/null
    cat > "$XDG_CONFIG_HOME/hbs2-peer/config" <<CONF
listen "127.0.0.1:$udp"
listen-tcp "127.0.0.1:$tcp"
rpc unix "$ROOT/$who/rpc.socket"
http-port "off"
multicast off
bootstrap off
storage "$ROOT/$who/storage"
key "./default.key"
${known:+known-peer \"127.0.0.1:$known\"}
CONF
  )
  ( env_of "$who"; cd "$XDG_CONFIG_HOME/hbs2-peer"; exec hbs2-peer run >>"$ROOT/$who/peer.log" 2>&1 </dev/null ) &
  PIDS+=($!)
  WHO=$who wait_for "the $who peer" "hbs2-peer poke" 30
}

# =============================================================================

step "Two peers on this machine"
note "One for the owner, one for the contributor. They know each other's"
note "address and nothing else."
start_peer owner   17551 17552
start_peer contrib 17561 17562 17551
WHO=contrib wait_for "the peers to connect" "hbs2-peer peers | grep -q 127.0.0.1:17551" 30
as contrib
run 'hbs2-peer peers'

# -----------------------------------------------------------------------------

step "The owner publishes a project"
note "An ordinary git repository, pushed to an hbs23:// remote. The remote's"
note "key is the project's identity from now on."
as owner
mkdir -p "$ROOT/owner/project"
run 'git init -q'
run 'printf "#!/bin/sh\necho \"Helo, \$1\"\n" > greet.sh && cat greet.sh'
run 'git add greet.sh && git commit -qm "greeter: first version"'
run 'hbs2-git3 repo:init --new'
run 'git push -q origin master'
REPO=$(get 'git remote get-url origin'); REPO=${REPO#hbs23://}

# -----------------------------------------------------------------------------

step "The owner opens the project to contributions"
note "Two commands. The first makes the owner an identity: a key, the sigil"
note "that lets people answer them, and a mailbox for those answers. The"
note "second gives the project a mailbox anyone may write to, and writes it"
note "into the repository, so a contributor needs nothing but the repo key."
run 'hbs2-hub identity init'
run 'hbs2-hub project open'
run 'hbs2-hub publish'

# -----------------------------------------------------------------------------

step "A contributor clones it and sets up an identity"
as contrib
note "All they were given is the repo key."
run 'git clone -q hbs23://$REPO project'
run 'hbs2-hub identity init'

# -----------------------------------------------------------------------------

step "The contributor files an issue"
note "No keys on the command line: the project comes from the clone's"
note "remote, the author and sender from identity init."
wait_for "the repository manifest to name its mailbox" 'hbs2-hub whoami --repo $REPO | grep -q "recipient sigil"' 120
run 'echo "greet.sh prints \"Helo\" instead of \"Hello\"." | hbs2-hub issue new --title "Typo in the greeting" --body -'

# -----------------------------------------------------------------------------

step "The owner reads the mailbox"
as owner
wait_for "the letter to arrive" 'hbs2-hub inbox | grep -q Typo' 120
run 'hbs2-hub inbox'
ISSUE_MSG=$(get "hbs2-hub inbox --long | grep 'Typo in the greeting' | cut -d' ' -f1")
run 'hbs2-hub inbox show --message $ISSUE_MSG'

step "The owner accepts the issue"
note "Accepting folds the letter into canon: the project's signed,"
note "append-only record, kept in the repository under refs/hbs2/meta."
run 'hbs2-hub inbox accept --message $ISSUE_MSG'
run 'hbs2-hub issue list'
note "Canon is a git ref, so it is published like one:"
run 'hbs2-hub publish'
CANON=$(get 'git rev-parse refs/hbs2/meta')

# -----------------------------------------------------------------------------

step "The contributor sees the issue, and the owner's reply"
as contrib
wait_for "canon to reach the contributor" 'git ls-remote origin refs/hbs2/meta | grep -q $CANON' 120
run 'hbs2-hub sync'
run 'hbs2-hub issue list'
run 'hbs2-hub issue show 1'
wait_for "the acknowledgement" 'hbs2-hub updates | grep -q .' 120
run 'hbs2-hub updates'

# -----------------------------------------------------------------------------

step "The contributor sends a fix"
note "A pull request is a git bundle of the new commits, sealed into a letter"
note "the same way. Only the delta travels. The branch it goes onto and the"
note "branch it comes from are the clone's own."
run 'git checkout -qb fix-typo && sed -i "s/Helo/Hello/" greet.sh && git commit -qam "greet: fix the typo"'
run 'hbs2-hub pr new --title "Fix the greeting typo" --body "Fixes #1."'

# -----------------------------------------------------------------------------

step "The owner reviews and merges it"
as owner
wait_for "the pull request to arrive" 'hbs2-hub inbox | grep -q "Fix the greeting"' 120
run 'hbs2-hub inbox'
PR_MSG=$(get "hbs2-hub inbox --long | grep 'Fix the greeting' | cut -d' ' -f1")
run 'hbs2-hub inbox accept --message $PR_MSG'
run 'hbs2-hub pr list'
PR=$(get "hbs2-hub pr list | grep 'Fix the greeting' | grep -o '#[0-9]*' | head -1 | tr -d '#'")
note "The proposal is now a local branch to review like any other:"
run 'hbs2-hub pr checkout --number $PR --branch review'
run 'git diff master review'
note "Merging is plain git. Then canon is told what happened, and refuses"
note "to record a merge that does not contain the proposal."
run 'git checkout -q master && git merge -q --no-ff review -m "Merge the greeting fix" && git push -q origin master'
run 'hbs2-hub pr merge --number $PR --commit $(git rev-parse --short HEAD) --into refs/heads/master'
run 'hbs2-hub issue close --number 1 --note "Fixed by #$PR."'

# -----------------------------------------------------------------------------

step "The owner makes the contributor a maintainer"
note "By the number of the issue they opened: no key to copy around."
run 'hbs2-hub maintainer add --author-of 1'
run 'hbs2-hub maintainer list'
run 'hbs2-hub publish'
CANON=$(get 'git rev-parse refs/hbs2/meta')

# -----------------------------------------------------------------------------

step "The contributor sees the result"
as contrib
wait_for "the merge to reach the contributor" 'git ls-remote origin refs/hbs2/meta | grep -q $CANON' 180
run 'hbs2-hub sync'
run 'hbs2-hub pr list'
run 'hbs2-hub issue list'
run 'git checkout -q master && git merge -q --ff-only origin/master && cat greet.sh'
note "Now a maintainer, they tell this clone to sign as their identity:"
run 'hbs2-hub maintainer use'
run 'hbs2-hub log'
run 'hbs2-hub verify'

step "Done"
note "Everything above lives in the repository: any clone can rebuild every"
note "issue and pull request from refs/hbs2/meta, offline, and check every"
note "signature with hbs2-hub verify."
