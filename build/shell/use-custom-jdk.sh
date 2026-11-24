#!/bin/bash
set -e

bundled_jdk=
for script in "$JJOBS_BASE"/start_{manager,server,agent}.sh; do
  [ -f "$script" ] || continue
  bundled_jdk=$(sed -n -E '/^export (JRE_HOME|JAVA_HOME)=/{s/^[^=]*=//;p;q;}' "$script")
  [ -z "$bundled_jdk" ] || break
done
bundled_jdk=${bundled_jdk%/}
if [ "${bundled_jdk%/*}" != "${JJOBS_BASE%/}" ] || [ ! -x "$bundled_jdk/bin/java" ]; then
  echo "Bundled JDK directory not found under $JJOBS_BASE" >&2
  exit 1
fi

custom_jdk="$JJOBS_BASE/.custom-jdk"
if [ -L "$bundled_jdk" ]; then
  if [ "$(readlink -- "$bundled_jdk")" = "$custom_jdk" ]; then
    echo "Custom JDK already applied: $bundled_jdk -> $custom_jdk"
    exit 0
  fi
  echo "Unexpected JDK symlink: $bundled_jdk" >&2
  exit 1
fi

archive=/JDKs/jdk.tar.gz
staging_dir=$(mktemp -d "$JJOBS_BASE/.jdk-staging.XXXXXX")
trap 'rm -rf -- "$staging_dir"' EXIT
staged_jdk="$staging_dir/jdk"
mkdir "$staged_jdk"
tar -xzf "$archive" -C "$staged_jdk" --strip-components=1
if [ ! -x "$staged_jdk/bin/java" ]; then
  echo "Executable bin/java not found in $archive (expected a single top-level JDK directory)" >&2
  exit 1
fi
"$staged_jdk/bin/java" -version

security_file="$staged_jdk/conf/security/java.security"
if [ ! -f "$security_file" ]; then
  security_file="$staged_jdk/jre/lib/security/java.security"
fi
if [ ! -f "$security_file" ]; then
  echo "java.security not found in $archive (expected conf/security or jre/lib/security)" >&2
  exit 1
fi

for security_property in "networkaddress.cache.ttl=${NETWORKADDRESS_CACHE_TTL:-1}" \
                         "networkaddress.cache.negative.ttl=${NETWORKADDRESS_CACHE_NEGATIVE_TTL:-3}"; do
  security_key=${security_property%%=*}
  security_pattern=${security_key//./\\.}
  if grep -Eq "^[[:space:]#]*${security_pattern}[[:space:]]*=" "$security_file"; then
    sed -i "s/^[[:space:]#]*${security_pattern}[[:space:]]*=.*/${security_property}/" "$security_file"
  else
    printf '\n%s\n' "$security_property" >> "$security_file"
  fi
done

rm -rf -- "$custom_jdk"
mv -- "$staged_jdk" "$custom_jdk"
backup_dir=$(mktemp -d "$JJOBS_BASE/.jdk-backup.XXXXXX")
mv -- "$bundled_jdk" "$backup_dir/"
if ! ln -sT -- "$custom_jdk" "$bundled_jdk"; then
  mv -- "$backup_dir/${bundled_jdk##*/}" "$bundled_jdk"
  rmdir -- "$backup_dir"
  exit 1
fi
rm -rf -- "$backup_dir"
