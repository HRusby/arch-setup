
# arch-setup: run the installer on the first console (appended to releng's .zlogin by iso/build.sh).
if [[ $(tty) == /dev/tty1 ]]; then
    install-arch || echo "install-arch stopped; fix the problem above, then run: install-arch --resume (skips archinstall once the system is installed)"
fi
