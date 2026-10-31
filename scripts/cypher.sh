#!/usr/bin/env bash
# Opens cypher-shell, or runs a file / query.
#   scripts/cypher.sh vg                          # interactive shell on the Virtual Graph
#   scripts/cypher.sh router                      # interactive shell on contracts360
#   scripts/cypher.sh vg examples/vg.cypher       # run a file
#   scripts/cypher.sh router "MATCH ... RETURN"   # run a query
. "$(dirname "$0")/lib.sh"

case "${1:-}" in
  vg)     container=neo4j-vg;     db=neo4j ;;
  router) container=neo4j-router; db=contracts360 ;;
  *)      die "usage: $0 vg|router [file.cypher | query]" ;;
esac

if [[ -z "${2:-}" ]]; then
  docker exec -it "$container" cypher-shell -u neo4j -p "$NEO4J_PASSWORD" -d "$db"
elif [[ -f "$2" ]]; then
  # --fail-at-end: some examples fail on purpose to show preview limits
  cypher "$container" "$db" --format plain --fail-at-end < "$2"
else
  cypher "$container" "$db" --format plain "$2"
fi
