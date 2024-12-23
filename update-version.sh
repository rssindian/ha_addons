#!/bin/bash

# Step 1: Fetch the latest upstream version
UPSTREAM_VERSION=$(curl -s https://api.github.com/repos/Jackett/Jackett/releases/latest | jq -r '.tag_name')
echo "Latest Upstream Version: $UPSTREAM_VERSION"

# Step 2: Read the stored version
STORED_VERSION=$(cat .current_version)

if [ "$UPSTREAM_VERSION" == "$STORED_VERSION" ]; then
  echo "Version is up-to-date. Exiting..."
  exit 0
fi

echo "Version changed! Proceeding with update..."

# Step 3: Increment the version in config.yaml
FILE_PATH="./vpnjackett/config.yaml"
CURRENT_VERSION=$(sed -n '2s/version: v//p' "$FILE_PATH")
NEW_VERSION=$(echo "$CURRENT_VERSION" | awk -F. '{$NF += 1}1' OFS='.')
sed -i "2s/version: v.*/version: v$NEW_VERSION/" "$FILE_PATH"
echo "Updated version to: v$NEW_VERSION"

# Step 4: Commit and push changes
git config user.name "GitHub Actions Bot"
git config user.email "actions@github.com"
git add "$FILE_PATH"
git commit -m "$UPSTREAM_VERSION"
git push

# Step 5: Update stored version
echo "$UPSTREAM_VERSION" > .current_version
