# Proton Mail setup

Proton Mail Plus on my own domain (registered with Cloudflare), read in
Thunderbird through Proton Mail Bridge. The opt-in `mail` module (`./bootstrap.sh --modules mail`)
installs both, makes Thunderbird the mailto handler and starts Bridge at login.
Everything below is done by hand once.

## 1. Domain (Cloudflare)

1. Cloudflare dashboard → Domain Registration → Register Domains → buy the domain.
   Cloudflare sells at cost, and the renewal price is the same as the first year.
2. Leave DNS on Cloudflare. Proton's records go there in step 3.

## 2. Proton account

1. Sign up at proton.me for **Mail Plus**. Annual billing is cheapest.
2. Turn on 2FA. Store the credentials and recovery phrase in the password manager.

## 3. Connect the domain

1. Proton → Settings → All settings → Organization → Domain names → Add domain.
2. Add each record Proton shows (TXT verification, MX ×2, SPF, DKIM CNAME ×3, DMARC)
   in Cloudflare → DNS → Records. **Set the DKIM CNAMEs to "DNS only" (grey cloud).**
   Cloudflare's proxy breaks them.
3. Wait for every check to go green in Proton.
4. Create the main address, e.g. `me@domain`.
5. Turn on **catch-all**: in the same Domain names screen, choose the catch-all address
   (the main one, or a dedicated `inbox@domain`).

## 4. Move off Hotmail

1. Proton → Settings → Import via Easy Switch → Outlook. This imports mail, contacts and calendar.
2. In Outlook.com → Settings → Mail → Forwarding → forward to the new address.
   Keep this on for a few months while accounts are moved over.
3. Change the address on important accounts first (bank, gov, work), then the rest.

## 5. Bridge + Thunderbird

1. `./bootstrap.sh --modules mail`.
2. Start `protonmail-bridge` once **with** its window and sign in. It stores its login in
   gnome-keyring. From the next login it starts hidden, via the module's autostart entry.
3. Bridge → the account → Mailbox details shows the local IMAP/SMTP host, ports and a
   Bridge-only password.
4. Thunderbird → Account Settings → Add Mail Account → use those details. Accept
   Bridge's self-signed certificate when asked.
5. If Thunderbird asks to become the default mail app, answer **No**. Saying yes makes it
   write `userapp-Thunderbird-*` entries; the `mail` module already registers it properly.
6. Optional, PGP to non-Proton people: Bridge already handles Proton-to-Proton
   encryption. For PGP with others, import your Proton key (Settings → Encryption and
   keys → Export) into Thunderbird → End-To-End Encryption.

## Throwaway addresses

With catch-all on, give any site `sitename@domain`. Nothing has to be created first.
If one starts spamming, add a Sieve filter
(Settings → All settings → Proton Mail → Filters → Add sieve filter):

```
require ["fileinto", "envelope"];

# One line per address that turned bad
if envelope :is "to" ["badsite@domain", "othersite@domain"] {
    fileinto "Spam";
    stop;
}
```

Use `discard;` instead of `fileinto "Spam";` to drop the mail silently.
Proton's hide-my-email aliases (10 on Mail Plus) are there for sign-ups that
shouldn't reveal the domain.
