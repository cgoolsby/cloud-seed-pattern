# Prime Command - Initialize Repository Context

## Step 1: Core Documentation
READ the README.md to understand the overall project purpose and structure.
READ CLAUDE.md for specific instructions and workflows.

## Step 2: Repository Structure
RUN ls -la to see the top-level directory structure.
LIST the scripts/ directory to understand available automation.
LIST the components/ directory to see reusable modules.

## Step 3: Claude-Specific Context
READ ai_docs/architecture-overview.md for system design understanding.
READ ai_docs/component-patterns.md for installation patterns.
READ ai_docs/crossplane-patterns.md for multi-account setup.
READ ai_docs/gitops-workflows.md for development workflows.
READ ai_docs/troubleshooting-guide.md for debugging help.

## Step 4: Current Deployment State
READ clusters/management/primary/kustomization.yaml to see active components.
READ clusters/management/prim/kustomization.yaml to compare environments.
CHECK for .pre-commit-config.yaml.bak (pre-commit hooks status).

## Step 5: Key Scripts Review
READ scripts/bootstrap-flux.sh to understand Flux installation.
READ scripts/dev-workflow.sh for local development patterns.
READ scripts/create-cluster.sh for cluster creation patterns.

## Step 6: Verify Git State
RUN git status to check working directory.
RUN git log -5 --oneline to see recent commits.
CHECK git branch to see current branch.