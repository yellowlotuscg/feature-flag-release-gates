.DEFAULT_GOAL := test
DOTNET := $(HOME)/.local/bin/dotnet

.PHONY: test run policy-test bicep-build audit-offline rollout-dry

test:
	PATH="$(HOME)/.local/bin:$(PATH)" $(DOTNET) test tests/PricingApi.Tests/PricingApi.Tests.csproj
	python3 -m unittest discover -s tests -p 'test_*.py'

run:
	PATH="$(HOME)/.local/bin:$(PATH)" $(DOTNET) run --project src/PricingApi/PricingApi.csproj

policy-test:
	opa test policy -v --ignore '*.json'
	conftest verify --policy policy
	conftest test policy/testdata/good.json --policy policy --namespace releasegates

bicep-build:
	az bicep build --file infra/main.bicep

audit-offline:
	python3 scripts/approval_audit.py --offline --output-prefix audit/report

rollout-dry:
	DRY_RUN=1 bash scripts/rollout.sh 10
