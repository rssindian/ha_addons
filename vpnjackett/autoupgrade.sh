
#!/bin/bash
set -euo pipefail

CONFIG_FILE="./vpnjackett/config.yaml"
VERSION_FILE="./vpnjackett/.version"
CHANGELOG_FILE="./vpnjackett/CHANGELOG.md"
UPSTREAM_REPO="Jackett/Jackett"     # GitHub owner/repo for upstream
DEFAULT_BRANCH="main"               # change if you use a different default branch

# Step 1: Fetch the latest upstream version
UPSTREAM_VERSION=$(curl -s https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest | jq -r '.tag_name')
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

# Step 4: Fetch and process the changelog from upstream
UPSTREAM_JSON=$(curl -s "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest")
UPSTREAM_NOTES=$(echo "$UPSTREAM_JSON" | jq -r '.body // "No upstream release notes found."')

# Normalise newlines (GitHub returns \r\n in .body sometimes) and
# replace bullets like "* <40-hex> message" with
# "* [<7-hex>](.../commit/<40-hex>) message"

COMMIT_URL="https://github.com/${UPSTREAM_REPO}/commit"
UPSTREAM_NOTES_CLEAN=$(
  printf "%s" "$UPSTREAM_NOTES" \
  | tr -d '\r' \
  | perl -0777 -pe "s{^\s*\*\s+([0-9a-f]{7})([0-9a-f]{33})\b}{* [\\1](${COMMIT_URL}/\\1\\2)}gim"
)

# Create CHANGELOG.md  
if [[ ! -f "$CHANGELOG_FILE" ]]; then
  echo "Creating $CHANGELOG_FILE…"
  touch "$CHANGELOG_FILE"
fi

DATE_STR=$(date +%F)
UPSTREAM_LINK="https://github.com/${UPSTREAM_REPO}/releases/tag/${UPSTREAM_VERSION}"

# Build the new changelog section
TMP_CL="${CHANGELOG_FILE}.new"
{
  echo "## v${NEW_VERSION} – ${DATE_STR}"
  echo "### Upstream (${UPSTREAM_REPO} ${UPSTREAM_VERSION})"
  echo "Link: ${UPSTREAM_LINK}"
  echo
  echo "${UPSTREAM_NOTES}"
} > "$TMP_CL"

mv "$TMP_CL" "$CHANGELOG_FILE"
echo "Prepended new entry to $CHANGELOG_FILE"


# Step 5: Update stored version in .jackett_version
echo "Updating $VERSION_FILE with the latest version..."
echo "$UPSTREAM_VERSION" > $VERSION_FILE
echo "New $VERSION_FILE content: $(cat "$VERSION_FILE")"

# Step 6: Commit and push changes
git config --global user.name "GitHub Actions Bot"
git config --global user.email "actions@github.com"

# Ensure we're using the token for authentication (in the GitHub Actions context)
git remote set-url origin https://x-access-token:${PA_TOKEN}@github.com/$GITHUB_REPOSITORY.git

# Commit all changes in a single commit
git add "$CONFIG_FILE" "$VERSION_FILE"
git commit -m "Update Jackett to $UPSTREAM_VERSION"
git push origin "${DEFAULT_BRANCH}"

echo "Version update completed successfully and pushed in a single commit."

# Indicate success
exit 0
