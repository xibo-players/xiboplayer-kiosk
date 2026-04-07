#!/bin/bash
# Switch AccountsService session to kiosk mode.
# Called via doas by xiboplayer-setup.py after first-boot configuration.
# After this, GDM will launch gnome-kiosk-script-wayland on next login.

cat > /var/lib/AccountsService/users/xibo << 'EOF'
[User]
Session=gnome-kiosk-script-wayland
SystemAccount=false
EOF
