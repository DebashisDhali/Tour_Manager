# Tour Cost: Scalability + Security Blueprint

## Objective
Build the system so product growth does not require risky rewrites. The target is resilient architecture, predictable performance, and strong user-data security.

## Reality Check
- 500M to 1B active downloads cannot be handled by a single Node API + single relational DB instance.
- The current codebase is a good offline-first foundation, but must evolve to a distributed architecture.

## Recommended System Architecture
1. Edge/API layer
- API Gateway + WAF (Cloudflare/AWS API Gateway)
- JWT validation at edge for cheap reject path
- Request shaping and IP/device throttling

2. Service layer (split from monolith)
- Auth Service
- Tour Service
- Expense/Settlement Service
- Search Service
- Notification Service
- Sync Orchestrator

3. Data layer
- Postgres (partitioned + read replicas) for transactional data
- Redis for cache/session/rate-limit counters
- Kafka (or Pub/Sub) for event streaming and async fanout
- Elasticsearch/OpenSearch for global text search (tours/profiles)
- Object storage for media/attachments

4. Observability layer
- OpenTelemetry traces
- Prometheus/Grafana metrics
- Centralized logs with PII redaction

## Data Structures and Algorithms

### A) Expense Settlement at Scale
- Current greedy cash-flow minimization is good and near-optimal for practical use.
- Keep two priority queues (max-heap creditor, max-heap debtor by absolute balance).
- Complexity: O(n log n), stable for large groups.

### B) Search
- Use inverted index (Elasticsearch/OpenSearch) for name, tour title, invite metadata.
- Use trigram/similarity for fuzzy matching.
- Use prefix index for fast autocomplete.
- Keep local on-device Drift search for offline mode only.

### C) Feed and Sync
- Use append-only event log + per-user cursor (monotonic sequence ID).
- Delta sync should be cursor-based, not timestamp-only.
- Conflict resolution: per-entity vector/lamport version field + server tie-break.

### D) Hot Path Caching
- Redis key patterns:
	- user:{id}:profile
	- tour:{id}:summary
	- tour:{id}:members:active
	- invite:{code}:tourId
- Use write-through or explicit invalidation via event bus.

### E) Rate Limiting
- Sliding window/token bucket in Redis.
- Per-IP + per-user + per-device fingerprint dimensions.

## Security Architecture
1. Auth/token
- Short-lived access token (10-15 min) + rotating refresh token
- Store refresh token family with revocation list
- Add jti claim for replay defense

2. Data protection
- TLS everywhere
- Encryption at rest
- Field-level encryption for sensitive data if needed
- Strict secret management (Vault/SSM), no fallback secrets

3. Application security
- Input schema validation at all write endpoints
- RBAC + ABAC for cross-tour access checks
- Prevent IDOR by binding user identity server-side
- Security headers + strict CORS allowlist

4. Abuse and fraud
- Progressive bot defense for auth endpoints
- Device risk scoring for suspicious activity
- Audit log for role changes, joins, deletions

## Database Scaling Strategy
1. Immediate
- Add missing indexes on join and lookup columns
- Remove unbounded wildcard queries from hot APIs

2. Mid-term
- Partition large tables by tenant/tour/date
- Add read replicas and route read-heavy endpoints
- Use background jobs for heavy retroactive operations

3. Long-term
- Shard by tenant/org or geographic region
- Multi-region active-active with async replication for non-critical reads

## Mobile App (Flutter) Scaling Strategy
1. Keep offline-first
- Continue Drift as local source of truth
- Keep sync chunked and resumable

2. Bounded memory/CPU
- Pagination + lazy rendering in all long lists
- Avoid full-table scans in UI isolate
- Debounce + cancel stale requests for search

3. Crash resilience
- Global error boundary + crash reporting
- Strict timeout/retry/backoff with jitter in network layer

## SLOs (initial)
- p95 API latency < 250ms (read), < 500ms (write)
- 99.95% monthly availability
- sync failure rate < 0.5%
- crash-free sessions > 99.8%

## Rollout Plan
1. Phase 1 (now)
- Security hardening and input validation
- DB index coverage and route locking
- Observability baseline

2. Phase 2
- Redis cache + distributed rate limits
- Async job queue for expensive workflows
- Cursor-based sync

3. Phase 3
- Search service extraction
- Service decomposition and event-driven integration

4. Phase 4
- Regionalization, read replicas, and shard strategy

## Definition of Done for "Internet Scale Ready"
- Load-tested with realistic user behavior and sync traffic
- Chaos-tested for node/DB/cache failures
- Security-tested (SAST, DAST, dependency scan, pen-test)
- Disaster recovery drills passed (RPO/RTO targets)
