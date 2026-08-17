# Iklwa Terminal Trainer — stage 4 network setup guide

This is the full instruction set behind stage 4's lab network — what it assumes already exists, how to build that, and how it fits into the trainee's workflow. Stage 4 is built into `iklwa-trainer.sh` now, and as of this revision the trainer runs `infra/iklwa-stage4-network-setup.sh` itself, automatically, the first time a learner reaches stage 4 on a machine that hasn't been pointed at the lab yet — see section 3 and section 4 below for exactly how. You, the supervisor, are still the one who has to build and run the lab machine itself (section 2); nothing can do that step for you.

---

## 1. The shape of the whole thing, before the details

One lab machine, built and run by you, carries all of stage 4's infrastructure — the DNS zone, the reachability targets, and the port-scan target. That machine needs to exist and be running before anything else here matters. Once it is, a trainee's own machine gets pointed at it the first time they reach stage 4, and that happens on its own, inside the same trainer run. After that, stage 4's tasks — dig, ping, nmap — work against real infrastructure the same way stages 1-3 work against a real sandbox folder.

Order of operations, start to finish:

1. Build the lab machine (section 2 below).
2. Edit `infra/iklwa-lab-dnsmasq.conf.example`, rename it, drop it in place, start dnsmasq.
3. Edit the three variables (`LAB_DOMAIN`, `LAB_DOWN_HOST`, `LAB_DNS_IP`) at the top of `iklwa-trainer.sh` and the two matching ones in `infra/iklwa-stage4-network-setup.sh` so all of it agrees with what you just built.
4. That's it. Trainees `git clone` the repo, `chmod +x iklwa-trainer.sh`, and run it — same two commands as every other stage. The first time any of them reaches stage 4 on a given machine, the trainer notices the resolver isn't pointed at the lab yet and runs the setup script itself, asking for a `sudo` password right there. Nothing separate to hand out or walk anyone through.

---

## 2. Building the lab machine

You don't need more than one machine for this. A spare box, a VM, a Raspberry Pi — anything that stays on and reachable from the training network is enough, because that single machine plays every role stage 4 needs: the DNS server, the domain's own A record, the mail host the MX record points to, and the service the port scan finds.

**Install dnsmasq.** On a Debian-family box this is `apt install dnsmasq`. If the lab machine itself runs something like Ubuntu Server with systemd-resolved active, systemd-resolved will already be holding port 53, and dnsmasq will fail to start until that's dealt with — either disable systemd-resolved's stub listener, or (simpler, and what the example config already does) bind dnsmasq explicitly to the lab network interface and its address with `bind-interfaces` and `listen-address`, which sidesteps the conflict in most setups without touching systemd-resolved at all.

**Drop the zone config in.** `iklwa-lab-dnsmasq.conf.example` has the A, CNAME, MX, and TXT records stage 4 needs, plus the one address that's meant to never answer (the reachability block's "down" target). Copy it to `/etc/dnsmasq.d/iklwa-lab.conf` (drop the `.example`), edit the IP and domain if they don't match what you actually want, and restart dnsmasq. The file itself explains the one wrinkle worth knowing about — dnsmasq won't let you hand-author a custom NS record, so that part of the lesson ends up smaller than the other four, and the config file's comments explain the honest fallback.

**Add the port-scan service.** The nmap block needs one open port that reports something recognizable. `infra/iklwa-lab-http.service.example` has the systemd unit for this already written — it runs a one-line HTTP server bound at boot, so it's always there without you having to remember to start it by hand:

```
cp infra/iklwa-lab-http.service.example /etc/systemd/system/iklwa-lab-http.service
systemctl daemon-reload
systemctl enable --now iklwa-lab-http
```

Check the `--bind` address inside the file matches the lab machine's real address before enabling it — it needs to agree with `iklwa-lab-dnsmasq.conf.example`, same as everything else in this section. Anything else on the box should stay closed — the point of the block is a fast top-ports scan finding exactly one thing, not a long scan finding a pile of them.

