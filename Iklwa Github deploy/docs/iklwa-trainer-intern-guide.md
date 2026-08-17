# Iklwa Terminal Trainer — intern guide

This is the trainer that teaches you the terminal by putting you inside it. There's no slideshow and nothing to click through. You'll type real commands against a sandbox folder built just for you, and the script reacts to what actually happens on disk, not to whether you typed the "right" words. Budget about an hour and a half for stages 1 through 3 in your first sitting, plus a shorter session for stage 4 once your supervisor confirms the lab network is up, and know that you can stop and come back any time — it remembers exactly where you left off.

Keep the Iklwa Terminal Sheet next to you. This trainer is built directly on it.

## 1. Getting it onto your machine

You'll get this as a GitHub repository, not a file handed to you directly. It runs on Kali — doesn't matter if that's a VM, your own laptop, or a machine with Kali installed straight to the drive.

1. You'll get an invite to the repo by email or GitHub notification. Accept it — you'll need a GitHub account for this, so make one first if you don't already have one.
2. Open a terminal, `cd` to wherever you want the project to live (your home folder or Desktop both work fine), and clone it:
   ```
   git clone <the repo URL your supervisor gives you>
   cd iklwa-trainer
   ```
3. Everything else in this guide happens from inside that folder.

## 2. Running it for the first time

Two commands, and you'll only ever need to run the first one once:

```
chmod +x iklwa-trainer.sh
./iklwa-trainer.sh
```

`chmod +x` gives the file permission to run — you'll actually learn what this means properly inside stage 2, so don't worry about it for now. Once you've done that, `./iklwa-trainer.sh` starts it. If you close the terminal and come back later, you only need the second line, run from inside the `iklwa-trainer` folder; the chmod sticks.

You'll see a small banner, then a question: whether you've got a notepad and pen ready. Say yes and mean it — writing a command down the moment you learn it is what actually makes it stick, and you'll want the list later. If you genuinely don't have one on you, answering anything else a couple of times will let you through anyway, but don't make a habit of it.

After that it'll ask for your name. Type it and hit Enter — the trainer greets you by it throughout, and it's also how your progress gets saved, so use the same name every time you come back.

### If two of you are sharing one machine

That's fine. The trainer tracks progress separately by the name you type in, so you and the other intern can both train on the same machine without stepping on each other's work. Just make sure you each consistently use your own name at the name prompt.

## 3. What to expect

**Stage 1** goes through the terminal sheet one command at a time — where you are, moving around, doing things to files, reading files, getting unstuck. Every command gets explained in a couple of sentences, then you do it for real in the sandbox immediately after. There's no such thing as watching for more than about 20 seconds without typing something.

**Stage 2** is a full shift at Iklwa: a new client, a USB handoff, a script that won't run until you fix its permissions, and the point where flags (`-l`, `-la`, and so on) actually start making sense. It moves faster than stage 1 and expects you to reach for commands yourself. A few of these blocks ask for more than one thing at once (set up a case folder *and* an empty file *and* a copied template *and* a subfolder, all before it counts as done) — on those, you'll see a small `[OK]`/`[--]` checklist after each command showing exactly which parts are done and which aren't, so you always know what's actually left rather than guessing.

**Stage 3** is the solo case. You get a written tasking, and after that the trainer goes quiet — no more step-by-step prompts. You work the case, and you can type `hint` (or `help`, same thing) at any point if you're stuck — in stage 3 that costs a few points, but it's there to be used, not to be avoided. When you think you're done, type `done` and it'll audit your work and show you a checklist of what's actually complete and what isn't. You can fix things and type `done` again as many times as you need.

**Stage 4** is recon day — a new client, Isipingo Freight, and the first stage where you're pointed at a real network instead of just the sandbox folder. You'll look up their domain's DNS records one at a time (`dig`), check which of their sites actually answers a ping and which doesn't, and run a quick port scan to see what's actually open. This one needs the lab network to be up before it'll start. If this machine hasn't been pointed at the lab yet, the trainer notices and does that one-time fix itself, right there — you'll just get a `sudo` password prompt the first time you reach stage 4, nothing to run separately beforehand. If the lab server itself isn't up yet, the trainer tells you plainly instead of letting `dig` and `nmap` fail with confusing errors, and nothing is lost; just try again once your supervisor confirms the lab server's running.

Along the way you'll get **flashbacks** — sudden pop quiz questions about something from earlier ("quick, you're lost, what command shows where you are?"). These are free and don't cost you anything if you get them wrong, and if a question is genuinely unclear, typing `hint` there works too and won't count against you — it just nudges you toward the answer instead of ending the question. Flashbacks exist because forgetting stage 1 by the middle of stage 2 is normal, and this is how the trainer fights that.

If you get something wrong, the trainer never just says WRONG and leaves you there. First attempt gets a gentle nudge, second gets a proper hint, and if you're still stuck on the third it shows you the answer and has you type it yourself before moving on — typing it is not busywork, it's what actually makes it stick.

None of that applies to just looking around, though. If a task asks you to `cd` somewhere and you run `ls` first to see what's actually there, that's not a wrong answer — it doesn't cost you anything or count as an attempt. Only a command that genuinely fails (wrong name, wrong path, typo) counts against you. Poke around as much as you want; the trainer only reacts when something errors out for real.

## 4. A few things worth knowing before you start

**Nothing you do in here can break your actual machine.** The whole trainer lives inside one folder, `~/iklwa-lab/`, and every command you run is confined to it. If you delete something inside the lab, it's genuinely gone — there's no bin, and that's on purpose, it's the same as real life — but nothing outside that folder is ever touched.

