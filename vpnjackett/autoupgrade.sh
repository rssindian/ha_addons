
#!/bin/bash

CONFIG_FILE="./vpnjackett/config.yaml"
VERSION_FILE="./vpnjackett/.jackett_version"

# Step 1: Fetch the latest upstream version
UPSTREAM_VERSION=$(curl -s https://api.github.com/repos/Jackett/Jackett/releases/latest | jq -r '.tag_name')
echo "Latest Upstream Version: $UPSTREAM_VERSION"

# Step 2: Read the stored version
STORED_VERSION=$(cat "$VERSION_FILE")
echo "Stored Version: $STORED_VERSION"

if [ "$UPSTREAM_VERSION" == "$STORED_VERSION" ]; then
  echo "Version is up-to-date. Exiting..."
  # Indicate failure (no update)
  exit 1
fi

echo "Version changed! Proceeding with update..."

# Step 3: Increment the version in config.yaml
CURRENT_VERSION=$(sed -n '2s/version: v//p' "$CONFIG_FILE")
NEW_VERSION=$(echo "$CURRENT_VERSION" | awk -F. '{$NF += 1}1' OFS='.')
sed -i "2s/version: v.*/version: v$NEW_VERSION/" "$CONFIG_FILE"
echo "Updated version in $CONFIG_FILE to: $NEW_VERSION"

# Step 4: Update stored version in .jackett_version
echo "Updating $VERSION_FILE with the latest version..."
echo "$UPSTREAM_VERSION" > $VERSION_FILE
echo "New $VERSION_FILE content: $(cat "$VERSION_FILE")"

# Step 5: Commit and push changes
git config --global user.name "GitHub Actions Bot"
git config --global user.email "actions@github.com"

# Ensure we're using the token for authentication (in the GitHub Actions context)
git remote set-url origin https://x-access-token:${PT_TOKEN}@github.com/$GITHUB_REPOSITORY.git

# Commit all changes in a single commit
git add "$CONFIG_FILE" "$VERSION_FILE"
git commit -m "Update Jackett to $UPSTREAM_VERSION"
git push origin main

echo "Version update completed successfully and pushed in a single commit."

# Indicate success
exit 0
