# Singularity Course Management System Documentation

## Introduction

**Why this documentation?**
This document provides a comprehensive overview of the Singularity system, primarily intended for developers and instructors who wish to understand, deploy, modify, or contribute to the platform. It details the architecture, components, setup, and operational aspects.

**Target Audience:**
*   **Developers/Instructors:** Individuals looking to set up Singularity for their own courses, customize its features, or contribute to its open-source development.
*   **Students/Users (Secondary):** While not the primary audience, students might find parts of this document useful for understanding the underlying mechanics of the course infrastructure they interact with.

---

## 1. Developer-Facing / Internal Documentation

### 1.1. README Highlights (Summary)

*(This summarizes key information found in the root [`README.md`](README.md).)*

*   **Project Purpose:** Singularity is an integrated system designed to manage course logistics, particularly for programming-intensive courses like the Kernel Development Learning Pipeline (KDLP). It handles user authentication, assignment submission via Git, email integration for patches/reviews, peer review management, grading workflows, and provides a web dashboard for students and instructors.
*   **Prerequisites:** `git`, `podman`, `podman-compose`. For testing: `flake8`, `shellcheck`, `jq`, `curl` (full version, not minimal), `socat`. 
*   **Installation/Setup:**
    1.  Clone the repository.
    2.  Create empty `docs` and `repos` directories at the root.
    3.  Build containers: `podman-compose build`
    4.  Launch containers: `podman-compose up -d`
*   **Running Locally:** Services listen on Unix sockets in the `socks/` directory. Use `./dev_sockets.sh &` (or `sudo ./dev_sockets.sh &`) to proxy standard TCP ports to these sockets for access via browsers, email clients, etc. 
*   **Running Tests:** Execute `./test.sh`. Ensure prerequisites are installed.
*   **Basic Usage:** Access the web interface via the proxied HTTPS port. A test user `resu` with password `ssap` is created by the test script. Email and Git access also use the proxied ports. The initial homepage might be a 404; use navigation links for services.
*   **Contribution Guidelines:** See [`CONTRIBUTORS.md`](CONTRIBUTORS.md).
*   **License:** GPLv3

### 1.2. Architecture Documentation

**High-Level Overview:**

Singularity employs a microservices-like architecture orchestrated using `podman-compose`. Components communicate primarily via proxied requests through Nginx or direct interaction with shared databases and a central Git repository used for grading. The system manages assignment submission via email (`git send-email`), automated checks, peer review logistics, and feedback delivery via a web dashboard.

**Core Components:**

*   **`extenginx`:** An Nginx container acting as the front-door reverse proxy. It handles SSL termination (HTTPS, SMTPS, POP3S) and routes requests to the appropriate backend services based on protocol and path. Uses a flexible snippet-based configuration.
*   **`orbit`:** The primary web application and API backend ([`orbit/radius.py`](orbit/radius.py)). Handles:
    *   User registration and login (password hashing with bcrypt).
    *   Session management.
    *   Web dashboard displaying assignment status, deadlines, peer reviews. **Reads submission status and feedback (currently from databases, planned to read from `git notes` in the grading repository).**
    *   Serving static course material content (Markdown rendering) from `docs/`.
    *   Proxying requests to `cgit` for web-based Git repository viewing.
    *   Authentication endpoint for mail services (`/mail-auth`).
    *   Authentication for Git operations over HTTP (Basic Auth).
    *   Generating `Containerfile` for student development environments.
    *   Uses [`orbit/db.py`](orbit/db.py) for user, session, and oopsie data. **Has read-only access to `mailman` and `denis` databases.**
*   **`mailman`:** Handles processing of email submissions (patchsets) ([`mailman/patchset.py`](mailman/patchset.py), [`mailman/submit.py`](mailman/submit.py)).
    *   Receives transactions containing email patches from the SMTP server.
    *   Applies patches to a central grading Git repository ([`mailman/patchset.py#L100`](mailman/patchset.py)), creating a commit and a unique tag (e.g., `<submission_id>`).
    *   Performs initial automated checks (e.g., whitespace errors, patch corruption).
    *   Records submission metadata in its database ([`mailman/db.py`](mailman/db.py)).
    *   **Writes initial automated feedback results to `git notes` associated with the submission commit (e.g., in `refs/notes/mailman`).** (Currently stores status in `Gradeable.status`).
    *   Provides tools for inspecting submissions/gradeables ([`mailman/inspector.py`](mailman/inspector.py)).
