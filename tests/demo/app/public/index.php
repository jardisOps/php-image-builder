<?php

/**
 * Demo-Anwendung des Stacks aus tests/demo/demo-stack.yml (P10).
 *
 * Zweck: zeigen, dass die drei Teile wirklich zusammenspielen — das offizielle
 * nginx mit unserer Vorlage aus P9, headgent/phpfpm und das offizielle
 * mariadb. Sie zeigt deshalb nur, was der Stack beweisen soll, und ist kein
 * Anwendungsgeruest: keine Abhaengigkeiten, kein Autoloader, kein Framework.
 *
 * KEINE VORLAGE FUER PRODUKTIVCODE. Diese Seite gibt absichtlich aus, was eine
 * Anwendung fuer sich behalten muesste — die Fehlermeldung der Datenbank samt
 * Benutzer und Herkunfts-IP, die Laufzeitkonfiguration und die
 * Prozesskennung. Das ist ihr Zweck: ein Demo-Stack, der eine gescheiterte
 * Verbindung als leeres Feld zeigt, meldet Erfolg, wo keiner ist. Wer von hier
 * abschreibt, laesst genau diese Ausgaben weg.
 *
 * Die Ausgabe ist zugleich der Messpunkt von tests/check-demo-stack.sh.
 * Wer hier Marken (PROBE=..., DB=...) umbenennt, zieht dort nach.
 */

declare(strict_types=1);

/** Praefix, an dem die Ausgabe eine gescheiterte Verbindung erkennt. */
const DB_ERROR_PREFIX = 'FEHLER: ';

/**
 * Verbindet zur Demo-Datenbank und gibt ihre Serverkennung zurueck.
 *
 * Bei einem Fehler ist der Rueckgabewert die Meldung mit DB_ERROR_PREFIX davor
 * — der Aufrufer unterscheidet daran, nicht an einem leeren Feld.
 */
function databaseVersion(): string
{
    // Kein Default fuer die Zugangsdaten: ein hartkodierter Wert im Code kann
    // die Konfiguration still ueberstimmen — genau der Defekt, den dieses Repo
    // an anderer Stelle als D16 aufgehoben hat. Fehlt ein Wert, wird das
    // gemeldet und nicht geraten.
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
        return DB_ERROR_PREFIX . 'nicht gesetzt: ' . implode(', ', $missing);
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

/** Die Laufzeitwerte, die das APP_ENV-Profil des Images gesetzt hat (A10). */
function runtimeFacts(): array
{
    $jit = ini_get('opcache.jit');

    return [
        'PHP'                        => PHP_VERSION,
        'SAPI'                       => PHP_SAPI,
        'APP_ENV'                    => getenv('APP_ENV') ?: '<nicht gesetzt>',
        'opcache.enable'             => ini_get('opcache.enable'),
        'opcache.validate_timestamps' => ini_get('opcache.validate_timestamps'),
        'opcache.jit'                => ($jit === '' || $jit === false) ? '<leer>' : $jit,
        'xdebug.mode'                => extension_loaded('xdebug') ? ini_get('xdebug.mode') : '<nicht geladen>',
        'pcov.enabled'               => extension_loaded('pcov') ? ini_get('pcov.enabled') : '<nicht geladen>',
        'max_execution_time'         => ini_get('max_execution_time'),
        'memory_limit'               => ini_get('memory_limit'),
        // posix ist in unseren Images vorhanden, aber nicht in jedem PHP-Build
        // — ohne die Pruefung waere die ganze Seite ein Fatal Error statt einer
        // fehlenden Zeile.
        'Prozesskennung'             => function_exists('posix_geteuid')
            ? sprintf('%s:%s', posix_geteuid(), posix_getegid())
            : '<posix nicht geladen>',
    ];
}

/**
 * Die $_SERVER-Werte, die aus der nginx-Vorlage stammen (A6/A8.3).
 *
 * HTTPS steht bewusst mit dabei: bei REQUEST_SCHEME=http darf der Schluessel
 * gar nicht ankommen — das war im Bestand fest auf "on" verdrahtet und damit
 * ohne TLS-Proxy falsch (A6.2).
 */
function templateFacts(): array
{
    $keys = [
        'SERVER_NAME', 'REQUEST_SCHEME', 'HTTPS', 'HTTP_X_FORWARDED_PROTO',
        'DOCUMENT_ROOT', 'SCRIPT_FILENAME', 'PATH_INFO', 'REQUEST_URI',
    ];

    $facts = [];
    foreach ($keys as $key) {
        $facts[$key] = $_SERVER[$key] ?? '<nicht uebergeben>';
    }

    return $facts;
}

$dbVersion = databaseVersion();

// Maschinenlesbare Zeile fuer den Prueflauf. Sie steht vor dem HTML, damit sie
// unabhaengig von jeder Darstellung greifbar bleibt.
header('Content-Type: text/html; charset=utf-8');

?>
<!-- PROBE=demo-app DB=<?= htmlspecialchars($dbVersion, ENT_QUOTES) ?> -->
<!doctype html>
<html lang="de">
<head>
    <meta charset="utf-8">
    <title>php-image-builder — Demo-Stack</title>
    <link rel="stylesheet" href="/demo.css">
</head>
<body>
<h1>Demo-Stack laeuft</h1>

<p class="lead">
    Drei Container: das offizielle <code>nginx</code> mit der Vorlage aus
    <code>tests/nginx/templates/</code>, <code>phpfpm</code> aus diesem Repo
    und das offizielle <code>mariadb</code>. Kein eigener nginx-Build, kein
    eigener Datenbank-Build.
</p>

<h2>Datenbank</h2>
<table>
    <tr>
        <th>SELECT VERSION()</th>
        <td class="<?= str_starts_with($dbVersion, DB_ERROR_PREFIX) ? 'bad' : 'good' ?>">
            <?= htmlspecialchars($dbVersion, ENT_QUOTES) ?>
        </td>
    </tr>
</table>

<h2>PHP-Laufzeit — gesetzt vom APP_ENV-Profil des Images</h2>
<table>
    <?php foreach (runtimeFacts() as $key => $value): ?>
        <tr>
            <th><?= htmlspecialchars((string) $key, ENT_QUOTES) ?></th>
            <td><?= htmlspecialchars((string) $value, ENT_QUOTES) ?></td>
        </tr>
    <?php endforeach; ?>
</table>

<h2>Aus der nginx-Vorlage — $_SERVER</h2>
<table>
    <?php foreach (templateFacts() as $key => $value): ?>
        <tr>
            <th><?= htmlspecialchars((string) $key, ENT_QUOTES) ?></th>
            <td><?= htmlspecialchars((string) $value, ENT_QUOTES) ?></td>
        </tr>
    <?php endforeach; ?>
</table>

<p class="hint">
    Weitere Einstiege: <a href="/index.php/beliebig/pfad">/index.php/beliebig/pfad</a>
    zeigt <code>PATH_INFO</code>, <a href="/health.txt">/health.txt</a> wird von
    nginx direkt ausgeliefert (ohne PHP) und traegt dessen Healthcheck.
</p>
</body>
</html>
