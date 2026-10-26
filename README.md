# hbs2-hub demo

[hbs2-hub](https://github.com/NCrashed/hbs2/blob/master/docs/hbs2-hub.md)
gives a git repository issues and pull requests without a server. The
issues and pull requests are stored inside the repository itself, and
contributors reach the project through an encrypted mailbox instead of
an account somewhere.

This repository is one script, `demo.sh`. It runs the whole thing on
your machine in about a minute and a half: an owner publishes a
project, a contributor reports a bug and sends a fix, the owner merges
it, and the contributor sees the result.

If you only want to read, [`transcript.txt`](transcript.txt) is the
output of a real run.

## Run it

You need the hbs2 tools on your `PATH`: `hbs2-peer`, `hbs2-cli`,
`hbs2-keyman`, `hbs2-git3`, `git-remote-hbs23` and `hbs2-hub`
([how to install](https://github.com/NCrashed/hbs2/blob/master/INSTALL.md)).
The demo needs hbs2 0.26 or newer; it was last run against hbs2
`60739021` (master, 2026-10-26).

```
./demo.sh
```

```
PAUSE=1 ./demo.sh           # stop after each step, press Enter to go on
KEEP=1 ./demo.sh            # keep the temporary files to look at afterwards
BIN=/path/to/bin ./demo.sh  # tools that are not on PATH
```

It is safe to run next to a real hbs2 setup. Each person gets a fresh
temporary home directory with its own keys, config and storage. The two
peers listen on 127.0.0.1 (ports 17551 and 17561) and talk only to each
other. Everything is deleted when the script ends.

## What you will see

Two people, each with their own hbs2 peer:

- **the owner** has a small project, `greet.sh`, with a typo in it;
- **the contributor** has nothing except the project's key.

The steps:

1. Two peers start and connect.
2. The owner pushes the project to an `hbs23://` remote. The remote's
   key is the project's address from now on.
3. The owner opens the project to contributions: creates a mailbox,
   says who may write to it, and records the mailbox in the repository.
4. The contributor clones the project and makes an identity.
5. The contributor files an issue: "Typo in the greeting".
6. The owner reads the mailbox.
7. The owner accepts the issue and publishes.
8. The contributor sees issue #1 in the project.
9. The contributor fixes the typo on a branch and sends a pull request.
10. The owner checks out the proposal, reviews the diff, merges it with
    plain git, records the merge, closes the issue and publishes.
11. The contributor sees #2 merged, #1 closed, and the fixed code.

## How it works, in five words

**Repo key.** `hbs2-git3 repo:init` makes a key pair for the project.
The public key is the address (`hbs23://<repo-key>`) and owning the
private key is owning the project.

**Mailbox.** Where letters to the project arrive, on the owner's peer.
It has its own key, and a *sigil*: a small public record with the
encryption key people seal their letters to. The repository names both,
so a contributor only ever needs the repo key.

**Letter.** An issue, a comment or a pull request is sent as a signed,
encrypted letter to the mailbox. A letter is a request. Nothing a
stranger sends becomes part of the project by itself.

**Canon.** The project's record of issues and pull requests: a signed,
append-only log in the repository under `refs/hbs2/meta`. The owner
adds a letter to it with `hbs2-hub inbox accept`, or writes to it
directly (`issue close`, `pr merge`, ...).

**Publish.** Canon is a git ref, so it travels like one. Nothing is
public until `hbs2-hub publish`; contributors get it with
`hbs2-hub sync`. Every clone can read every issue offline and check
every signature with `hbs2-hub verify`.

## Use cases

Most commands below are ones the demo runs; `inbox reject` and
`--follow` come from the full guide. `<repo-key>` is the key from
`hbs2-git3 repo:init`.

### "I want to report a bug in a project"

You need the project's repo key and, once, an identity:

```
mkdir -p ~/.hbs2-keyman/keys
hbs2-cli hbs2:keyring:new > ~/.hbs2-keyman/keys/me.key
hbs2-keyman update
hbs2-cli hbs2:keyring:show ~/.hbs2-keyman/keys/me.key   # sign-key: <my-key>
hbs2-cli hbs2:sigil:create:from-keyring ~/.hbs2-keyman/keys/me.key > me.sigil
hbs2-cli hbs2:sigil:store:file me.sigil                 # prints <my-sigil>
hbs2-peer mailbox create --key <my-key> hub
```

Check that the identity is wired correctly and see where your letters
will go:

```
hbs2-hub whoami --author <my-key> --sender <my-sigil> --repo <repo-key>
hbs2-peer fetch <recipient-sigil>     # the sigil whoami printed for the repo
```

Then file it:

```
echo "What happened, and how to reproduce it." |
  hbs2-hub issue new --repo <repo-key> --author <my-key> --sender <my-sigil> \
                     --title "Short summary" --body -
```

It takes a moment: your machine does a little proof-of-work (well under
a second on a recent laptop) so that flooding a project's mailbox
costs something.

### "I want to send a fix"

Commit on a branch in your clone, then:

```
hbs2-hub pr new --repo <repo-key> --author <my-key> --sender <my-sigil> \
                --title "Fix the thing" --onto master --from my-branch
```

Only your new commits travel, as a git bundle inside the letter.

### "I want to know what happened to my issue or pull request"

```
hbs2-hub sync --repo <repo-key>
hbs2-hub issue list <repo-key>
hbs2-hub pr list <repo-key>
hbs2-hub issue show <repo-key> 1
```

These read the repository and need no network once synced.

### "I maintain a project and want contributions"

Once:

```
mkdir -p ~/.hbs2-keyman/keys
hbs2-cli hbs2:keyring:new > ~/.hbs2-keyman/keys/mailbox.key
hbs2-keyman update
hbs2-peer mailbox create --key <mailbox-key> hub
hbs2-hub policy default --mailbox <mailbox-key> --sender allow --peer allow
hbs2-cli hbs2:sigil:create:from-keyring ~/.hbs2-keyman/keys/mailbox.key > mailbox.sigil
hbs2-cli hbs2:sigil:store:file mailbox.sigil            # prints <mailbox-sigil>
hbs2-git3 repo:mailbox:set   <repo-key> --key <mailbox-key>
hbs2-git3 repo:mailbox:sigil <repo-key> --key <mailbox-key> --sigil <mailbox-sigil>
```

Then tell people the repo key. `hbs2-hub status --repo <repo-key>`
shows what they will find.

### "Somebody sent something; I want to deal with it"

```
hbs2-hub inbox --repo <repo-key>                    # what is waiting
hbs2-hub inbox --repo <repo-key> --long             # full ids
hbs2-hub inbox show --mailbox <mailbox-key> --repo <repo-key> --message <id>
hbs2-hub inbox accept --repo <repo-key> --message <id>   # take it
hbs2-hub inbox reject --repo <repo-key> --mailbox <mailbox-key> --message <id>
hbs2-hub publish
```

`hbs2-hub inbox --repo <repo-key> --follow` keeps running and prints
letters as they arrive.

### "I want to review and merge a pull request"

```
hbs2-hub pr checkout --repo <repo-key> --number 2 --branch review
git diff master review
git checkout master && git merge --no-ff review && git push origin master
hbs2-hub pr merge --repo <repo-key> --number 2 --commit <merge-commit> --into refs/heads/master
hbs2-hub issue close --repo <repo-key> --number 1 --note "Fixed by #2."
hbs2-hub publish
```

The merge itself is ordinary git. `pr merge` only records it, and
refuses if the commit does not actually contain the proposal.

### "I want to check that nobody forged anything"

```
hbs2-hub verify <repo-key>
```

Rechecks every signature and rule over the whole record. Needs no
network and no keys.

## Rough edges

Things you will notice in the transcript, true as of hbs2 `60739021`:

- A contributor has to `hbs2-peer fetch` the project's sigil before
  the first letter; `hbs2-hub issue new` does not fetch it.
- `hbs2-git3 repo:init --new` names the remote with two random words;
  the demo renames it to `origin`.
- The owner cannot send acknowledgements ("no acknowledgement: no
  encryption key ...") for a repository made with `repo:init`, so
  `hbs2-hub updates` stays empty. Contributors follow progress by
  reading the record with `hbs2-hub sync`, as the demo does.
- `hbs2-hub policy default` prints its policy with `\u{0a}` where line
  breaks should be.
- There is no web interface yet. Everything is the command line.

## More

- [Getting started with hbs2-hub](https://github.com/NCrashed/hbs2/blob/master/docs/hub-quickstart.md)
- [The full hbs2-hub guide](https://github.com/NCrashed/hbs2/blob/master/docs/hbs2-hub.md)
- `hbs2-hub --help`, `hbs2-hub help <verb>`