*   **`denis`:** Manages assignment structure, deadlines, peer review logistics, and timed events.
    *   Defines assignments and due dates ([`denis/db.py`](denis/db.py), [`denis/configure.py`](denis/configure.py)).
    *   Assigns peer reviews based on initial submissions ([`denis/initial.py`](denis/initial.py)).
    *   On due dates:
        *   Identifies the latest valid submission for each student per assignment component ([`denis/utilities.py`](denis/utilities.py)).
        *   Creates named tags in the grading repository (e.g., `assignment_component_username`) pointing to the corresponding submission commit/tag ([`denis/utilities.py`](denis/utilities.py)). The tag message currently contains the automated feedback status from `Gradeable.status`.
        *   Releases submissions for review/grading stages ([`denis/initial.py`](denis/initial.py), [`denis/peer_review.py`](denis/peer_review.py), [`denis/final.py`](denis/final.py)).
    *   **Potentially runs more comprehensive, assignment-specific automated checks after due dates and adds feedback to `git notes` (e.g., in `refs/notes/denis`).**
*   **`git`:** Manages the central bare Git repository (`grading.git`) used for storing applied patches, feedback notes, and grading tags.
    *   Uses `cgit` for web interface (proxied via `orbit`).
    *   Provides scripts for repository creation and setup ([`git/create-repo.sh`](git/create-repo.sh), [`git/setup-repo.sh`](git/setup-repo.sh)).
    *   Handles Git pushes via `git-http-backend` ([`git/cgi-bin/git-receive-pack`](git/cgi-bin/git-receive-pack)), authenticated by `orbit` via Nginx/cgit proxy path.
    *   **Access Control:** Students do *not* have direct write access. `mailman` and `denis` push tags and notes. `orbit` reads data (potentially via clone/fetch). Graders interact via standard Git tools (pushing notes).
*   **`submatrix`:** Integrates with a Synapse Matrix homeserver.
    *   Provides a custom password authentication provider ([`submatrix/orbit_auth.py`](submatrix/orbit_auth.py)) that delegates authentication checks to `orbit` ([`submatrix/orbit_auth.py`](submatrix/orbit_auth.py)). This allows users to log into Matrix with their Orbit credentials.
    *   Configured via [`submatrix/homeserver.yaml.template`](submatrix/homeserver.yaml.template).
*   **`journal`:** A custom C component responsible for managing email data storage and access control using extended attributes (`xattr`) ([`journal/init_journal.c`](journal/init_journal.c)). It maintains a journal file that tracks the state of all emails in the mail directory, enforces per-user access limits, and provides utilities for initializing, updating, and restricting access to the email journal.
*   **`smtp`:** A custom C implementation of an SMTP server ([`smtp/smtp.c`](smtp/smtp.c)), designed to securely receive assignment submissions via email. It handles authentication, message parsing, and storage of incoming emails and patchsets, integrating tightly with the `journal` component for access control and with `extenginx` for SSL termination and proxying.

### 1.4. API Documentation (Orbit Service)

**Authentication:**
*   Web UI uses session cookies established via `/login`.
*   Git HTTP clients use HTTP Basic Authentication, checked against Orbit credentials ([`orbit/radius.py`](orbit/radius.py)).
*   Mail clients authenticate via Nginx's `auth_http` mechanism, which calls Orbit's `/mail-auth` endpoint ([`orbit/radius.py`](orbit/radius.py)).
*   `/containerfile` endpoint uses HTTP Basic Authentication ([`orbit/radius.py`](orbit/radius.py)).

**Endpoints:**

*   **`POST /register`**
    *   Description: Registers a new user.
    *   Request Body (form-data): `student_id`, `username`, `password`
    *   Response: Redirects or HTML page indicating success/failure. Fails if `student_id` is already used ([`test.sh`](test.sh)).
*   **`POST /login`**
    *   Description: Authenticates a user and establishes a session.
    *   Request Body (form-data): `username`, `password`
    *   Response: Sets session cookie, redirects to dashboard or original target. Returns error message on failure ([`test.sh`](test.sh)).
