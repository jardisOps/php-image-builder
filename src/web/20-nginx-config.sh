# shellcheck shell=dash
# ---------------------------------------------------------------------------
# 20-nginx-config.sh — target addition for the web image
# ---------------------------------------------------------------------------
# Renders the shared vhost template into nginx's config dir, replicating what
# the official nginx image's envsubst step does in the sidecar pattern.
#
# Defaults come from the baked nginx-defaults.env; a variable already set in
# the environment wins (same precedence direction as the PHP values). Only
# the variables named in the defaults file are substituted, so nginx runtime
# variables ($uri, $realpath_root, ...) pass through untouched.
#
# Expected from the core: log_info/die
# ---------------------------------------------------------------------------

NGINX_TEMPLATE='/etc/nginx/templates/default.conf.template'
NGINX_DEFAULTS='/etc/nginx/nginx-defaults.env'
NGINX_CONF_OUT='/etc/nginx/http.d/default.conf'

[ -f "$NGINX_TEMPLATE" ] || die "nginx template missing: $NGINX_TEMPLATE"
[ -f "$NGINX_DEFAULTS" ] || die "nginx defaults missing: $NGINX_DEFAULTS"

_ng_vars=''
while IFS= read -r _ng_line; do
    case "$_ng_line" in
        [A-Z_]*=*) ;;
        *) continue ;;
    esac
    _ng_key=${_ng_line%%=*}
    _ng_default=${_ng_line#*=}
    eval "_ng_current=\${$_ng_key:-}"
    if [ -z "$_ng_current" ]; then
        eval "$_ng_key=\$_ng_default"
    fi
    # shellcheck disable=SC2163  # exporting the variable NAMED in _ng_key is the point
    export "$_ng_key"
    _ng_vars="$_ng_vars \${$_ng_key}"
done < "$NGINX_DEFAULTS"

envsubst "$_ng_vars" < "$NGINX_TEMPLATE" > "$NGINX_CONF_OUT"

# Fail at start, not at first request: a template/values mismatch must abort
# the container visibly (no silent swallowing).
nginx -t -q || die "rendered nginx config failed 'nginx -t' — see output above"

log_info "nginx vhost rendered: upstream ${FASTCGI_UPSTREAM}:${PHP_PORT}, root ${APP_ROOT}${DOCUMENT_ROOT}"
