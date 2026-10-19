# Owner Interview Answers Q-143–Q-152

Status: Recorded — pending formal transcription into `01`, `05`, `07`, `08`, and `09`
Date: 2026-10-20

This addendum preserves owner answers that are not yet reflected in the main answer table. It does not replace the requirement, decision, or quality documents.

| ID | Owner answer | Impact / follow-up |
|---|---|---|
| Q-143 | Accepts the 1.0 performance gates: pen-to-photon P95 < 50 ms, 20,000 strokes/page, 500 pages, cold start < 3 s, standard document open < 2 s, page turn P95 < 150 ms, Android peak memory < 1 GB, desktop peak memory < 2 GB, Android APK < 150 MB, desktop installer < 200 MB. After Phase 0 measurements these gates may only be tightened, not relaxed. | Add the new gates to `05-quality-and-test-strategy.md`; baseline devices still need concrete models (Q-140b). |
| Q-144 | Accepts the risk-based definition of complete unit and integration tests: C++ ≥ 80% line coverage, key native modules ≥ 85% branch coverage, Dart ≥ 70%; all critical paths require integration tests; pen, PDF, EPUB, and save/recovery require real-device manual acceptance; every S0/S1 fix requires a regression test. Coverage alone is not correctness. | Encode in `05` and `08`; keep manual acceptance records in reports. |
| Q-145 | Accepts basic fuzzing plus targeted security cases for corrupt `.meowo`, malicious PDF/EPUB, oversized images, path traversal, and HTML injection. No third-party security audit in 1.0; residual risk must be disclosed in release notes. | Add fuzz targets and security corpus requirements to `05`; document the no-audit limitation. |
| Q-146 | Originally chose automated accessibility scans only. | Conflicts with the earlier screen-reader and keyboard commitments; see Q-146b. |
| Q-146b | Confirms the downgrade: accessibility acceptance is automated scans only. 1.0 no longer promises full screen-reader or keyboard-only usability. The earlier Q-016/Q-134 promises must be withdrawn or marked unverified; basic font scaling and high contrast from Q-135 remain. | Update `01` A11Y requirements, `04` accessibility section, `05` test strategy, and release notes. Canvas accessibility is not claimed. |
| Q-147 | GitHub public beta via Pre-release; feedback through GitHub Issues; users manually export redacted diagnostic logs and attach them. No automatic upload or telemetry. | Add beta/feedback process to `05`, `07`, and release checklist; no telemetry code. |
| Q-148 | Strict SemVer; rolling releases after 1.0; no LTS and no fixed release cadence; security and data-corruption fixes take priority. | Add versioning and support policy to `07` and `06`. |
| Q-149 | Owner holds signing keys and GitHub release authority. Agent may draft privacy notes, README, screenshots, and release copy but must not hold keys or publish. No app-store dependency. | Add release-key custody and publication approval to `08`/`07`. |
| Q-150 | Manual “check for updates” that opens GitHub Releases only; no automatic download or install. Linux deb/rpm updates are delegated to the package manager. Back up the database before migration and keep rollback. | Update settings/update UX, `05` migration tests, and release docs. |
| Q-151 | Owner holds the release veto. Any unresolved S0 data-loss/corruption issue blocks release indefinitely. Agents may recommend but cannot declare a release ready. | Encode as a hard release gate in `05`, `06`, and `08`. |
| Q-152 | Collaboration policy: Chinese-first maintenance docs with a bilingual README; Issues/PRs in Chinese or English; DCO; new dependencies, license changes, and format changes require owner approval; agents must not auto-commit, push, or publish; AI-generated code must be reviewed, tested, and disclosed. | Update `07`, `08`, and contribution docs. |

## Still Pending

- Q-140b: exact test-device models, RAM, pen protocol, and ownership.
- Formal transcription of Q-143–Q-152 into the normative documents.
- Q-153 onward.