*   **`GET /logout`** (or POST?)
    *   Description: Clears the user's session cookie.
    *   Response: Redirects to login page or homepage.
*   **`GET /dashboard`**
    *   Description: Displays the main course dashboard. Shows assignment status, deadlines, peer review assignments, links, and Oopsie button. Requires active session. **Pulls submission status and feedback information primarily by reading `git notes` from the grading repository (future state) and supplementing with data from `mailman` and `denis` databases.** Feedback details might be summarized (e.g., "warning", "error") before deadlines.
    *   Response: HTML page ([`orbit/radius.py`](orbit/radius.py)).
*   **`POST /dashboard`**
    *   Description: Handles form submissions from the dashboard, currently only the "Oopsie" request.
    *   Request Body (form-data): `assignment`, `confirm=y`
    *   Response: HTML page confirming Oopsie or error. Records request in [`Oopsie`](orbit/db.py) table ([`orbit/radius.py`](orbit/radius.py)).
*   **`GET /activity`**
    *   Description: Placeholder/stub for an activity log page ([`orbit/radius.py`](orbit/radius.py)). Requires active session.
    *   Response: HTML page.
*   **`GET /mail-auth`**
    *   Description: Internal endpoint used by Nginx (`auth_http`) to verify mail client credentials (likely passed via Basic Auth headers). Requires valid Orbit credentials.
    *   Response: Specific HTTP headers indicating success (e.g., `Auth-Status: OK`) or failure (e.g., `Auth-Status: Invalid login`) for Nginx.
*   **`GET /cgit/*`**
    *   Description: Proxies requests to the backend `cgit` service. Handles authentication: requires session for web access, or valid Basic Auth for Git clients (`User-Agent: git/*`).
    *   Response: Proxied response from `cgit` (HTML, Git data, etc.) or authentication challenge (401/403). ([`orbit/radius.py`](orbit/radius.py))
*   **`GET /containerfile`**
    *   Description: Generates a personalized `Containerfile` for setting up a student development environment, including credentials for Git/Mutt. Requires HTTP Basic Authentication.
    *   Query Parameters: `?vim=true` (optional) to set vim as default editor.
    *   Response: `text/plain` containing the `Containerfile` content ([`orbit/radius.py`](orbit/radius.py)).
*   **`GET /*.md`**
    *   Description: Serves Markdown files from the configured `doc_root` ([`orbit/config.py`](orbit/config.py)) rendered as HTML. Uses the first H1 as the page title.
    *   Response: HTML page ([`orbit/radius.py`](orbit/radius.py)).
*   **`GET /`**
    *   Description: Serves `index.md` from the `doc_root` if it exists, otherwise may result in 404 or redirect depending on configuration.

### 1.6. Database Schema Documentation

Singularity uses three separate SQLite databases.

**1. Orbit Database (`/var/lib/orbit/orbit.db`)** ([`orbit/db.py`](orbit/db.py))

*   **`User` Table:** Stores user account information.
    *   `username` (TEXT, UNIQUE): The user's login name.
    *   `pwdhash` (TEXT, NULLABLE): Bcrypt hash of the user's password.
    *   `student_id` (TEXT, UNIQUE, NULLABLE): Unique student identifier, used for registration.
    *   `fullname` (TEXT, NULLABLE): User's full name.
*   **`Session` Table:** Stores active web session tokens.
    *   `token` (TEXT, PRIMARY KEY): Secure random session token.
    *   `username` (TEXT, UNIQUE): User associated with the session.
    *   `expiry` (FLOAT): Unix timestamp when the session expires.
*   **`Oopsie` Table:** Tracks student requests for extensions or exceptions ("Oopsie" tokens).
    *   `user` (TEXT, PRIMARY KEY): The username requesting the oopsie. (Note: PK implies one oopsie per user across all assignments?)
    *   `assignment` (TEXT): The assignment the oopsie applies to.
    *   `timestamp` (INTEGER): Unix timestamp when the oopsie was requested.

**2. Mailman Database (`/var/lib/mailman/submissions.db`)** ([`mailman/db.py`](mailman/db.py))

