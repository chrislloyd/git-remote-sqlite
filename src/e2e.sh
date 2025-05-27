#!/bin/bash
# End-to-end test for git-remote-sqlite
# Tests basic workflows described in the README

set -e
set -u
set -o pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test directory setup - use system tmpdir
TEST_DIR=$(mktemp -d)
echo "Using temporary test directory: $TEST_DIR"

# Helper functions
pass() {
  echo -e "${GREEN}✓ $1${NC}"
}

fail() {
  echo -e "${RED}✗ $1${NC}"
  exit 1
}

# Function to print debug info
debug_output() {
  echo "Debug output:"
  echo "---"
  cat "$1"
  echo "---"
}

# Setup function - handles binary path and PATH configuration
setup() {
  # If binary path provided as argument, add its directory to PATH
  if [ $# -gt 0 ]; then
    BINARY_PATH="$1"
    echo "Using binary path from argument: $BINARY_PATH"

    echo "Using binary at $BINARY_PATH"

    # Add the binary directory to PATH so git can find git-remote-sqlite
    BINARY_DIR=$(dirname "$BINARY_PATH")
    export PATH="${BINARY_DIR}:$PATH"
    echo "Added to PATH: $BINARY_DIR"
  else
    echo "Using git-remote-sqlite from PATH"
  fi

  # Always use the command name for execution
  GIT_REMOTE_SQLITE="git-remote-sqlite"

  # Verify git can find our remote helper
  if ! which git-remote-sqlite >/dev/null 2>&1; then
    fail "git-remote-sqlite not found in PATH"
  fi
  echo "Verified git-remote-sqlite is in PATH"

  cd "$TEST_DIR"
}

teardown() {
  echo "Cleaning up test directory"
  cd /
  rm -rf "$TEST_DIR"
}

trap teardown EXIT

test_push() {
  echo "Test: Create and push a repository..."

  # Create a test repo
  mkdir -p test_repo
  cd test_repo
  git init .
  git config user.name "Test User"
  git config user.email "test@example.com"
  git config commit.gpgsign false

  # Create a test file
  echo "# Test Repository" > README.md
  echo "This is a test file." >> README.md

  # Commit the file
  git add README.md
  git commit -m "Initial commit"

  # Add the database as a remote and push
  git remote add origin "sqlite://${TEST_DIR}/test.db"

  # Run git push
  if ! git push origin main; then
    fail "Failed to push to SQLite database"
  fi

  pass "Successfully pushed to database"
  cd "$TEST_DIR"
  return 0
}

test_clone() {
  echo "Test: Clone from the database..."

  # Create a new directory to clone into
  mkdir -p clone_test
  cd clone_test

  # Initialize a new repository
  git init .
  git config user.name "Test User"
  git config user.email "test@example.com"
  git config commit.gpgsign false

  # Add the database as a remote and fetch
  git remote add origin "sqlite://${TEST_DIR}/test.db"

  if ! git fetch origin; then
    fail "Failed to fetch from SQLite database"
  fi

  git checkout -b main origin/main || fail "Failed to checkout branch from SQLite database"

  # Verify the content exists and matches exactly what was pushed
  [ -f README.md ] || fail "README.md not found in cloned repository"

  # Compare the cloned file with the original
  diff README.md "${TEST_DIR}/test_repo/README.md" || fail "Cloned README.md does not match original"

  # Verify specific content
  grep -q "# Test Repository" README.md || fail "README.md missing header"
  grep -q "This is a test file." README.md || fail "README.md missing content"

  # Check git log matches
  original_commit=$(cd "${TEST_DIR}/test_repo" && git rev-parse HEAD)
  cloned_commit=$(git rev-parse HEAD)
  [ "$original_commit" = "$cloned_commit" ] || fail "Commit hashes don't match between original and clone"

  pass "Successfully cloned from database with matching content"
  cd "$TEST_DIR"
  return 0
}

test_config() {
  echo "Test: Repository configuration..."

  # Test config options mentioned in README.md
  echo "Testing README.md config options..."
  
  # Test receive.denyDeletes
  "$GIT_REMOTE_SQLITE" config test.db receive.denyDeletes true || fail "Failed to set receive.denyDeletes"
  config_value=$("$GIT_REMOTE_SQLITE" config test.db --get receive.denyDeletes)
  config_value=$(echo "$config_value" | tr -d '\n')
  [ "$config_value" = "true" ] || fail "receive.denyDeletes value not set correctly: '$config_value'"
  
  # Test receive.denyNonFastForwards  
  "$GIT_REMOTE_SQLITE" config test.db receive.denyNonFastForwards true || fail "Failed to set receive.denyNonFastForwards"
  config_value=$("$GIT_REMOTE_SQLITE" config test.db --get receive.denyNonFastForwards)
  config_value=$(echo "$config_value" | tr -d '\n')
  [ "$config_value" = "true" ] || fail "receive.denyNonFastForwards value not set correctly: '$config_value'"

  # Test basic CRUD operations
  echo "Testing basic config operations..."
  
  # Test --list functionality
  "$GIT_REMOTE_SQLITE" config test.db --list > config_list.txt
  grep -q "receive.denyDeletes=true" config_list.txt || fail "--list missing receive.denyDeletes"
  grep -q "receive.denyNonFastForwards=true" config_list.txt || fail "--list missing receive.denyNonFastForwards"

  # Test --unset functionality
  "$GIT_REMOTE_SQLITE" config test.db --unset receive.denyNonFastForwards || fail "Failed to unset receive.denyNonFastForwards"
  
  # Verify it's gone
  if "$GIT_REMOTE_SQLITE" config test.db --get receive.denyNonFastForwards 2>/dev/null; then
    fail "receive.denyNonFastForwards should have been unset but still exists"
  fi

  # Test overwriting existing values
  "$GIT_REMOTE_SQLITE" config test.db receive.denyDeletes false || fail "Failed to overwrite receive.denyDeletes"
  config_value=$("$GIT_REMOTE_SQLITE" config test.db --get receive.denyDeletes)
  [ "$(echo "$config_value" | tr -d '\n')" = "false" ] || fail "receive.denyDeletes overwrite failed"

  # Test error cases
  echo "Testing error cases..."
  
  # Test --get for non-existent key
  if "$GIT_REMOTE_SQLITE" config test.db --get nonexistent.key 2>/dev/null; then
    fail "Should fail when getting non-existent key"
  fi

  pass "Successfully tested configuration functionality"
  return 0
}

test_update() {
  echo "Test: Update repository and verify synchronization..."

  # Go back to the test repo
  cd "$TEST_DIR/test_repo"

  # Make changes
  echo "This line was added in an update." >> README.md
  echo "## New Section" >> README.md
  echo "Additional content for testing." >> README.md
  git add README.md
  git commit -m "Update README.md with new content"

  # Push changes
  if ! git push origin main; then
    fail "Failed to push updates"
  fi

  # Go to clone and pull
  cd "$TEST_DIR/clone_test"

  # Pull changes
  if ! git pull origin main; then
    fail "Failed to pull updates"
  fi

  # Verify the updated files are identical
  diff README.md "${TEST_DIR}/test_repo/README.md" || fail "Updated README.md files don't match"

  # Verify all expected content is present
  grep -q "# Test Repository" README.md || fail "Original header missing after update"
  grep -q "This is a test file." README.md || fail "Original content missing after update"
  grep -q "This line was added in an update." README.md || fail "Updated content not found in clone"
  grep -q "## New Section" README.md || fail "New section missing in clone"
  grep -q "Additional content for testing." README.md || fail "Additional content missing in clone"

  # Verify commit history matches
  original_commit=$(cd "${TEST_DIR}/test_repo" && git rev-parse HEAD)
  cloned_commit=$(git rev-parse HEAD)
  [ "$original_commit" = "$cloned_commit" ] || fail "Commit hashes don't match after update"

  # Verify commit count matches
  original_count=$(cd "${TEST_DIR}/test_repo" && git rev-list --count HEAD)
  cloned_count=$(git rev-list --count HEAD)
  [ "$original_count" = "$cloned_count" ] || fail "Commit counts don't match: original=$original_count, clone=$cloned_count"

  pass "Successfully tested repository updates with verified content synchronization"
  cd "$TEST_DIR"
  return 0
}

# TODO: High signal config tests to add:
# - Test that receive.denyDeletes actually prevents branch/tag deletions during push
# - Test that receive.denyNonFastForwards prevents non-fast-forward pushes
# - Test config persistence across multiple git operations
# - Test config inheritance and precedence in git remote operations

# Main test function
run_tests() {
  echo "Starting end-to-end tests for git-remote-sqlite..."

  test_config
  test_push
  test_clone
  test_update

  echo -e "\n${GREEN}All tests passed successfully!${NC}"
  return 0
}

# Run all tests
setup "$@"
run_tests
