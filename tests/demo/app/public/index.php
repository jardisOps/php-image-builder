<?php

/**
 * Demo application for the stack in tests/demo/demo-stack.yml.
 *
 * Purpose: show that the three parts actually work together — the official
 * nginx with our template, headgent/phpfpm and the official mariadb. It shows
 * only what the stack needs to prove and is not an application skeleton: no
 * dependencies, no autoloader, no framework.
 *
 * NOT A TEMPLATE FOR PRODUCTION CODE. This page deliberately outputs what a
 * real application must keep to itself — the database error message with user
 * and origin IP, the runtime configuration, and the process ID. That is the
 * point: a demo stack that shows a failed connection as an empty field reports
 * success where there is none. Anyone copying from here should drop these
 * outputs.
 *
 * The output is also the measuring point of tests/check-demo-stack.sh. Renaming
 * markers here (PROBE=..., DB=...) requires updating that script too.
 */

declare(strict_types=1);

/** Prefix that marks the output as a failed connection. */
const DB_ERROR_PREFIX = 'ERROR: ';

/**
 * Connects to the demo database and returns its server identifier.
 *
 * On failure, the return value is the error message prefixed with
 * DB_ERROR_PREFIX — callers distinguish on that, not on an empty field.
 */
function databaseVersion(): string
{
    // No default for the credentials: a hardcoded value in code could
    // silently override the configuration. A missing value is reported, not
    // guessed.
    $required = ['DEMO_DB_HOST', 'DEMO_DB_NAME', 'DEMO_DB_USER', 'DEMO_DB_PASSWORD'];

    $config = [];
    $missing = [];
    foreach ($required as $key) {
        $value = getenv($key);
        if ($value === false || $value === '') {
            $missing[] = $key;
            continue;
        }
        $config[$key] = $value;
    }

    if ($missing !== []) {
        return DB_ERROR_PREFIX . 'not set: ' . implode(', ', $missing);
    }

    $dsn = sprintf(
        'mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4',
        $config['DEMO_DB_HOST'],
        getenv('DEMO_DB_PORT') ?: '3306',
        $config['DEMO_DB_NAME'],
    );

    try {
        $pdo = new PDO(
            $dsn,
            $config['DEMO_DB_USER'],
            $config['DEMO_DB_PASSWORD'],
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION],
        );

        return (string) $pdo->query('SELECT VERSION()')->fetchColumn();
    } catch (PDOException $e) {
        return DB_ERROR_PREFIX . $e->getMessage();
    }
}

/** The runtime values set by the image's APP_ENV profile. */
function runtimeFacts(): array
{
    $jit = ini_get('opcache.jit');

    return [
        'PHP'                        => PHP_VERSION,
        'SAPI'                       => PHP_SAPI,
        'APP_ENV'                    => getenv('APP_ENV') ?: '<not set>',
        'opcache.enable'             => ini_get('opcache.enable'),
        'opcache.validate_timestamps' => ini_get('opcache.validate_timestamps'),
        'opcache.jit'                => ($jit === '' || $jit === false) ? '<empty>' : $jit,
        'xdebug.mode'                => extension_loaded('xdebug') ? ini_get('xdebug.mode') : '<not loaded>',
        'pcov.enabled'               => extension_loaded('pcov') ? ini_get('pcov.enabled') : '<not loaded>',
        'max_execution_time'         => ini_get('max_execution_time'),
        'memory_limit'               => ini_get('memory_limit'),
        // posix is present in our images, but not in every PHP build — without
        // this check the whole page would be a fatal error instead of one
        // missing line.
        'Process ID'                 => function_exists('posix_geteuid')
            ? sprintf('%s:%s', posix_geteuid(), posix_getegid())
            : '<posix not loaded>',
    ];
}

/**
 * The $_SERVER values that come from the nginx template.
 *
 * HTTPS is deliberately included: with REQUEST_SCHEME=http, the key must not
 * arrive at all — a fixed "on" here would be wrong without a TLS proxy.
 */
function templateFacts(): array
{
    $keys = [
        'SERVER_NAME', 'REQUEST_SCHEME', 'HTTPS', 'HTTP_X_FORWARDED_PROTO',
        'DOCUMENT_ROOT', 'SCRIPT_FILENAME', 'PATH_INFO', 'REQUEST_URI',
    ];

    $facts = [];
    foreach ($keys as $key) {
        $facts[$key] = $_SERVER[$key] ?? '<not passed>';
    }

    return $facts;
}

$dbVersion = databaseVersion();

// Machine-readable line for the test run. It precedes the HTML so it stays
// reachable independent of any rendering.
header('Content-Type: text/html; charset=utf-8');

?>
<!-- PROBE=demo-app DB=<?= htmlspecialchars($dbVersion, ENT_QUOTES) ?> -->
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>php-image-builder — demo stack</title>
    <link rel="stylesheet" href="/demo.css">
</head>
<body>
<h1>Demo stack running</h1>

<p class="lead">
    Three containers: the official <code>nginx</code> with the template from
    <code>tests/nginx/templates/</code>, <code>phpfpm</code> from this repo,
    and the official <code>mariadb</code>. No custom nginx build, no custom
    database build.
</p>

<h2>Database</h2>
<table>
    <tr>
        <th>SELECT VERSION()</th>
        <td class="<?= str_starts_with($dbVersion, DB_ERROR_PREFIX) ? 'bad' : 'good' ?>">
            <?= htmlspecialchars($dbVersion, ENT_QUOTES) ?>
        </td>
    </tr>
</table>

<h2>PHP runtime — set by the image's APP_ENV profile</h2>
<table>
    <?php foreach (runtimeFacts() as $key => $value): ?>
        <tr>
            <th><?= htmlspecialchars((string) $key, ENT_QUOTES) ?></th>
            <td><?= htmlspecialchars((string) $value, ENT_QUOTES) ?></td>
        </tr>
    <?php endforeach; ?>
</table>

<h2>From the nginx template — $_SERVER</h2>
<table>
    <?php foreach (templateFacts() as $key => $value): ?>
        <tr>
            <th><?= htmlspecialchars((string) $key, ENT_QUOTES) ?></th>
            <td><?= htmlspecialchars((string) $value, ENT_QUOTES) ?></td>
        </tr>
    <?php endforeach; ?>
</table>

<p class="hint">
    More entry points: <a href="/index.php/any/path">/index.php/any/path</a>
    shows <code>PATH_INFO</code>, <a href="/health.txt">/health.txt</a> is
    served by nginx directly (without PHP) and carries its healthcheck.
</p>
</body>
</html>
