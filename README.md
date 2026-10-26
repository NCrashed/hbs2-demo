# hbs2-hub demo

[hbs2-hub](https://github.com/NCrashed/hbs2/blob/master/docs/hbs2-hub.md)
gives a git repository issues and pull requests without a server. The
issues and pull requests are stored inside the repository itself, and
contributors reach the project through an encrypted mailbox instead of
an account somewhere.

This repository is one script, `demo.sh`. It runs the whole thing on
your machine in about a minute and a half: an owner publishes a
project, a contributor reports a bug and sends a fix, the owner merges
it and makes the contributor a maintainer.

If you only want to read, [`transcript.txt`](transcript.txt) is the
output of a real run.

## Run it

You need the hbs2 tools on your `PATH`: `hbs2-peer`, `hbs2-cli`,
`hbs2-keyman`, `hbs2-git3`, `git-remote-hbs23` and `hbs2-hub`
([how to install](https://github.com/NCrashed/hbs2/blob/master/INSTALL.md)).
The demo needs hbs2 0.26.0.0 or newer; the transcript is from 0.26.0.0.

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
3. The owner runs `hbs2-hub identity init` and `hbs2-hub project open`:
   the project now has a mailbox anyone may write to, written into the
   repository.
4. The contributor clones the project and runs `hbs2-hub identity init`.
5. The contributor files an issue, with only a title and a body.
6. The owner reads the mailbox.
7. The owner accepts the issue and publishes.
8. The contributor sees issue #1, and the owner's reply in their own
   mailbox.
9. The contributor fixes the typo on a branch and sends a pull request,
   with only a title.
10. The owner checks out the proposal, reviews the diff, merges it with
    plain git, records the merge and closes the issue.
11. The owner makes the contributor a maintainer, by the number of the
    issue they opened.
12. The contributor sees #2 merged, #1 closed and the fixed code, and
    starts signing as a maintainer.

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

Inside a clone, `hbs2-hub` fills in the project key from the
`hbs23://` remote and your author key and sigil from
`hbs2-hub identity init`. It says on stderr what it filled in.

### "I want to report a bug in a project"

Once, on your machine:

```
hbs2-hub identity init
```

Then:

```
git clone hbs23://<repo-key> project
cd project
echo "What happened, and how to reproduce it." |
  hbs2-hub issue new --title "Short summary" --body -
```

It takes a moment: your machine does a little proof-of-work (well under
a second on a recent laptop) so that flooding a project's mailbox
costs something.

### "I want to send a fix"

Commit on a branch in your clone, then:

```
hbs2-hub pr new --title "Fix the thing"
```

Only your new commits travel, as a git bundle inside the letter.

### "I want to know what happened to my issue or pull request"

```
hbs2-hub updates
hbs2-hub sync
hbs2-hub issue list
hbs2-hub issue show 1
```

`updates` reads the owner's replies in your own mailbox. The rest read
the repository and need no network once synced.

### "I maintain a project and want contributions"

Once, in your clone:

```
hbs2-hub identity init
hbs2-hub project open
hbs2-hub publish
```

Then tell people the repo key.

### "Somebody sent something; I want to deal with it"

```
hbs2-hub inbox                       # what is waiting
hbs2-hub inbox --follow              # keep running, print letters as they arrive
hbs2-hub inbox show --message <id>
hbs2-hub inbox accept --message <id> # take it
hbs2-hub inbox reject --message <id> # or turn it down
hbs2-hub publish
```

### "I want to review and merge a pull request"

```
hbs2-hub pr checkout --number 2 --branch review
git diff master review
git checkout master && git merge --no-ff review && git push origin master
hbs2-hub pr merge --number 2 --commit <merge-commit> --into refs/heads/master
hbs2-hub issue close --number 1 --note "Fixed by #2."
hbs2-hub publish
```

The merge itself is ordinary git. `pr merge` only records it, and
refuses if the commit does not actually contain the proposal.

### "I want help maintaining it"

```
hbs2-hub maintainer add --author-of 1    # whoever opened #1
hbs2-hub publish
```

The new maintainer, in their clone after `hbs2-hub sync`:

```
hbs2-hub maintainer use
```

### "I want to check that nobody forged anything"

```
hbs2-hub verify
```

Rechecks every signature and rule over the whole record. Needs no
network and no keys.

## Rough edges

True as of hbs2 0.26.0.0:

- `git push -q` to an `hbs23://` remote still prints progress lines
  when its output is captured; on a terminal it is one line redrawn.
- Raising a project's proof-of-work price takes a while to reach
  contributors' peers. Until it does, their letters are sent with too
  little work and dropped without a word.
- There is no web interface yet. Everything is the command line.

## More

- [Getting started with hbs2-hub](https://github.com/NCrashed/hbs2/blob/master/docs/hub-quickstart.md)
- [The full hbs2-hub guide](https://github.com/NCrashed/hbs2/blob/master/docs/hbs2-hub.md)
- `hbs2-hub --help`, `hbs2-hub help <verb>`
