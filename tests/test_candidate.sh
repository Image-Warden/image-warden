#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers/assertions.sh
source "${TEST_DIR}/helpers/assertions.sh"
iw_test_init

export STATE_DIR="${XDG_STATE_HOME}/image-warden"

source "${IW_TEST_ROOT}/lib/common.sh"
source "${IW_TEST_ROOT}/lib/validate.sh"
source "${IW_TEST_ROOT}/lib/candidate.sh"

digest="sha256:2222222222222222222222222222222222222222222222222222222222222222"
hash_trivy="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
hash_grype="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

_iw_candidate_write "app" "docker.io/library/nginx:stable" "stable_20260524-1200_22222222" "$digest" "1779626246" "72"
file="$(_iw_candidate_file "app" "$digest")"
assert_file_exists "$file"

_iw_candidate_read "$file"
assert_eq "stable_20260524-1200_22222222" "$_CAND_TAG" "candidate tag"
assert_eq "$digest" "$_CAND_DIGEST" "candidate digest"
assert_eq "72" "$_CAND_QUARANTINE_HOURS_AT_STAGE" "quarantine hours"

_iw_candidate_set_scanner_report_hash "app" "$digest" "trivy" "$hash_trivy"
_iw_candidate_set_scanner_report_hash "app" "$digest" "grype" "$hash_grype"

assert_eq "$hash_trivy" "$(_iw_candidate_get_scanner_report_hash "$file" trivy)" "trivy hash"
assert_eq "$hash_grype" "$(_iw_candidate_get_scanner_report_hash "$file" grype)" "grype hash"

legacy="${STATE_DIR}/candidates/app/legacy.json"
cat > "$legacy" <<EOF
{
  "local_name": "app",
  "upstream": "docker.io/library/nginx:stable",
  "tag": "stable_20260524-1200_22222222",
  "digest": "$digest",
  "staged_at": 1779626246,
  "quarantine_hours_at_stage": 72,
  "trivy_blocked_report_hash": "$hash_trivy"
}
EOF

assert_eq "$hash_trivy" "$(_iw_candidate_get_scanner_report_hash "$legacy" trivy)" "legacy trivy hash fallback"

corrupt="${STATE_DIR}/candidates/app/corrupt.json"
printf '{bad\n' > "$corrupt"
run_cmd _iw_candidate_read "$corrupt"
assert_failure "$IW_LAST_STATUS" "corrupt candidate should fail"