*   **`Submission` Table:** Records details about each email submission received.
    *   `submission_id` (TEXT, UNIQUE): A unique identifier for the submission (e.g., Git tag).
    *   `timestamp` (INTEGER): Unix timestamp of submission reception.
    *   `user` (TEXT): Username of the submitter.
    *   `recipient` (TEXT): Intended recipient (likely the assignment identifier, e.g., `assignment1@domain`).
    *   `email_count` (INTEGER): Number of emails/patches in the submission.
    *   `in_reply_to` (TEXT, NULLABLE): Message-ID this submission is replying to (for threading).
    *   `status` (TEXT, NULLABLE): Current processing or grading status (e.g., 'pending', 'applied', 'failed').
*   **`Gradeable` Table:** Represents items derived from submissions that are subject to grading.
    *   `submission_id` (TEXT, UNIQUE): Link back to the `Submission` table (or Git tag).
    *   `timestamp` (INTEGER): Unix timestamp relevant to this gradeable item.
    *   `user` (TEXT): Username associated with the gradeable item.
    *   `assignment` (TEXT): The assignment name.
    *   `component` (TEXT): The specific part of the assignment (e.g., 'initial', 'review1', 'final').
    *   `status` (TEXT, NULLABLE): Grading status for this specific component.

**3. Denis Database (`/var/lib/denis/assignments.db`)** ([`denis/db.py`](denis/db.py))

*   **`Assignment` Table:** Defines the structure and deadlines for course assignments.
    *   `name` (TEXT, UNIQUE): Unique name for the assignment (e.g., 'hw1').
    *   `initial_due_date` (INTEGER): Unix timestamp for the initial submission deadline.
    *   `peer_review_due_date` (INTEGER): Unix timestamp for the peer review deadline.
    *   `final_due_date` (INTEGER): Unix timestamp for the final submission deadline.
*   **`PeerReviewAssignment` Table:** Stores the peer review pairings for each assignment.
    *   `assignment` (TEXT): Foreign key to `Assignment.name`.
    *   `reviewer` (TEXT): Username of the student performing the review.
    *   `reviewee1` (TEXT, NULLABLE): Username of the first student being reviewed by `reviewer`.
    *   `reviewee2` (TEXT, NULLABLE): Username of the second student being reviewed by `reviewer`.
    *   *Index:* Unique index on (`assignment`, `reviewer`).

**Notes on Feedback Storage:**

*   The `mailman.db.Gradeable.status` field ([`mailman/db.py`](mailman/db.py)) currently holds the result string from initial automated checks ([`mailman/submit.py#L99`](mailman/submit.py), [`mailman/patchset.py#L88`](mailman/patchset.py)).
*   **Future Direction:** Detailed feedback (automated and manual)

### 1.7. Contribution Guidelines

Refer to the [`CONTRIBUTORS.md`](CONTRIBUTORS.md) file. 

### 1.8. Testing Documentation

*   **Primary Test Suite:** [`test.sh`](test.sh)
*   **Strategy:** End-to-end testing using `curl` against a running instance (launched via `podman-compose`). It simulates user actions like registration and login. Requires `socat` proxying to be active.
*   **Linting:** [`script-lint.sh`](script-lint.sh) uses `shellcheck` and `flake8` to check script and Python code quality.
*   **Key Test Cases Covered (in [`test.sh`](test.sh)):**
    *   Successful user registration.
    *   Failure on attempting to register with a duplicate student ID.
    *   Failure on login with invalid credentials.
    *   Successful login with valid credentials.

### 1.9. Grading and Feedback Workflow

This section outlines the process from submission to feedback delivery, incorporating the planned use of `git notes`.

1.  **Submission:**
    *   Student uses `git send-email` to send a patch or patchset to a designated assignment email address (e.g., `assignment1@hostname`).
2.  **Initial Processing (`mailman`):**
    *   The SMTP server receives the email transaction.
    *   `mailman` ([`mailman/submit.py`](mailman/submit.py)) processes the transaction:
        *   Applies the patches to the `grading.git` repository, creating a commit.
        *   Creates a unique Git tag (e.g., `<submission_id>`) pointing to this commit.
        *   Runs initial automated checks (whitespace, corruption) via [`mailman/patchset.py`](mailman/patchset.py).
        *   Records submission metadata in `mailman.db` (`Submission` table).
        *   Records a `Gradeable` entry in `mailman.db`, marking it as `initial` or `final` based on timestamp relative to deadlines ([`mailman/submit.py#L52`](mailman/submit.py)).
        *   **Writes the results of the automated checks (e.g., "whitespace error", "patch applies", "corrupt patch") to `git notes` in a dedicated namespace (e.g., `refs/notes/mailman`) associated with the submission commit.**
