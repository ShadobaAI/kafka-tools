---
name: task-orchestration
description: Coordinate bounded independent work and fresh review for large Kafka tasks; skip for small scoped changes.
---

# Task orchestration

Use only when the task has separable workstreams, spans repositories, needs substantial independent research, or benefits materially from a fresh reviewer. Follow the current user's delegation preference; do not spawn workers by default for a small change.

Give each worker only `goal`, `scope`, `known_facts`, `constraints`, `authoritative_sources`, and `expected_output`. Require `conclusion`, `evidence`, `risks`, and `unknowns` back. Keep each worker within the assigned repository and authority route. Do not import a full transcript into the main context.

For public API, schema, multi-repository, or complex logic changes, request a fresh read-only review of acceptance criteria, selected requirements, diff, and validation evidence. The reviewer must not infer that passing tests proves normative compliance. Resolve findings in the implementation phase, then verify changed work. Put durable results in the owning SDD/ADR/docs; use a bounded `kfk-tasks/work` handoff only across task or developer boundaries.
