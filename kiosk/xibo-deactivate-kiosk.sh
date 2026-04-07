#!/bin/bash
# Revert AccountsService to normal GNOME session.
# Called via doas by xibo-show-cms.sh for full reconfiguration.

cat > /var/lib/AccountsService/users/xibo << 'EOF'
[User]
Session=gnome
SystemAccount=false
EOF
