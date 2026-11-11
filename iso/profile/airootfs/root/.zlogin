
# arch-setup: run the installer on the first console (appended to releng's .zlogin by iso/build.sh).
if [[ $(tty) == /dev/tty1 ]]; then
    install-arch || echo "install-arch stopped; fix the problem above and run install-arch again."
fi
