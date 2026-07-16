# Change log

Every deviation from documented box state, captured **when it happens** — not
reconstructed at layer close. The rule: if a command changes a box's durable
state, it gets a line here AND the relevant provisioning script is edited in the
same commit. This is the manual version of the L5 learning-capture hook.

Distinct from docs/failure-log.md (failures + fixes) and docs/architecture.md
(state at each layer close). This log is the running delta between them.

| Date | Box | Change | Why | Provisioning updated? |
|------|-----|--------|-----|----------------------|
| 16 Jul | controller | Installed Docker Engine + compose plugin | L2 makes the controller a container host (Langfuse + LiteLLM); L0/L1 only needed tinyproxy, so provision-controller.sh predated container-hosting | Yes — Docker block added to provision-controller.sh |
