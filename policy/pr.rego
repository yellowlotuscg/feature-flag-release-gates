package releasegates

import rego.v1

# A PR can merge only after a second person who is a CODEOWNER approves it.
deny contains msg if {
  not codeowner_approval
  msg := "at least one approving review must come from a CODEOWNER who is not the PR author"
}

codeowner_approval if {
  some review in input.reviews
  review.state == "APPROVED"
  review.user_login != input.pull_request.author_login
  some owner in input.codeowners
  owner == review.user_login
}

# Every check listed by the repository policy must have a successful conclusion.
deny contains msg if {
  required := input.required_checks[_]
  not successful_check(required)
  msg := sprintf("required check did not succeed: %s", [required])
}

successful_check(name) if {
  some check in input.checks
  check.name == name
  check.conclusion == "success"
}

# Tests must move with behavior changes unless a maintainer explicitly labels the PR.
deny contains "tests must be changed, or the PR must carry the no-tests-needed label" if {
  not tests_changed
  not no_tests_needed
}

tests_changed if {
  some file in input.pull_request.changed_files
  startswith(file, "tests/")
}

no_tests_needed if {
  some label in input.pull_request.labels
  lower(label) == "no-tests-needed"
}

# Deployments enter the release path only through main and a merge queue.
deny contains "target branch must be main" if {
  input.pull_request.base_ref != "main"
}

deny contains "the PR must be admitted through the merge queue" if {
  not input.pull_request.merge_queue
}
