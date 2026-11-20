# shellcheck shell=dash
# ---------------------------------------------------------------------------
# 15-web-runtime.sh — target addition for the web image
# ---------------------------------------------------------------------------
# Prepares WEB_RUNTIME_DIR, the one place this target writes to: nginx's
# pid/log/temp directories and the s6 scan directory. The image links the
# fixed paths (/run/nginx, /var/log/nginx, /etc/s6, ...) into it, so a
# read-only root filesystem needs a single writable mount here.
#
# Expected from the core: log_info/die
# ---------------------------------------------------------------------------

S6_SERVICE_DIR='/etc/s6.d'

: "${WEB_RUNTIME_DIR:?is not set — this value must come as an ENV from the image (src/web/Dockerfile).}"

_wr_hint="$WEB_RUNTIME_DIR is not writable for UID $(id -u). On a read-only root filesystem mount a writable volume there (tmpfs/emptyDir); without one, run as root or as $APP_USER."

# The image ships the directory owned by APP_USER so the non-root start can
# write to it. Under the root start that would let the PHP worker swap the
# scan directory s6 runs as root - so root takes it back before anything runs.
if [ "$(id -u)" = '0' ]; then
    chown root:root "$WEB_RUNTIME_DIR" \
        || die "Could not transfer $WEB_RUNTIME_DIR to root."
fi

mkdir -p "$WEB_RUNTIME_DIR/nginx/run" "$WEB_RUNTIME_DIR/nginx/log" "$WEB_RUNTIME_DIR/nginx/tmp" \
    || die "$_wr_hint"

# s6 writes locks, FIFOs and status files next to the service definitions.
# The scan directory is therefore rebuilt here on every start: real
# directories, with links to the read-only run/finish scripts in the image.
# Links, not copies, so the writable mount needs no exec permission.
rm -rf "$WEB_RUNTIME_DIR/s6" || die "$_wr_hint"

for _wr_src in "$S6_SERVICE_DIR"/.s6-svscan "$S6_SERVICE_DIR"/*; do
    [ -d "$_wr_src" ] || continue
    _wr_dst="$WEB_RUNTIME_DIR/s6/$(basename "$_wr_src")"
    mkdir -p "$_wr_dst" || die "$_wr_hint"
    for _wr_file in "$_wr_src"/*; do
        [ -e "$_wr_file" ] || continue
        ln -s "$_wr_file" "$_wr_dst/" || die "Could not link $_wr_file into $_wr_dst."
    done
done

log_info "web runtime directory prepared: $WEB_RUNTIME_DIR"
