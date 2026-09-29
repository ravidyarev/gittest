# Power BI CI/CD Demo Script — DEV → TEST

A step-by-step run sheet for live-demoing the working Path C setup. This assumes everything in `POWERBI-CICD-DEV-TEST.md` is already configured and confirmed working (Git integration, `AZURE_CREDENTIALS`, `WORKSPACE_ID`, `PIPELINE_ID`, service principal access). This document is just the **sequence of actions to perform live**, plus what to point at on screen at each step.

---

## 0. Pre-demo checklist (do this before your audience joins)

Run through this once, silently, so the demo itself has no surprises.

- [ ] Confirm `development` branch has no pending/uncommitted changes and matches DEV workspace (check **Workspace settings → Git integration** shows "up to date").
- [ ] Confirm TEST workspace currently does **not** have today's demo change yet — this is the "before" state your audience should see.
- [ ] Have four browser tabs open and ready:
  1. GitHub repo → **Code** tab, on `development` branch
  2. GitHub repo → **Actions** tab
  3. Power BI Service → **DEV workspace**
  4. Power BI Service → **Deployment pipelines** → your pipeline (showing Dev/Test side by side)
- [ ] Have the report open in Power BI Desktop (or ready to edit a `.Report`/`.SemanticModel` file directly), connected to a local clone of the repo.

---

## 1. Show the "before" state (30 seconds)

Talk track: *"Here's our DEV workspace and TEST workspace side by side. Right now they're identical / TEST doesn't have today's change yet."*

- Tab 3 (DEV workspace): open the report, point at the item you're about to change.
- Tab 4 (Deployment pipelines): show the Dev and Test stages — note the "Last deployment" timestamp on Test, and that Power BI shows no pending differences yet.

---

## 2. Make a change and push it to `development`

1. In your local clone, create a feature branch:
   ```powershell
   git switch development
   git pull
   git switch -c demo-change
   ```
2. Make a small, visible edit — e.g. rename a report title, or change a measure's description in `ActorReportPass.Report/` or `ActorReportPass.SemanticModel/`.
3. Commit and push:
   ```powershell
   git add -A
   git commit -m "Demo: update report title"
   git push -u origin demo-change
   ```
4. On GitHub (Tab 1), open a **Pull Request**: base = `development`, compare = `demo-change`.
5. **Merge the PR.**

Talk track while merging: *"This merge is the trigger. GitHub fires a `push` event on `development`, and that's what our sync workflow is listening for."*

---

## 3. Watch the DEV sync run (GitHub Actions)

1. Switch to Tab 2 (**Actions**). A new run of **"Sync Dev workspace from Git"** should appear within a few seconds — refresh if needed.
2. Click into the run → click the `sync` job → expand the steps live as they go green:
   - **Get access token** — point out this is where the service principal authenticates using `AZURE_CREDENTIALS`.
   - **Trigger updateFromGit** — expand this and narrate: *"First it calls Fabric's `git/status` to get the commit hashes, then calls `updateFromGit` with those hashes — Fabric requires the exact commit hashes, not just a bare request. Fabric also requires us to explicitly allow overriding items, which is the `allowOverrideItems: true` flag you can see in the request body."*
   - Point out the `Response body:` and `Status code:` log lines — a `200`/`202` confirms Fabric accepted the sync.

---

## 4. Confirm the DEV workspace updated

1. Switch to Tab 3 (**DEV workspace**). Refresh the report/model — your edit should now be visible.
2. Open **Workspace settings → Git integration** and point out the "last synced" commit now matches your merge commit.

Talk track: *"Git is now the source of truth for DEV — nothing was published manually from Desktop. The workflow pulled it in."*

---

## 5. Promote DEV → TEST

1. Back on GitHub (Tab 1), open a **Pull Request**: base = `main`, compare = `development`.
2. **Merge the PR.**

Talk track while merging: *"This is the promotion trigger. A push to `main` fires our second workflow, which doesn't touch git content at all — it just tells Power BI's deployment pipeline to copy the current DEV workspace into TEST."*

*(Alternative if you don't want to wait for a natural push: Tab 2 → **Actions** → "Promote Dev to Test" → **Run workflow** → run manually via `workflow_dispatch`. Narrate that this calls the exact same code path.)*

---

## 6. Watch the promotion run

1. Tab 2 (**Actions**) → new run of **"Promote Dev to Test"** appears.
2. Open it → expand steps:
   - **Get access token** — same pattern, different scope (`analysis.windows.net/powerbi/api/.default` this time, since this call is against the Power BI REST API rather than Fabric's).
   - **Trigger deployment (Dev -> Test)** — expand and narrate: *"This calls `deployAll` with `sourceStageOrder: 0`, meaning 'deploy everything out of the Development stage.' We also pass `allowCreateArtifact` and `allowOverwriteArtifact` so it can create items in Test the first time and overwrite them on every subsequent run."*
3. Point out a `202 Accepted` response and explain: *"This means Power BI accepted the job — deployment itself runs asynchronously, so we verify completion in the UI, not in this log."*

---

## 7. Confirm in Power BI Service

1. Tab 4 (**Deployment pipelines**): refresh — the Test stage's "Last deployment" timestamp should now show just now, and the Dev/Test comparison should show **in sync**.
2. Tab 3 → open the **TEST workspace** directly, refresh, and show the same title/description change is now present there too.

Talk track to close: *"That's the full loop — a change merged into `development` synced automatically into DEV, and a merge into `main` promoted DEV's current state into TEST. No manual publish, no manual deployment click — both steps were driven entirely by the git merges."*

---

## Quick troubleshooting reference (condensed)

| Symptom during a live demo | Likely cause | Fast check |
|---|---|---|
| Sync workflow doesn't appear in Actions at all | PR was merged into the wrong base branch, or workflow file isn't on `development` | Confirm PR base was `development`; confirm `.github/workflows/sync-dev.yml` exists on that branch |
| `Get access token` step fails / empty token | `AZURE_CREDENTIALS` missing or malformed in the `dev`/`test` environment | Settings → Environments → confirm the JSON secret exists with `tenantId`, `clientId`, `clientSecret` |
| `updateFromGit` returns `GitCredentialsNotConfigured` | Service principal's own Fabric Git connection isn't set up | Re-run `.github/scripts/configure-fabric-github-credentials.ps1` |
| Promotion succeeds (green) but TEST doesn't change | DEV workspace itself doesn't have the new content yet | Confirm Step 4 above actually completed before running Step 5 |
| `Alm_InvalidRequest_NoArtifactsToDeploy` | Used `/deploy` (selective) instead of `/deployAll` | Confirm workflow calls `deployAll` |

For anything not covered here, see the full troubleshooting table in `POWERBI-CICD-DEV-TEST.md` (Section 7).