**Ctrl+C is safe to practice.** It's an actual lesson in stage 1, and pressing it stops whatever command is currently running without closing the trainer itself. If you're ever unsure whether something is stuck, Ctrl+C is always safe to try.

**Typing `quit` (or `exit`) at any prompt saves your progress and closes the trainer cleanly.** So does just closing the terminal window, but `quit` is the tidy way to do it.

**Tab completion and the up arrow work for real.** When a lesson asks you to use Tab, it means the actual Tab key on your keyboard — type the first couple of letters of a folder name and press it. The up arrow recalls whatever you typed last, exactly like a real terminal, because this genuinely is one.

## 5. Coming back to it later

Nobody finishes this in one sitting, and it's built assuming you won't. Close the terminal whenever you need to. When you run `./iklwa-trainer.sh` again and type the same name, you'll be greeted by name and dropped back at the exact task you left off on — same score, same streak. Your sandbox folder and everything you've built in it stays exactly as you left it too; the trainer never wipes it out from under you on a normal restart.

## 6. Finishing stage 3 and handing in your work

When your `done` audit shows everything complete, the trainer builds a submission bundle automatically and tells you exactly where it saved it — something like:

```
~/iklwa-submission-<yourname>-<date>-<time>.tar.gz
```

That file has your case work and the audit result packaged together. It's not part of the git repo — it lives in your home folder, not inside the `iklwa-trainer` folder you cloned, and it isn't something you commit or push. Hand it back to your supervisor the way they've told you to (USB stick, a shared drive, whatever they've set up) — ask if you're not sure.

If you run stage 3 again later and pass a second time, it makes a new bundle with a fresh timestamp rather than touching the old one, so don't worry about overwriting anything by accident.

## 7. Command reference for the trainer itself

These are commands for the *trainer*, not for the terminal lessons inside it — run them from a normal prompt, before or instead of starting a session.

| Command | What it does |
|---|---|
| `./iklwa-trainer.sh` | Start training, or resume exactly where you left off. |
| `./iklwa-trainer.sh --stage 2` | Jump straight to stage 1, 2, 3, or 4. Useful for a deliberate re-run, or if your supervisor asks you to redo one stage. |
| `./iklwa-trainer.sh --reset` | Wipe your own progress and start stage 1 fresh. Your sandbox folder is left alone. |
| `./iklwa-trainer.sh --reset all` | Wipe both your progress and the sandbox folder, and rebuild from scratch. It asks you to type the sandbox path back before it does anything, so you can't trigger this by accident. |
| `./iklwa-trainer.sh --selfcheck` | Checks that your machine has everything the trainer needs, without touching your progress or sandbox. Good first move if something feels broken. |
| `./iklwa-trainer.sh --help` | Prints this list. |

## 8. If something goes wrong

**"Permission denied" when you try to run it.** You skipped `chmod +x iklwa-trainer.sh`, or ran it before that finished. Run that line again, then try `./iklwa-trainer.sh` again.

**"No such file or directory" when you type `./iklwa-trainer.sh`.** You're not in the folder where you copied the file. Check with `ls` — if you don't see `iklwa-trainer.sh` listed, `cd` to wherever you actually put it first.

**The trainer says a command is "blocked."** That's deliberate — a small number of commands (mainly `sudo`, and anything that would reach outside the sandbox folder) are switched off inside the trainer so nothing can go wrong even by accident. It's not a bug and it's not you doing anything wrong. Just try the command the lesson is actually asking for.

**You got kicked back to `~/iklwa-lab` with a message about "outside the lab."** Same idea — you navigated somewhere outside the sandbox, and the trainer brought you back automatically. No harm done, just carry on from there.

**Colors look wrong, or the progress bar looks like broken characters.** Harmless, and it won't affect your progress. Some terminal windows don't support color or special characters the same way — the trainer falls back to plain text automatically in most cases, but a few odd-looking terminal configurations can still slip through. Keep going; if it's genuinely unreadable, flag it to your supervisor along with what terminal app you're using.

**You typed the exact command the lesson asked for, but it's not being accepted.** Check where you actually are first — the prompt (`~/iklwa-lab/cases/...$`) always shows your current folder. A command like `grep FAILED access.log` only works if `access.log` is really in the folder you're standing in right now; the same command run from one folder over will just error out, same as on a real system. If you're not sure, `pwd` and `ls` cost you nothing and never count against you — use them to get your bearings, then try again from the right spot. Type `hint` if you're still stuck.

**You think the trainer itself has crashed (not just a lesson going wrong).** Run `./iklwa-trainer.sh --selfcheck` first — it'll tell you if something basic is missing from your machine. If everything there says OK and it still won't start, note down exactly what you typed and what appeared on screen, and bring it to your supervisor. Your progress up to your last completed task is safe either way, since it saves after every single task, not just when you quit cleanly.

**Stage 4 asked for my sudo password.** That's expected the first time this machine reaches stage 4 — it's the trainer pointing this box's DNS resolver at the lab server, a one-time fix it now does for you automatically instead of making you run a separate script first. It only needs to happen once per machine.

**Stage 4 says it can't reach the lab network.** That's not your machine being broken. Either the sudo step above didn't complete, or — more likely if you already got past that — the lab server itself isn't up right now. Tell your supervisor; there's nothing to fix on your end beyond that. Nothing about your progress is lost when this happens — run the trainer again once you're told the lab network's ready, and it picks up exactly at stage 4 where it left off.

**You want to start completely over, on purpose.** `./iklwa-trainer.sh --reset all` does exactly that. Ask your supervisor first if you're not sure whether you should.
