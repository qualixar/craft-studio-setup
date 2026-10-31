# GUIDE-PROMPT: paste this into Claude Code

Copy the lines below, paste them into Claude Code, press Enter, and answer its questions. Nothing is installed without your yes.

```
/plugin marketplace add qualixar/craft-studio-setup
/plugin install craft-studio@craft-studio-setup
/craft-setup
```

What happens next: Claude Code checks what your Mac already has, explains each
app in one plain sentence, asks before each install, checks every download's
fingerprint, connects the apps, and prints a card of things you can now ask it
to do. It also asks whether you want the desktop apps so you can open the
files yourself. Choosing no keeps the install CLI-only. Downloads and first-run
macOS checks affect how long setup takes. This setup flow supports Mac only;
Windows installers are available from the upstream projects.
