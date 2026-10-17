# Import payloads exist only in this private directory until the hook exits.
umask 077
private_import_dir="$(mktemp -d)"
trap 'rm -rf "$private_import_dir"' EXIT