3.  **Student Activity Log (`orbit`):**
    *   The student can view the `Activity Log` ([`orbit/header.html`](orbit/header.html)) on the website, which shows basic submission receipt confirmation based on the `Submission` table.
4.  **Due Date Processing (`denis`):**
    *   At predefined deadlines (initial, peer review, final), `denis` scripts run:
        *   Identifies the canonical submission for each student for that phase ([`denis/utilities.py#L13`](denis/utilities.py)).
        *   Creates a named Git tag (e.g., `assignment_component_username`) pointing to the canonical submission tag ([`denis/utilities.py#L41`](denis/utilities.py)).
        *   Assigns peer reviews and records them in `denis.db` ([`denis/initial.py`](denis/initial.py)).
        *   **Potentially runs more extensive, assignment-specific automated tests/checks.**
        *   **Writes results of these checks to `git notes` in a separate namespace (e.g., `refs/notes/denis`).**
5.  **Peer Review Submission (`mailman`):**
    *   Students submit peer reviews via email, replying to the original submission notification.
    *   `mailman` processes these, applies them as patches to the relevant branch/tag in `grading.git`, creates `Gradeable` entries (`review1`, `review2`), and potentially adds notes ([`mailman/submit.py#L76`](mailman/submit.py), [`mailman/patchset.py#L100`](mailman/patchset.py)).
6.  **Manual Grading:**
    *   Graders clone/fetch the `grading.git` repository.
    *   They check out the named tags (e.g., `assignment_component_username`).
    *   They review the code and existing automated feedback in `git notes` (`git notes --ref=mailman show <commit>`, `git notes --ref=denis show <commit>`).
    *   **Graders add their qualitative feedback and scores using `git notes` in their own namespace (e.g., `git notes --ref=grader add -m "Score: 85/100. Good work, minor issues..." <commit>`).**
    *   Graders push the notes refs (`refs/notes/grader`) back to the central repository.
7.  **Feedback Display (`orbit`):**
    *   The student views their `Dashboard` ([`orbit/radius.py#L562`](orbit/radius.py)).
    *   `orbit` fetches/reads the relevant commit/tag for the student's submission.
    *   `orbit` reads `git notes` from all relevant namespaces (`mailman`, `denis`, `grader`).
    *   **Before the final deadline/grading completion:** `orbit` displays only a summarized status based on notes (e.g., "Submitted", "Warning: Automated checks failed", "Error: Submission corrupt"). This encourages students to debug based on high-level feedback without revealing exact solutions.
    *   **After the final deadline/grading completion:** `orbit` displays the full feedback from all sources (automated checks details, grader comments, final score).

---

## 2. Operations-Facing Documentation

### 2.1. Deployment Guide

**Development vs. Production:**

