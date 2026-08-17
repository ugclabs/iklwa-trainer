# Iklwa Terminal Trainer

A terminal trainer for Ubuntu Guard interns. No slideshow, no video — you learn Linux and the early stages of fieldwork by typing real commands against a sandbox built for you, working through simulated Ubuntu Guard cases.

## Quick start

```
git clone <this repo's URL>
cd iklwa-trainer
chmod +x iklwa-trainer.sh
./iklwa-trainer.sh
```

That's it. The script asks for your name, then drops you into stage 1 (or wherever you left off, if you've run it before on this machine).

## What's in this repo

```
iklwa-trainer.sh                       the trainer itself
iklwa-trainer-selftest.sh              regression test, run after any edit to the trainer
docs/
  iklwa-trainer-intern-guide.md        full instructions for interns — read this first
infra/
  iklwa-stage4-network-setup.sh        one-time DNS setup for stage 4, runs itself automatically
  iklwa-stage4-network-setup-guide.md  how the stage 4 lab network is built and wired in
  iklwa-lab-dnsmasq.conf.example       DNS zone config for the lab machine
  iklwa-lab-http.service.example       systemd unit for the lab machine's port-scan target
.github/workflows/check.yml            CI: syntax-checks the trainer and runs the selftest on every push
```

If you're an intern: start with `docs/iklwa-trainer-intern-guide.md`, not this file. It covers what each stage is, how progress and hints work, and what to do if something goes wrong.

If you're setting up the stage 4 lab network for the first time: start with `infra/iklwa-stage4-network-setup-guide.md`.

## Stages

Four stages so far. Stage 1 through 3 need nothing but the sandbox — no network, no setup. Stage 4 is recon day, and it's the first stage that reaches out to a real (lab-controlled) network.

Stage 1 through 3: moving around, working with files, a full case, a solo case with a written tasking and a graded submission.

Stage 4: DNS lookups, reachability checks, and a port scan against Ubuntu Guard's own lab domain — a client engagement seen from outside, before anything gets touched directly.

## About stage 4 and sudo

Stage 4 needs this machine's DNS resolver pointed at the lab network. The trainer handles that itself, automatically, the first time you reach stage 4 on a machine that isn't set up yet — you'll get a `sudo` password prompt right there in the middle of the run. This is the only time the trainer ever asks for elevated permissions, and it's a deliberate, narrow exception: everything else it does stays inside your own sandbox folder. See `docs/iklwa-trainer-intern-guide.md` for what to expect, and `infra/iklwa-stage4-network-setup-guide.md` for what the setup script actually changes.

## Scope

Every scan, lookup, and (in later stages) crack in this trainer runs against something Ubuntu Guard built specifically for training — a lab domain, a lab VM, never a real client or third party. That's not incidental. The same commands this trains you on are the same commands used on real engagements, and the only thing that separates the two is written permission. Break it here, not out there.

## Progress

Progress is tracked per name, on the machine you're running on — it's stored in your home folder, outside this cloned repo, so it isn't something git tracks or syncs. If you clone this repo onto a second machine, you start fresh there; typing the same name back into the trainer on your original machine picks up exactly where you left off.

## Command reference

```
./iklwa-trainer.sh                 start, or resume where you left off
./iklwa-trainer.sh --stage 2       jump straight to a stage (1-4)
./iklwa-trainer.sh --reset         wipe your own progress, keep your sandbox
./iklwa-trainer.sh --reset all     wipe progress and sandbox, start over completely
./iklwa-trainer.sh --selfcheck     check your machine has what the trainer needs
./iklwa-trainer.sh --help          print this list
```

## Questions

If something in the trainer itself looks wrong, or a lesson isn't accepting a command that should be correct, check the troubleshooting section at the end of `docs/iklwa-trainer-intern-guide.md` first. If that doesn't cover it, flag it to your supervisor with exactly what you typed and what appeared on screen.
