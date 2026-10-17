package releasegates_test

import rego.v1
import data.releasegates

test_good_pull_request if {
  count(releasegates.deny) with input as good_input == 0
}

test_bad_pull_request_is_denied if {
  count(releasegates.deny) with input as bad_input > 0
}

good_input := {
  "pull_request": {
    "author_login": "author",
    "base_ref": "main",
    "merge_queue": true,
    "labels": [],
    "changed_files": ["src/PricingApi/Program.cs", "tests/PricingApi.Tests/QuoteEndpointTests.cs"]
  },
  "codeowners": ["reviewer"],
  "reviews": [{"user_login": "reviewer", "state": "APPROVED"}],
  "required_checks": ["build-test"],
  "checks": [{"name": "build-test", "conclusion": "success"}]
}

bad_input := {
  "pull_request": {
    "author_login": "author",
    "base_ref": "develop",
    "merge_queue": false,
    "labels": [],
    "changed_files": ["src/PricingApi/Program.cs"]
  },
  "codeowners": ["reviewer"],
  "reviews": [{"user_login": "author", "state": "APPROVED"}],
  "required_checks": ["build-test"],
  "checks": [{"name": "build-test", "conclusion": "failure"}]
}
