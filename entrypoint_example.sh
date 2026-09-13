#!/bin/bash
set -e

# 1. Ensure internal .ssh folder structure exists securely
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# 2. Safely copy mounted keys into the container's native filesystem layer
if [ -d /tmp/.ssh ] && [ "$(ls -A /tmp/.ssh 2>/dev/null)" ]; then
    cp -r /tmp/.ssh/* /root/.ssh/ 2>/dev/null || true
fi

# 3. Lock down file execution permissions strictly for Linux compatibility
chmod 600 /root/.ssh/* 2>/dev/null || true

# 4. Map the custom key configuration route for GitHub connections
echo -e "Host github.com\n  IdentityFile /root/.ssh/key\n  IdentitiesOnly yes" > /root/.ssh/config

# 5. Fire up the background SSH Agent explicitly for this environment session
eval "$(ssh-agent -s)"

# 6. Check if the key file explicitly exists before registering it into active memory
if [ -f /root/.ssh/key ]; then
    ssh-add /root/.ssh/key 2>/dev/null
else
    echo "⚠️ File check: /root/.ssh/key not found."
fi

# 7. Print out diagnostic check to screen
echo "--------------------------------------------------------"
echo "Checking SSH Authentication..."
ssh -T git@github.com -o StrictHostKeyChecking=no 2>&1 | grep -E "Hi|successfully authenticated" || echo "⚠️ SSH Authentication failed."
echo "--------------------------------------------------------"

git config --global user.name "name"
git config --global user.email "email

# (Optional) Prevent standard directory ownership security errors in Docker
git config --global --add safe.directory "*"

echo "==> Git configured successfully for: email"
echo "==> Handing over to CMD."


# 8. Drop the user straight into the standard interactive command prompt
exec "$@"