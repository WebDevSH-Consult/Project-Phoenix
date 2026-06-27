# PROJECT.md

## Cold Start Summary

### Context

Project Phoenix originated from the need to eliminate the repetitive and time-consuming process of rebuilding a Windows workstation after system failures or fresh installations. Following a recent Windows 11 reinstallation, numerous configuration issues arose, including PowerShell execution policies, fragmented game libraries, missing development tools, and the manual recreation of an AI-assisted development environment.

Rather than solving each problem individually, the project evolved into the design of a complete Infrastructure-as-Code platform for Windows. The objective is to define a desired workstation once and allow automation to install, configure, validate, maintain, and eventually repair the entire environment from a clean Windows installation.

The project encompasses Windows administration, AI tooling, software development, gaming, health monitoring, documentation, and long-term maintainability.

---

### User Goals and Reasoning

The user wants to build a professional-grade automation platform capable of reproducing their complete workstation with minimal manual intervention.

The original motivation was simply to automate software installation and configuration after Windows rebuilds. Through iterative discussion, the user refined this into a much broader vision: a modular platform that becomes the authoritative source of truth for every aspect of the workstation.

Key priorities include:

* Automating repetitive configuration tasks.
* Maintaining consistent Windows settings.
* Installing and configuring development tools.
* Managing AI tooling such as Claude Code and future AI assistants.
* Standardising gaming libraries across multiple launchers.
* Detecting duplicate installations and unnecessary storage usage.
* Producing health reports and ongoing system audits.
* Building a repository that follows professional engineering practices rather than becoming a collection of unrelated scripts.

The user also expressed a strong desire to learn through the project rather than simply consuming generated code. Documentation, architectural reasoning, and maintainability are therefore considered equally important to implementation.

---

### Key Progress and Decisions

The project has been formally named **Project Phoenix** and is hosted in a GitHub repository.

Major architectural decisions include:

* Treat Project Phoenix as a software platform rather than a PowerShell script.
* Adopt Infrastructure-as-Code principles.
* Use a modular architecture centred around a future "Phoenix Core".
* Ensure all modules follow a consistent lifecycle:

  * Initialise
  * Validate
  * Execute
  * Verify
  * Log
  * Report
* Store preferences in configuration files rather than hard-coded values.
* Design all automation to be idempotent, allowing safe repeated execution.
* Maintain extensive documentation from the beginning of development.

A phased roadmap has been established:

* Repository Foundation
* Phoenix Core
* Logging Engine
* Configuration Engine
* Bootstrap Engine
* Application Installer
* Windows Configuration
* Gaming Suite
* AI Development Environment
* Health Dashboard
* Self-Healing Workstation

The GitHub repository has been verified as accessible through ChatGPT's GitHub connector, with administrative permissions available. The default branch is currently `develop`, which will remain the active development branch during early development.

---

### Open Threads and Next Actions

Immediate priorities for Sprint 0 (Foundation) are:

* Establish the professional repository structure.
* Create the core documentation set, including:

  * README.md
  * MANIFESTO.md
  * PROJECT_CHARTER.md
  * ROADMAP.md
  * ARCHITECTURE.md
  * CONTRIBUTING.md
  * CHANGELOG.md
  * SECURITY.md
  * CODE_OF_CONDUCT.md
* Create foundational configuration files.
* Implement repository standards, including:

  * `.editorconfig`
  * `.gitattributes`
  * `.gitignore`
  * `VERSION`
* Create the first GitHub Actions workflow for continuous integration.
* Design the initial Bootstrap framework and Phoenix Core architecture.

Longer-term objectives include implementing automated software installation, Windows configuration, AI environment setup, gaming library management, workstation health monitoring, configuration backup and restoration, and a natural-language AI command centre capable of managing the workstation through conversational requests.

---

### Continuation Guidance

Continue acting as Lead Software Architect for Project Phoenix.

Prioritise long-term maintainability, modular design, documentation quality, and engineering discipline over rapid implementation. Treat every change as though it were part of a commercial-grade open-source project, ensuring that each commit improves the repository while remaining fully documented, version controlled, testable, and aligned with the project's architectural principles.
