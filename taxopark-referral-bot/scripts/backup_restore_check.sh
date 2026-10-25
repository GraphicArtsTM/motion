#!/usr/bin/env bash
# TC-111: бэкап создаётся и восстанавливается на тестовом стенде.
#   SOURCE_URL=postgresql://user:pass@host:5432/referral  RESTORE_URL=postgresql://user:pass@host:5432/postgres \
#   scripts/backup_restore_check.sh
set -euo pipefail
: "${SOURCE_URL:?}" "${RESTORE_URL:?}"
DUMP="$(mktemp -d)/referral.dump"
CHECK_DB="referral_restore_check_$(date +%s)"
TABLES="users referrals accruals withdrawals wallet_ledger orders periods qualifications audit_log settings"

pg_dump --format=custom --file="$DUMP" "$SOURCE_URL"
psql "$RESTORE_URL" -qc "CREATE DATABASE $CHECK_DB"
TARGET_URL="${RESTORE_URL%/*}/$CHECK_DB"
pg_restore --no-owner --dbname="$TARGET_URL" "$DUMP"

status=0
for t in $TABLES; do
  a=$(psql "$SOURCE_URL" -Atc "SELECT count(*) FROM $t")
  b=$(psql "$TARGET_URL" -Atc "SELECT count(*) FROM $t")
  if [ "$a" = "$b" ]; then echo "OK   $t: $a"; else echo "FAIL $t: $a != $b"; status=1; fi
done
a=$(psql "$SOURCE_URL" -Atc "SELECT coalesce(sum(balance_available),0) || '/' || coalesce(sum(debt),0) FROM users")
b=$(psql "$TARGET_URL" -Atc "SELECT coalesce(sum(balance_available),0) || '/' || coalesce(sum(debt),0) FROM users")
[ "$a" = "$b" ] && echo "OK   balances: $a" || { echo "FAIL balances: $a != $b"; status=1; }
psql "$RESTORE_URL" -qc "DROP DATABASE $CHECK_DB"
exit $status