**Reachability, for free.** You already have what this block needs without building anything extra. The lab machine itself (10.0.0.53 in the example) answers ping normally — that's your "up" target. The address the TXT-record comment mentions, `branch-office.isipingofreight.internal` pointing at 10.0.0.99, resolves via DNS but has nothing listening on it — ping and traceroute against it genuinely time out, which is your "down" target. No second machine required; the contrast comes from one real host and one real gap.

---

## 3. Running the client-side setup

`infra/iklwa-stage4-network-setup.sh` is what actually points a Kali box's resolver at the lab machine. Under normal use nobody runs it by hand anymore — `iklwa-trainer.sh` runs it for you, via `sudo`, the first time a learner reaches stage 4 on a machine that isn't configured yet (see section 4). It's still a real, standalone script, and there are two situations where you'd still reach for it directly:

- **Pre-provisioning a batch of machines** before a session, so nobody hits a sudo prompt mid-lesson.
- **`--restore`**, to put a machine's original DNS settings back — the trainer never calls this for you, since undoing it isn't something stage 4 itself would ever need.

Before relying on it either way, open it and check the two values at the top match what you actually built in section 2 — the lab machine's IP and the domain — and that they agree with the matching three constants in `iklwa-trainer.sh` (section 1, step 3). Run it the same way either the trainer or you would:

```
sudo bash infra/iklwa-stage4-network-setup.sh
```

It backs up the box's original DNS settings (once — it won't overwrite that backup on a second run), points the resolver at your lab machine, and runs a quick `dig` check against your domain so whoever's watching knows immediately whether it worked. `--restore` undoes it using that backup.

This only needs to happen once per Kali box. If a trainee's box gets reimaged or they move to a different machine, it needs doing again there — which, same as the first time, the trainer will just handle on its own.

---

## 4. Where this fits with the trainer

Stage 4 is built. Before its tasks begin, `run_stage4` calls `s4_check_network` — a `dig +short` lookup against the lab domain — and if that comes back empty, it checks `/etc/resolv.conf` to tell apart two situations: this machine has never been pointed at the lab (worth fixing automatically), or it's pointed there already and the lab server itself isn't answering (a resolver rewrite wouldn't help, so the trainer just says so and stops, rather than asking for a password for nothing). In the first case, the trainer explains what it's about to do in one line and runs `infra/iklwa-stage4-network-setup.sh` itself via `sudo` — located next to the trainer script automatically, not tied to whatever folder the learner happened to run it from. If that succeeds, stage 4 continues in the same run. That's the same "check before letting things fail confusingly" philosophy `selfcheck()` already uses for stage 1 through 3's binary requirements, just extended one step further — fix it, not just report it — since this particular fix is safe, scoped, and something the learner would otherwise have no way to do themselves without being handed a second file and told what to do with it.

Everything stage 4's tasks actually check against — the TXT record's contents, which reachability target answers, which port and service nmap reports — comes from what you put in `iklwa-lab-dnsmasq.conf.example` and the systemd unit in section 2. The trainer's own `check_cmd()` pattern-matching (the same fallback already used for `dig`-style effect-free commands in stages 1-3) compares a learner's redirected evidence file against those real values.

---

## 5. Full file inventory for this piece

`infra/iklwa-stage4-network-setup.sh` — points the resolver at the lab machine. Runs itself, automatically via the trainer, the first time it's needed on a given Kali box. Still runnable by hand for batch pre-provisioning or `--restore`.

`infra/iklwa-lab-dnsmasq.conf.example` — runs once, on the lab machine, as the dnsmasq zone. Rename to drop `.example` before dropping it into `/etc/dnsmasq.d/`.

`infra/iklwa-lab-http.service.example` — runs once, on the lab machine, as the port-scan service. Copy into `/etc/systemd/system/` and drop the `.example`, same pattern as the dnsmasq file.

This guide — not run anywhere, just the instructions tying the pieces together.

`iklwa-trainer.sh`, `iklwa-trainer-intern-guide.md`, `iklwa-trainer-selftest.sh` — the trainer itself and its docs, all four stages now, everything in this guide is what stage 4 assumes is running underneath it.
