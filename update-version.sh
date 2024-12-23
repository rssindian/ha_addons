#!/bin/bash

# Step 1: Fetch the latest upstream version
UPSTREAM_VERSION=$(curl -s https://api.github.com/repos/Jackett/Jackett/releases/latest | jq -r '.tag_name')
echo "Latest Upstream Version: $UPSTREAM_VERSION"

# Step 2: Read the stored version
STORED_VERSION=$(cat .current_version)
echo "Stored Version: $STORED_VERSION"

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
echo "Updated version in ./vpnjackett/config.yaml to: $NEW_VERSION"

# Step 4: Update stored version in .current_version
echo "Updating .current_version with the latest version..."
echo "$UPSTREAM_VERSION" > .current_version
echo "New .current_version: $(cat .current_version)"

# Step 5: Commit and push changes together
git config --global user.name "GitHub Actions Bot"
git config --global user.email "actions@github.com"

# Ensure we're using the token for authentication (in the GitHub Actions context)
git remote set-url origin https://x-access-token:${GH_TOKEN}@github.com/${{ github.repository }}.git

# Stage both the updated config.yaml and .current_version
git add "$FILE_PATH" .current_version

# Commit both changes in one commit
git commit -m "Update version to $UPSTREAM_VERSION and .current_version"

# Push changes to the repository
git push origin HEAD

echo "Version update completed successfully and pushed in a single commit."

# Step 6: Trigger builder workflow using the GitHub API (corrected)
echo "Triggering Builder Workflow directly via GitHub API..."

# Trigger the builder workflow using the `workflow_dispatch` event
curl -X POST \
  -H "Authorization: token $GH_TOKEN" \
  -d '{"ref": "main"}' \
  https://api.github.com/repos/${{ github.repository }}/actions/workflows/builder.yml/dispatches

echo "Builder workflow triggered successfully."