*   **Development:** Use `podman-compose up -d`. Access services via `socat` using `./dev_sockets.sh &`. Uses self-signed certificates. Live editing of web content might be enabled if `COMPOSE_FILE` includes `container-compose-dev.yml` ([`README.md`](README.md): Section 5).
*   **Production:**
    1.  **Configure Hostname:** Edit the `.env` file to set `SINGULARITY_HOSTNAME` and potentially other environment variables (e.g., `MATRIX_HOSTNAME`). Alternatively, use a forked `podman-compose` that respects environment variable overrides ([`README.md`](README.md): Section 6).
    2.  **Build & Launch:** `podman-compose build && podman-compose up -d` (ensure `COMPOSE_FILE` does *not* include dev overrides).
    3.  **SSL Certificates:** Obtain valid SSL certificates (e.g., via Let's Encrypt/certbot). Create a `.tar` file containing `fullchain.pem` and `privkey.pem`. Import them into the Nginx SSL volume: `podman volume import singularity_ssl-certs /path/to/certs.tar`. Reload Nginx: `podman-compose exec nginx nginx -s reload` ([`README.md`](README.md): Section 6).
    4.  **Port Exposure:** Expose services to the internet.
        *   **Option A (Simple):** Run `sudo ./dev_sockets.sh &` on the host to map standard ports (443, 465, 995) directly to the application's Unix sockets ([`README.md`](README.md): Section 6). Requires `socat`.
        *   **Option B (Reverse Proxy):** Configure an existing reverse proxy on the host (e.g., Nginx, Apache, Caddy) to proxy external ports (443, 465, 995, potentially 8448 for Matrix federation) to the Unix sockets located in the `socks/` directory within the project structure on the host.

### 2.2. Configuration Management

*   **Environment Variables (`.env`):**
    *   `SINGULARITY_HOSTNAME`: Public hostname for web, email, git.
    *   `MATRIX_HOSTNAME`: Public hostname for the Matrix server.
    *   (Other variables might be defined for database paths, etc., if customized).
*   **Orbit Configuration (`orbit/config.py`):**
    *   `version_info`: Application version string.
    *   `doc_root`: Filesystem path for Markdown documentation files.
    *   `doc_header`: Path to the HTML header file ([`orbit/header.html`](orbit/header.html)).
    *   `minutes_each_session_token_is_valid`: Session duration.
    *   `num_bytes_entropy_for_pw`: Entropy for password generation (if applicable).
*   **Nginx Configuration (`extenginx/` or `nginx_snippets/`):**
    *   Configuration is built from snippets included in various contexts (http, server, mail). See READMEs within those directories (e.g., [`extenginx/include.d/README.md`](extenginx/include.d/README.md)). Modify/add `.conf` files here to customize Nginx behavior (e.g., add location blocks, change proxy settings). Reload Nginx after changes (`podman-compose exec nginx nginx -s reload`).
*   **Synapse Configuration (`submatrix/homeserver.yaml.template` -> `/etc/synapse/homeserver.yaml`):**
    *   `server_name`: Set via `${MATRIX_HOSTNAME}`.
    *   `database`: Path to Synapse SQLite DB.
    *   `media_store_path`: Path for Matrix media storage.
    *   `signing_key_path`: Path to Matrix signing key.
    *   `modules`: Enables the [`OrbitAuthProvider`](submatrix/orbit_auth.py).
*   **Database Paths:** Hardcoded in Python DB modules ([`orbit/db.py`](orbit/db.py), [`mailman/db.py`](mailman/db.py), [`denis/db.py`](denis/db.py)). Typically mounted as volumes defined in `podman-compose.yml`.

### 2.3. Monitoring & Alerting Guide

*   **Basic Monitoring:**
    *   Monitor container health: `podman ps`, `podman-compose ps`.
    *   Check container logs: `podman-compose logs <service_name>` (e.g., `orbit`, `nginx`, `mailman`). Orbit logs errors from `cgit` to stderr ([`orbit/radius.py#L687`](orbit/radius.py)).
    *   Monitor resource usage (CPU, Memory, Disk I/O) of containers and the host.
    *   Monitor disk space for volumes (databases, Git repos, Matrix media).
*   **Service-Specific Monitoring:**
    *   **Nginx (`extenginx`):** Monitor HTTP error rates (4xx, 5xx), request latency. Check Nginx error logs (`podman-compose logs nginx`).
    *   **Orbit:** Monitor application-level errors in logs, response times for key endpoints (`/login`, `/dashboard`).
    *   **Databases:** Monitor disk space. For SQLite, monitoring is limited; ensure regular backups.
    *   **Mailman/SMTP:** Monitor mail queue length (if applicable), processing errors in `mailman` logs. Check for failed patch applications ([`mailman/patchset.py#L88`](mailman/patchset.py)).
    *   **Git:** Monitor disk usage for repositories.
    *   **Synapse:** Monitor Matrix federation status (if enabled), registration/login success rates, database size, media storage size.
*   **Alerting:** Set up alerts based on:
    *   Container crashes or restarts.
    *   High HTTP error rates (e.g., >1% 5xx errors).
    *   High resource utilization (CPU, memory).
    *   Low disk space on critical volumes.
    *   Specific error messages in logs (e.g., database connection errors, mail processing failures).

### 2.4. Runbooks / Playbooks (Common Operational Tasks)

*   **Restarting a Service:**
    `podman-compose restart <service_name>` (e.g., `orbit`, `nginx`)
*   **Restarting All Services:**
    `podman-compose restart`
*   **Viewing Logs:**
    `podman-compose logs <service_name>`
    `podman-compose logs -f <service_name>` (follow logs)
*   **Updating SSL Certificates:**
    1.  Obtain new `fullchain.pem` and `privkey.pem`.
    2.  Create tarball: `tar cvf new_certs.tar fullchain.pem privkey.pem`
    3.  Import volume: `podman volume rm singularity_ssl-certs && podman volume create singularity_ssl-certs && podman volume import singularity_ssl-certs new_certs.tar` (Ensure correct volume name from `podman volume ls`)
    4.  Reload Nginx: `podman-compose exec nginx nginx -s reload`
*   **Applying Nginx Configuration Changes:**
    1.  Modify `.conf` files in `nginx_snippets/` or `extenginx/include.d/`.
    2.  Check syntax: `podman-compose exec nginx nginx -t`
    3.  Reload Nginx: `podman-compose exec nginx nginx -s reload`
*   **Database Backup:**
    *   Identify volume paths: `podman volume inspect <volume_name>` (e.g., `singularity_orbit-db`, `singularity_mailman-db`, `singularity_denis-db`, `singularity_synapse-data`)
    *   Stop containers: `podman-compose down` (or stop individual services accessing the DB)
    *   Copy SQLite files from their volume mount points on the host. (Or use `backup/backup.sh` if it's designed for this).
    *   Restart containers: `podman-compose up -d`
*   **Database Restore:**
    *   Stop containers: `podman-compose down`
    *   Replace SQLite files in volume mount points with backup files. (Or use `backup/restore.sh`).
    *   Restart containers: `podman-compose up -d`
*   **Adding/Managing Assignments:**
    *   Define assignment metadata and deadlines using `denis/configure.py` ([`denis/configure.py`](denis/configure.py)) which updates the `denis` database.
    *   Ensure corresponding email addresses/aliases are configured if needed (likely handled by mail server config based on `SINGULARITY_HOSTNAME`).
    *   Schedule `denis` scripts (`initial.py`, `peer_review.py`, `final.py`) to run at appropriate due dates.
*   **Creating Git Repositories:**
    *   The central `grading.git` repository is typically created once during initial setup. Student-specific repos are not used in this workflow; submissions are applied to the central repo.
*   **Inspecting Submissions/Gradeables:**
    *   Use `mailman/inspector.py` for database queries ([`mailman/inspector.py`](mailman/inspector.py)):
        *   `./inspector.py submissions -a <assignment> -u <user>`
        *   `./inspector.py gradables -a <assignment> -u <user> -c <component>`
        *   `./inspector.py missing -a <assignment>`
        *   `./inspector.py oopsie -a <assignment> -u <user>`
    *   Inspect Git tags and notes directly in the `grading.git` repository clone:
        *   `git tag` (list all tags)
        *   `git show <tag_name>` (show commit associated with a tag)
        *   `git notes --ref=<namespace> list` (list commits with notes in a namespace)
        *   `git notes --ref=<namespace> show <commit_or_tag>` (show notes for a commit)
*   **Manual Grading Actions (Example):**
    *   `git clone <grading_repo_url>`
    *   `cd grading`
    *   `git fetch --all --tags --prune`
    *   `git checkout <assignment>_<component>_<username>`
    *   *(Review code)*
    *   `git notes --ref=mailman show HEAD` *(Review mailman feedback)*
    *   `git notes --ref=denis show HEAD` *(Review denis feedback, if any)*
    *   `git notes --ref=grader add -m "Score: 90/100. Comments..." HEAD`
    *   `git push origin refs/notes/grader`
*   **Cleaning Up Test Data:**
    *   After running `./test.sh`, containers/volumes might be modified.
    *   Stop containers: `podman-compose down`
    *   Remove potentially modified volumes: `podman volume prune` (removes *all* unused volumes) or `podman volume rm singularity_orbit-db singularity_mailman-db ...` (list specific volumes used by the project - see `podman volume ls`). ([`README.md`](README.md): Section 3)
