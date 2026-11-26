# Workflow with Coder

As a developer of plume-works/images I want to keep image free of bloat and opinionated workflows.

As a coder template I supply basic agent harnesses with remote control and basic tooling needed to setup workspace (including bootstrapping clone repos).

--- 

As a developer of Dr.QP I want to be able to use Coder workspace with Dr.QP repo and bring exact version of ROS and accompanying tools into workspace, without need to copy agent harness setup. I want coder template to take care of that.

---

As a developer of any repo used in coder workspace:
 - I want to be able to use my custom tools.
 - I want to have my own AGENTS.md/CLAUDE.md and other rules and skills come from my repo. Coder template should not inject opinionated agent instructions.
 - I want to have access to claude remote-control available without modifying my repo. Similar to how Claude's cloud sessions work 

